# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.SafeStreamTest do
  use ExUnit.Case

  import Mox

  alias Pleroma.HTTP.SafeStream
  alias Pleroma.ReverseProxy.ClientMock

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global(ClientMock)
    :ok
  end

  defp public_resolver(_host), do: {:ok, [{93, 184, 216, 34}]}

  test "rejects private address literals without requesting them" do
    assert {:error, :private_address} =
             SafeStream.fetch_prefix("http://127.0.0.1/image", 8_192,
               resolver: &public_resolver/1
             )

    assert {:error, :private_address} =
             SafeStream.fetch_prefix("http://[::1]/image", 8_192, resolver: &public_resolver/1)
  end

  test "rejects special-purpose addresses while allowing adjacent public addresses" do
    blocked = [
      "http://192.0.0.1/image",
      "http://[::ffff:7f00:1]/image",
      "http://[2001:20::1]/image",
      "http://[3fff::1]/image",
      "http://[fc00::1]/image",
      "http://[4000::1]/image"
    ]

    Enum.each(blocked, fn url ->
      assert {:error, :private_address} = SafeStream.validate_url(url, &public_resolver/1)
    end)

    assert :ok = SafeStream.validate_url("http://192.0.1.1/image", &public_resolver/1)

    assert :ok =
             SafeStream.validate_url("http://[2606:4700:4700::1111]/image", &public_resolver/1)
  end

  test "rejects redirects to private addresses and closes the redirect response" do
    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", opts ->
      refute opts[:follow_redirect]
      {:ok, 302, [{"location", "http://169.254.169.254/latest"}], %{id: :redirect}}
    end)
    |> expect(:close, fn %{id: :redirect} -> :ok end)

    assert {:error, :private_address} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: &public_resolver/1
             )
  end

  test "follows validated relative redirects and preserves request headers" do
    headers = [{"range", "bytes=0-8191"}]

    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", ^headers, "", _opts ->
      {:ok, 302, [{"location", "/final"}], %{id: :redirect}}
    end)
    |> expect(:close, fn %{id: :redirect} -> :ok end)
    |> expect(:request, fn :get, "https://example.com/final", ^headers, "", _opts ->
      {:ok, 206, [], %{id: :final}}
    end)
    |> expect(:stream_body, fn %{id: :final} ->
      {:ok, "image bytes", %{id: :latest}}
    end)
    |> expect(:stream_body, fn %{id: :latest} -> :done end)

    assert {:ok, "image bytes"} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               headers: headers,
               resolver: &public_resolver/1
             )
  end

  test "strips credentials when following a cross-origin redirect" do
    headers = [
      {"authorization", "Bearer secret"},
      {"cookie", "session=secret"},
      {"range", "bytes=0-8191"}
    ]

    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", ^headers, "", _opts ->
      {:ok, 302, [{"location", "https://cdn.example/image"}], %{id: :redirect}}
    end)
    |> expect(:close, fn %{id: :redirect} -> :ok end)
    |> expect(:request, fn :get,
                           "https://cdn.example/image",
                           [{"range", "bytes=0-8191"}],
                           "",
                           _opts ->
      {:ok, 200, [], %{id: :final}}
    end)
    |> expect(:stream_body, fn %{id: :final} -> :done end)

    assert {:error, :empty_body} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               headers: headers,
               resolver: &public_resolver/1
             )
  end

  test "retains at most the requested prefix and closes the latest client state" do
    body = :binary.copy("a", 16_384)

    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", _opts ->
      {:ok, 200, [], %{id: :initial}}
    end)
    |> expect(:stream_body, fn %{id: :initial} ->
      {:ok, body, %{id: :latest}}
    end)
    |> expect(:close, fn %{id: :latest} -> :ok end)

    assert {:ok, prefix} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: &public_resolver/1
             )

    assert byte_size(prefix) == 8_192
  end

  test "keeps request, body reads, and cleanup in the same owner process" do
    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", _opts ->
      Process.put(:safe_stream_request_owner, self())
      {:ok, 200, [], %{id: :current}}
    end)
    |> expect(:stream_body, fn %{id: :current} ->
      assert Process.get(:safe_stream_request_owner) == self()
      {:ok, "image bytes", %{id: :latest}}
    end)
    |> expect(:close, fn %{id: :latest} ->
      assert Process.get(:safe_stream_request_owner) == self()
      :ok
    end)

    assert {:ok, "image"} =
             SafeStream.fetch_prefix("https://example.com/image", 5, resolver: &public_resolver/1)
  end

  test "does not close a stream that was fully consumed and released" do
    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", _opts ->
      {:ok, 200, [], %{id: :initial}}
    end)
    |> expect(:stream_body, fn %{id: :initial} ->
      {:ok, "short", %{id: :finished, fin: true}}
    end)
    |> expect(:stream_body, fn %{id: :finished, fin: true} -> :done end)

    assert {:ok, "short"} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: &public_resolver/1
             )
  end

  test "rejects hostnames with mixed public and private DNS results" do
    resolver = fn _host -> {:ok, [{93, 184, 216, 34}, {10, 0, 0, 1}]} end

    assert {:error, :private_address} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192, resolver: resolver)
  end

  test "rejects requests after their shared deadline" do
    assert {:error, :timeout} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               deadline: System.monotonic_time(:millisecond) - 1,
               resolver: &public_resolver/1
             )
  end

  test "interrupts slow DNS resolution at the shared deadline" do
    resolver = fn _host ->
      Process.sleep(100)
      {:ok, [{93, 184, 216, 34}]}
    end

    assert {:error, :timeout} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: resolver,
               timeout: 10
             )
  end

  test "interrupts a slow request at the shared deadline" do
    expect(ClientMock, :request, fn :get, "https://example.com/image", _headers, "", _opts ->
      Process.sleep(100)
      {:error, :too_late}
    end)

    assert {:error, :timeout} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: &public_resolver/1,
               timeout: 10
             )
  end

  test "interrupts a slow body read at the shared deadline" do
    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", _opts ->
      {:ok, 200, [], %{id: :current}}
    end)
    |> expect(:stream_body, fn %{id: :current} ->
      Process.sleep(100)
      :done
    end)

    assert {:error, :timeout} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: &public_resolver/1,
               timeout: 10
             )
  end

  test "includes blocking cleanup in the shared deadline" do
    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", _opts ->
      {:ok, 200, [], %{id: :current}}
    end)
    |> expect(:stream_body, fn %{id: :current} ->
      {:ok, "image bytes", %{id: :latest}}
    end)
    |> expect(:close, fn %{id: :latest} ->
      receive do
        :never -> :ok
      end
    end)

    assert {:error, :timeout} =
             SafeStream.fetch_prefix("https://example.com/image", 5,
               resolver: &public_resolver/1,
               timeout: 10
             )
  end

  test "closes the current stream when a body read raises" do
    ClientMock
    |> expect(:request, fn :get, "https://example.com/image", _headers, "", _opts ->
      {:ok, 200, [], %{id: :current}}
    end)
    |> expect(:stream_body, fn %{id: :current} -> raise "boom" end)
    |> expect(:close, fn %{id: :current} -> :ok end)

    assert {:error, :request_failed} =
             SafeStream.fetch_prefix("https://example.com/image", 8_192,
               resolver: &public_resolver/1
             )
  end
end
