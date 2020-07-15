# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.IncomingHandler do
  require Logger

  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedSocket
  alias Pleroma.Web.FedSockets.SocketInfo

  import HTTPSignatures, only: [validate_conn: 1, split_signature: 1]

  @behaviour :cowboy_websocket
  @timeout :infinity

  def init(req, state) do
    shake = FedSocket.shake()

    with true <- Pleroma.Config.get([:fed_sockets, :enabled]),
         sec_protocol <- :cowboy_req.header("sec-websocket-protocol", req, nil),
         headers = %{"(request-target)" => ^shake} <- :cowboy_req.headers(req),
         true <- validate_conn(%{req_headers: headers}),
         %{"keyId" => origin} <- split_signature(headers["signature"]) do
      req =
        if is_nil(sec_protocol) do
          req
        else
          :cowboy_req.set_resp_header("sec-websocket-protocol", sec_protocol, req)
        end

      {:cowboy_websocket, req, %{origin: origin}, %{idle_timeout: @timeout}}
    else
      _ ->
        {:ok, req, state}
    end
  end

  def websocket_init(%{origin: origin} = state) do
    sckt = SocketInfo.incoming(self(), origin)

    with {:connect, {:ok, fed_socket}} <- {:connect, FedSocket.connection_from_host(sckt)},
         {:register, {:ok, fed_socket}} <- {:register, FedRegistry.add_fed_socket(fed_socket)} do
      Logger.debug("incoming FedSocket created for - #{inspect(origin)}")
      {:ok, Map.put(state, :fed_socket, fed_socket)}
    else
      {mode, {:error, e}} ->
        Logger.error("FedSocket init failed in #{mode}- #{inspect(e)}")
        {:error, inspect(e)}

      {mode, e} ->
        Logger.error("FedSocket init failed in #{mode} - #{inspect(e)}")
        {:error, inspect(e)}
    end
  end

  # Replying to ping is handled by cowboy
  def websocket_handle(:ping, state) do
    {:ok, state}
  end

  def websocket_handle(:pong, state) do
    {:ok, state}
  end

  def websocket_handle({:text, data}, %{fed_socket: fed_socket} = state) do
    case FedSocket.receive_package(fed_socket, data) do
      {:noreply, _} ->
        {:ok, state}

      {:reply, reply} ->
        {:reply, {:text, Jason.encode!(reply)}, state}

      {:error, reason} ->
        Logger.error("incoming error - receive_package: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def websocket_info({:send, message}, state) do
    {:reply, {:text, message}, state}
  end

  def websocket_info(:close, state) do
    {:stop, state}
  end

  def websocket_info(message, state) do
    Logger.debug("#{__MODULE__} unknown message #{inspect(message)}")
    {:ok, state}
  end

  def terminate(reason, _req, _state) do
    Logger.debug("#{__MODULE__} terminating incoming connection for #{inspect(reason)}")

    :ok
  end
end
