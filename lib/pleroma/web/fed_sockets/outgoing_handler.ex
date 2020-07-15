# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.OutgoingHandler do
  require Logger
  alias Pleroma.Web.ActivityPub.InternalFetchActor
  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedSocket
  alias Pleroma.Web.FedSockets.SocketInfo

  def start_link(origin) do
    uri_string = SocketInfo.uri_for_origin(origin)

    case initiate_connection(uri_string) do
      {:ok, socket_info} ->
        {:ok, socket_info}

      {:error, reason} ->
        Logger.debug("Outgoing connection failed - #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_frame({:text, data}, %{origin: origin} = state) do
    {:ok, fs} = FedRegistry.get_fed_socket(origin)

    case FedSocket.receive_package(fs, data) do
      {:noreply, _} ->
        {:ok, state}

      {:reply, reply} ->
        {:reply, {:text, Jason.encode!(reply)}, state}

      {:error, reason} ->
        Logger.error("incoming error - receive_package: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_frame(other, state) do
    Logger.warn("outgoing unknown handle_frame: #{inspect(other)}")
    {:ok, state}
  end

  def handle_info(:close, state) do
    Logger.debug("Sending close frame !!!!!!!")
    {:close, state}
  end

  def handle_info({:send, data}, state) do
    {:reply, {:text, data}, state}
  end

  def handle_info(:ping, state), do: {:reply, :ping, state}

  def handle_info(_, state), do: {:ok, state}

  def handle_pong(_pong, state), do: {:ok, state}

  def handle_ping(_ping, state), do: {:reply, :pong, state}

  def handle_connect(_conn, state), do: {:ok, state}

  def handle_disconnect(_conn, state), do: {:ok, state}

  def terminate(_reason, state) do
    Logger.error("#{__MODULE__} terminating outgoing connection for #{inspect(state)}")
    exit(:normal)
  end

  def initiate_connection(uri_string) do
    uri = %{host: host} = URI.parse(uri_string)

    case WebSockex.start_link(uri_string, __MODULE__, %{origin: SocketInfo.origin(uri_string)},
           extra_headers: build_headers(host),
           socket_connect_timeout: 60_000,
           socket_recv_timeout: 60_000
         ) do
      {:ok, pid} ->
        {:ok, SocketInfo.outgoing(pid, uri)}

      {:error, e} ->
        {:error, e}
    end
  end

  defp build_headers(host) do
    shake = FedSocket.shake()
    digest = "SHA-256=" <> (:crypto.hash(:sha256, shake) |> Base.encode64())
    date = Pleroma.Signature.signed_date()

    signature_opts = %{
      "(request-target)": shake,
      host: host,
      "content-length": byte_size(shake),
      digest: digest,
      date: date
    }

    signature = Pleroma.Signature.sign(InternalFetchActor.get_actor(), signature_opts)

    [
      {"signature", signature},
      {"date", date},
      {"digest", digest},
      {"content-length", byte_size(shake)},
      {"(request-target)", shake}
    ]
  end
end
