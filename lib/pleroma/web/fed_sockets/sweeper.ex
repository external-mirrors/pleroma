# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.Sweeper do
  use GenServer

  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedRegistry.RegistryData
  alias Pleroma.Web.FedSockets.FedSocket

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, initial_data(opts), name: __MODULE__)
  end

  def init(opts) do
    schedule_next_ping(opts)
    {:ok, opts}
  end

  def handle_info(
        :sweep,
        %{connection_duration: connection_duration, rejection_duration: rejection_duration} =
          state
      ) do
    schedule_next_ping(state)

    time_now = :os.system_time(:millisecond)
    expire_time = time_now - connection_duration
    release_time = time_now - rejection_duration

    for reg_item <- FedRegistry.list_all() do
      if is_connected?(reg_item) do
        maybe_expire_or_ping(reg_item, expire_time)
      else
        maybe_release(reg_item, release_time)
      end
    end

    {:noreply, state}
  end

  defp schedule_next_ping(%{ping_interval: ping_interval}) do
    Process.send_after(self(), :sweep, ping_interval, [])
  end

  defp is_connected?(%RegistryData{rejected_at: nil, connected: true}), do: true
  defp is_connected?(_reg_data), do: false

  defp maybe_release(
         %RegistryData{rejected_at: rejected_at, origin: origin},
         release_time
       )
       when rejected_at < release_time,
       do: FedRegistry.delete_host(origin)

  defp maybe_release(unswept, _release_time),
    do: unswept

  defp maybe_expire_or_ping(
         %RegistryData{last_message: nil, created_at: created_at, fed_socket: fed_socket},
         expire_time
       )
       when created_at < expire_time,
       do: FedSocket.close(fed_socket)

  defp maybe_expire_or_ping(
         %RegistryData{last_message: last_message, fed_socket: fed_socket},
         expire_time
       )
       when last_message < expire_time,
       do: FedSocket.close(fed_socket)

  defp maybe_expire_or_ping(
         %RegistryData{fed_socket: %{type: :outgoing} = fed_socket},
         _expire_time
       ),
       do: FedSocket.ping(fed_socket)

  defp maybe_expire_or_ping(%RegistryData{fed_socket: _fed_socket} = unswept, _expire_time),
    do: unswept

  defp initial_data(opts) do
    %{
      connection_duration: get_from_opts_or_config(opts, :connection_duration, :timer.hours(24)),
      rejection_duration: get_from_opts_or_config(opts, :rejection_duration, :timer.hours(24)),
      ping_interval: get_from_opts_or_config(opts, :ping_interval, :timer.seconds(15))
    }
  end

  defp get_from_opts_or_config(opts, key, default) do
    case Keyword.get(opts, key) do
      nil ->
        Pleroma.Config.get(
          [:fed_sockets, key],
          default
        )

      value ->
        value
    end
  end
end
