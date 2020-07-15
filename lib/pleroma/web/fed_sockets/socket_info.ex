# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.SocketInfo do
  defstruct pid: nil, origin: nil, type: nil

  alias Pleroma.Web.FedSockets.SocketInfo

  def outgoing(pid, uri),
    do: %{build_socket_info(uri) | pid: pid, type: :outgoing}

  def incoming(pid, uri),
    do: %{build_socket_info(uri) | pid: pid, type: :incoming}

  def origin(uri),
    do: build_socket_info(uri).origin

  def uri_for_origin(origin),
    do: "ws://#{origin}/fedsocket"

  defp build_socket_info(uri) when is_binary(uri),
    do: URI.parse(uri) |> build_socket_info

  defp build_socket_info(%{host: host, port: nil}),
    do: %SocketInfo{origin: host}

  defp build_socket_info(%{host: host, port: 80}),
    do: %SocketInfo{origin: host}

  defp build_socket_info(%{host: host, port: port}),
    do: %SocketInfo{origin: "#{host}:#{port}"}
end
