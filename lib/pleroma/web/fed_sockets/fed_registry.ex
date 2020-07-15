# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.FedRegistry do
  @moduledoc """
  The FedRegistry stores the active FedSockets for quick retrieval and cleans up after closed or broken connections.

  The storage and retrieval portion of the FedRegistry is done in process through ETS for maximum speed.
  The FedRegistry goes out of process to start monitoring new FedSockets, so there is a slight one time delay.

  Dropped connections will be caught here and deleted from the registry. Since the next
  message will initiate a new connection there is no reason to try and recononect at that point.

  Normally outside modules will have no need to call or use the FedRegistry themselves.
  """

  defmodule RegistryData do
    defstruct fed_socket: nil,
              origin: nil,
              rejected_at: nil,
              created_at: nil,
              last_message: nil,
              process_ref: nil,
              connected: false
  end

  use GenServer

  alias Pleroma.Web.FedSockets.FedSocket

  require Logger

  @origins :fed_socket_origins

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Retrieves a FedSocket from the Registry given it's origin.

  The origin is expected to be a string identifying the endpoint "example.com" or "example2.com:8080"

  Will return:
    * {:ok, fed_socket} for working FedSockets
    * {:error, :rejected} for origins that have been tried and refused within the rejection duration interval
    * {:error, some_reason} usually :missing for unknown origins
  """
  def get_fed_socket(origin) do
    case get_registry_data(origin) do
      {:error, reason} ->
        {:error, reason}

      {:ok, %{rejected_at: rejected_at}} when not is_nil(rejected_at) ->
        {:error, :rejected}

      {:ok, %{connected: true, fed_socket: fed_socket}} ->
        {:ok, fed_socket}

      {:ok, %{fed_socket: fed_socket} = item} ->
        Logger.warn("Registered fedsocket neither rejected nor connected - #{inspect(item)}")
        {:ok, fed_socket}
    end
  end

  @doc """
  Adds a FedSocket to the Registry.

  Always returns {:ok, fed_socket}
  """
  def add_fed_socket(%FedSocket{} = fed_socket) do
    GenServer.call(__MODULE__, {:add_fed_socket, fed_socket})
  end

  @doc """
  Indicates to the FedRegistry some activity related to the Given FedSocket.
  This will prevent the connection from being timed out.

  Always returns {:ok, fed_socket} or {:error, :missing} if the origin is unknown
  """
  def touch(%FedSocket{origin: origin}) do
    case get_registry_data(origin) do
      {:ok, %RegistryData{} = reg_data} ->
        reg_data =
          reg_data
          |> update_last_message()
          |> save_registry_data()

        {:ok, reg_data}

      {:error, _} ->
        Logger.warn("tried to refresh missing host - #{origin}")
        {:error, :missing}
    end
  end

  @doc """
  This deletes the given origin from the FedRegistry.
  If there is an associated connection it will be closed.

  Always returns :ok or :error if no deletion can be done
  """
  def delete_host(origin) do
    case get_registry_data(origin) do
      {:ok, %RegistryData{fed_socket: nil}} ->
        delete_registry_data(origin)
        :ok

      {:ok, %RegistryData{fed_socket: fed_socket}} ->
        FedSocket.close(fed_socket)
        :ok

      {:error, _} ->
        Logger.warn("tried to delete missing host - #{origin}")
        :error
    end
  end

  @doc """
  Mark this origin as having rejected a connection attempt.
  This will keep it from getting additional connection attempts
  for a period of time specified in the config.

  Always returns {:ok, new_reg_data}
  """
  def set_host_rejected(origin) do
    new_reg_data =
      origin
      |> get_or_create_registry_data()
      |> set_to_rejected()
      |> save_registry_data()

    {:ok, new_reg_data}
  end

  @doc """
  Retrieves the FedRegistryData from the Registry given it's origin.

  The origin is expected to be a string identifying the endpoint "example.com" or "example2.com:8080"

  Will return:
    * {:ok, fed_registry_data} for known origins
    * {:error, :missing} for uniknown origins
    * {:error, :cache_error} indicating some low level runtime issues
  """
  def get_registry_data(origin) do
    case Cachex.get(@origins, origin) do
      {:ok, nil} ->
        {:error, :missing}

      {:ok, reg_data} ->
        {:ok, reg_data}

      _ ->
        {:error, :cache_error}
    end
  end

  @doc """
  Retrieves all of the FedRegistryData from the Registry.
  """
  def list_all do
    Cachex.keys!(@origins)
    |> Enum.map(&Cachex.get!(@origins, &1))
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def handle_call(
        {:add_fed_socket, %FedSocket{origin: origin} = fed_socket},
        _from,
        state
      ) do
    reg_data =
      origin
      |> get_or_create_registry_data()
      |> set_to_connected()

    new_state = save_maybe_attach_process(state, reg_data, fed_socket)

    {:reply, {:ok, fed_socket}, new_state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    new_state =
      case Map.get(state, ref) do
        nil ->
          Logger.warn("DOWN reference received for missing process")
          state

        origin ->
          delete_registry_data(origin)
          Logger.debug("DOWN reference caused Registry deletion")

          Map.delete(state, ref)
      end

    {:noreply, new_state}
  end

  defp get_or_create_registry_data(origin) do
    case Cachex.get(@origins, origin) do
      {:ok, nil} ->
        %RegistryData{
          origin: origin,
          created_at: :os.system_time(:millisecond)
        }

      {:ok, reg_data} ->
        reg_data
    end
  end

  defp save_maybe_attach_process(
         state,
         %RegistryData{fed_socket: nil, origin: origin} = reg_data,
         %FedSocket{} = fed_socket
       ) do
    %RegistryData{process_ref: process_ref} =
      reg_data
      |> attach_and_monitor(fed_socket)
      |> save_registry_data()

    Map.put(state, process_ref, origin)
  end

  defp save_maybe_attach_process(
         state,
         %RegistryData{
           fed_socket: %FedSocket{pid: old_pid} = old_fed_socket,
           origin: origin,
           process_ref: old_process_ref
         } = reg_data,
         %FedSocket{pid: socket_pid} = fed_socket
       )
       when old_pid != socket_pid do
    Process.demonitor(old_process_ref, [:flush])
    FedSocket.close(old_fed_socket)

    state = Map.delete(state, old_process_ref)

    %RegistryData{process_ref: process_ref} =
      reg_data
      |> attach_and_monitor(fed_socket)
      |> save_registry_data()

    Map.put(state, process_ref, origin)
  end

  defp save_maybe_attach_process(state, reg_data, _fed_socket) do
    save_registry_data(reg_data)
    state
  end

  defp save_registry_data(%RegistryData{origin: origin} = reg_data) do
    {:ok, true} = Cachex.put(@origins, origin, reg_data)
    reg_data
  end

  defp attach_and_monitor(%RegistryData{} = reg_data, %FedSocket{pid: socket_pid} = fed_socket) do
    process_ref = Process.monitor(socket_pid)
    %RegistryData{reg_data | fed_socket: fed_socket, process_ref: process_ref}
  end

  defp delete_registry_data(origin),
    do: {:ok, true} = Cachex.del(@origins, origin)

  defp set_to_connected(%RegistryData{} = reg_data),
    do: %RegistryData{reg_data | rejected_at: nil, connected: true}

  defp set_to_rejected(%RegistryData{} = reg_data),
    do: %RegistryData{reg_data | rejected_at: :os.system_time(:millisecond)}

  defp update_last_message(%RegistryData{} = reg_data),
    do: %RegistryData{reg_data | last_message: :os.system_time(:millisecond)}
end
