# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.SafeStream do
  alias Pleroma.ReverseProxy.Client.Wrapper, as: Client

  @redirect_statuses [301, 302, 303, 307, 308]
  @default_timeout 5_000
  @default_redirects 3
  @blocked_ipv4 Enum.map(
                  [
                    "0.0.0.0/8",
                    "10.0.0.0/8",
                    "100.64.0.0/10",
                    "127.0.0.0/8",
                    "169.254.0.0/16",
                    "172.16.0.0/12",
                    "192.0.0.0/24",
                    "192.0.2.0/24",
                    "192.88.99.0/24",
                    "192.168.0.0/16",
                    "198.18.0.0/15",
                    "198.51.100.0/24",
                    "203.0.113.0/24",
                    "224.0.0.0/4",
                    "240.0.0.0/4"
                  ],
                  &InetCidr.parse_cidr!(&1, true)
                )
  @blocked_ipv6 Enum.map(
                  [
                    "::/128",
                    "::1/128",
                    "::ffff:0:0/96",
                    "64:ff9b::/96",
                    "64:ff9b:1::/48",
                    "100::/64",
                    "2001::/23",
                    "2001:db8::/32",
                    "2002::/16",
                    "3fff::/20",
                    "fc00::/7",
                    "fe80::/10",
                    "ff00::/8"
                  ],
                  &InetCidr.parse_cidr!(&1, true)
                )
  @global_ipv6 InetCidr.parse_cidr!("2000::/3", true)

  @callback fetch_prefix(String.t(), pos_integer(), keyword()) ::
              {:ok, binary()} | {:error, term()}

  @spec fetch_prefix(String.t(), pos_integer(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def fetch_prefix(url, limit, opts \\ []) when is_binary(url) and limit > 0 do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    deadline = Keyword.get(opts, :deadline, now() + timeout)
    resolver = Keyword.get(opts, :resolver, &resolve/1)
    redirects = Keyword.get(opts, :max_redirects, @default_redirects)
    headers = Keyword.get(opts, :headers, [])

    request_opts =
      opts
      |> Keyword.drop([:deadline, :headers, :max_redirects, :resolver, :timeout])
      |> Keyword.put(:follow_redirect, false)
      |> Keyword.put_new(:pool, :media)

    case within_deadline(
           fn -> fetch(url, limit, headers, request_opts, resolver, redirects, deadline) end,
           deadline
         ) do
      {:ok, result} -> result
      error -> error
    end
  rescue
    _ -> {:error, :request_failed}
  catch
    _, _ -> {:error, :request_failed}
  end

  @spec validate_url(String.t(), (String.t() -> {:ok, [tuple()]} | {:error, term()})) ::
          :ok | {:error, term()}
  def validate_url(url, resolver \\ &resolve/1) do
    deadline = now() + @default_timeout

    case within_deadline(fn -> validate_url(url, resolver, deadline) end, deadline) do
      {:ok, result} -> result
      error -> error
    end
  end

  defp fetch(url, limit, headers, request_opts, resolver, redirects, deadline) do
    with {:ok, client} <- open(url, headers, request_opts, resolver, redirects, deadline) do
      read_prefix(client, "", limit, deadline)
    end
  end

  defp validate_url(url, resolver, deadline) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and is_integer(uri.port) and uri.port in 1..65_535 do
      with {:ok, addresses} <- addresses(uri.host, resolver, deadline) do
        if addresses != [] and Enum.all?(addresses, &public_address?/1) do
          :ok
        else
          {:error, :private_address}
        end
      end
    else
      {:error, :invalid_url}
    end
  rescue
    _ -> {:error, :invalid_url}
  end

  defp open(url, headers, request_opts, resolver, redirects, deadline) do
    with :ok <- remaining(deadline),
         :ok <- validate_url(url, resolver, deadline),
         :ok <- remaining(deadline),
         response <-
           Client.request(:get, url, headers, "", with_timeouts(request_opts, deadline)) do
      handle_response(response, url, headers, request_opts, resolver, redirects, deadline)
    end
  end

  defp handle_response(
         {:ok, status, headers, client},
         url,
         request_headers,
         request_opts,
         resolver,
         redirects,
         deadline
       )
       when status in @redirect_statuses do
    close(client)

    follow_redirect(
      headers,
      url,
      request_headers,
      request_opts,
      resolver,
      redirects,
      deadline
    )
  end

  defp handle_response(
         {:ok, status, headers},
         url,
         request_headers,
         request_opts,
         resolver,
         redirects,
         deadline
       )
       when status in @redirect_statuses do
    follow_redirect(
      headers,
      url,
      request_headers,
      request_opts,
      resolver,
      redirects,
      deadline
    )
  end

  defp handle_response({:ok, status, _headers, client}, _, _, _, _, _, _)
       when status in [200, 206],
       do: {:ok, client}

  defp handle_response({:ok, status, _headers, client}, _, _, _, _, _, _) do
    close(client)
    {:error, {:http_status, status}}
  end

  defp handle_response({:ok, status, _headers}, _, _, _, _, _, _),
    do: {:error, {:http_status, status}}

  defp handle_response({:error, _} = error, _, _, _, _, _, _), do: error
  defp handle_response(_, _, _, _, _, _, _), do: {:error, :request_failed}

  defp follow_redirect(_headers, _url, _request_headers, _opts, _resolver, 0, _deadline),
    do: {:error, :too_many_redirects}

  defp follow_redirect(
         headers,
         url,
         request_headers,
         request_opts,
         resolver,
         redirects,
         deadline
       ) do
    with {:ok, location} <- header(headers, "location"),
         redirect_url <- url |> URI.parse() |> URI.merge(location) |> URI.to_string() do
      request_headers = redirect_headers(request_headers, url, redirect_url)
      open(redirect_url, request_headers, request_opts, resolver, redirects - 1, deadline)
    else
      _ -> {:error, :invalid_redirect}
    end
  rescue
    _ -> {:error, :invalid_redirect}
  end

  defp read_prefix(client, data, limit, _deadline) when byte_size(data) >= limit do
    close(client)
    {:ok, data}
  end

  defp read_prefix(client, data, limit, deadline) do
    case remaining(deadline) do
      :ok ->
        case Client.stream_body(client) do
          {:ok, chunk, next_client} when is_binary(chunk) ->
            retain_chunk(next_client, data, chunk, limit, deadline)

          {:ok, _chunk, next_client} ->
            close(next_client)
            {:error, :invalid_chunk}

          :done when data != "" ->
            {:ok, data}

          :done ->
            {:error, :empty_body}

          {:error, reason} ->
            close(client)
            {:error, reason}
        end

      error ->
        close(client)
        error
    end
  rescue
    _ ->
      close(client)
      {:error, :request_failed}
  catch
    _, _ ->
      close(client)
      {:error, :request_failed}
  end

  defp retain_chunk(client, data, chunk, limit, deadline) do
    try do
      remaining_bytes = limit - byte_size(data)
      retained = binary_part(chunk, 0, min(byte_size(chunk), remaining_bytes)) |> :binary.copy()
      read_prefix(client, data <> retained, limit, deadline)
    rescue
      _ ->
        close(client)
        {:error, :invalid_chunk}
    catch
      _, _ ->
        close(client)
        {:error, :invalid_chunk}
    end
  end

  defp within_deadline(fun, deadline) do
    with :ok <- remaining(deadline) do
      caller = self()
      reply_ref = make_ref()

      {pid, monitor_ref} =
        spawn_monitor(fn ->
          result =
            try do
              {:ok, fun.()}
            rescue
              _ -> {:error, :request_failed}
            catch
              _, _ -> {:error, :request_failed}
            end

          send(caller, {reply_ref, result, now()})
        end)

      receive do
        {^reply_ref, result, finished_at} when finished_at <= deadline ->
          Process.demonitor(monitor_ref, [:flush])
          result

        {^reply_ref, _result, _finished_at} ->
          Process.demonitor(monitor_ref, [:flush])
          {:error, :timeout}

        {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
          {:error, :request_failed}
      after
        max(deadline - now(), 1) ->
          Process.exit(pid, :kill)
          await_down(monitor_ref, pid)
          flush_reply(reply_ref)
          {:error, :timeout}
      end
    end
  end

  defp await_down(monitor_ref, pid) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    end
  end

  defp flush_reply(reply_ref) do
    receive do
      {^reply_ref, _result, _finished_at} -> :ok
    after
      0 -> :ok
    end
  end

  defp with_timeouts(opts, deadline) do
    timeout = max(deadline - now(), 1)

    opts
    |> Keyword.update(:connect_timeout, timeout, &min(&1, timeout))
    |> Keyword.update(:recv_timeout, timeout, &min(&1, timeout))
  end

  defp remaining(deadline) do
    if deadline > now(), do: :ok, else: {:error, :timeout}
  end

  defp header(headers, wanted) do
    case Enum.find(headers, fn {name, _value} -> String.downcase(name) == wanted end) do
      {_name, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_header}
    end
  end

  defp addresses(host, resolver, deadline) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, :einval} ->
        case remaining(deadline) do
          :ok -> resolver.(host)
          error -> error
        end
    end
  end

  defp resolve(host) do
    addresses =
      [:inet, :inet6]
      |> Enum.flat_map(fn family ->
        case :inet.getaddrs(String.to_charlist(host), family) do
          {:ok, found} -> found
          {:error, _} -> []
        end
      end)
      |> Enum.uniq()

    if addresses == [], do: {:error, :nxdomain}, else: {:ok, addresses}
  end

  defp public_address?({_a, _b, _c, _d} = address),
    do: Enum.all?(@blocked_ipv4, &(!InetCidr.contains?(&1, address)))

  defp public_address?({_a, _b, _c, _d, _e, _f, _g, _h} = address),
    do:
      InetCidr.contains?(@global_ipv6, address) and
        Enum.all?(@blocked_ipv6, &(!InetCidr.contains?(&1, address)))

  defp public_address?(_), do: false

  defp close(client) do
    Client.close(client)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp redirect_headers(headers, from, to) do
    if origin(from) == origin(to) do
      headers
    else
      Enum.reject(headers, fn {name, _value} ->
        String.downcase(name) in ["authorization", "cookie", "proxy-authorization"]
      end)
    end
  end

  defp origin(url) do
    uri = URI.parse(url)
    {uri.scheme, uri.host, uri.port}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
