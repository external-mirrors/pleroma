# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.SweeperTest do
  use ExUnit.Case

  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedSocket

  setup do
    start_supervised(
      {Pleroma.Web.FedSockets.Supervisor,
       [
         ping_interval: 8,
         connection_duration: 15,
         rejection_duration: 5
       ]}
    )

    :ok
  end

  describe "ping functionality" do
    test "pings outgoing fedsockets" do
      %{pid: socket_pid} = fs = build_socket("good.domain", :outgoing)
      :erlang.trace(socket_pid, true, [:receive])

      FedRegistry.add_fed_socket(fs)
      Process.sleep(10)
      assert_receive {:trace, ^socket_pid, :receive, :ping}
    end

    test "does not ping incoming fedsockets" do
      %{pid: socket_pid} = fs = build_socket("good.domain", :incoming)
      :erlang.trace(socket_pid, true, [:receive])

      FedRegistry.add_fed_socket(fs)
      Process.sleep(10)

      refute_receive {:trace, ^socket_pid, :receive, :ping}
    end
  end

  describe "expiration functionality" do
    setup do
      {:ok, fed_socket} =
        "good.domain"
        |> build_socket(:incoming)
        |> FedRegistry.add_fed_socket()

      {:ok, fed_socket: fed_socket}
    end

    test "new expire", %{fed_socket: %{origin: origin}} do
      Process.sleep(20)
      assert {:error, :missing} = FedRegistry.get_fed_socket(origin)
    end

    test "inactive fedsockets expire", %{fed_socket: %{origin: origin} = fed_socket} do
      Process.sleep(10)
      FedRegistry.touch(fed_socket)
      Process.sleep(10)
      assert {:ok, _fs} = FedRegistry.get_fed_socket(origin)
      Process.sleep(20)

      assert {:error, :missing} = FedRegistry.get_fed_socket(origin)
    end

    test "active fedsockets expire do not expire", %{fed_socket: %{origin: origin} = fed_socket} do
      Process.sleep(10)
      FedRegistry.touch(fed_socket)
      Process.sleep(10)
      FedRegistry.touch(fed_socket)
      Process.sleep(10)

      assert {:ok, _fs} = FedRegistry.get_fed_socket(origin)
    end
  end

  describe "rejection caching functionality" do
    test "rejected domains are cached" do
      {:ok, %{origin: origin}} = FedRegistry.set_host_rejected("good.domain")
      assert {:error, :rejected} = FedRegistry.get_fed_socket(origin)
    end

    test "cached rejected domains eventually expire" do
      {:ok, %{origin: origin}} = FedRegistry.set_host_rejected("bad.domain")
      assert {:error, :rejected} = FedRegistry.get_fed_socket(origin)
      Process.sleep(10)

      assert {:error, :missing} = FedRegistry.get_fed_socket(origin)
    end

    test "rejected domains expiration is extended" do
      {:ok, %{origin: origin}} = FedRegistry.set_host_rejected("bad.domain")
      assert {:error, :rejected} = FedRegistry.get_fed_socket(origin)
      Process.sleep(4)
      {:ok, %{origin: origin}} = FedRegistry.set_host_rejected("bad.domain")
      Process.sleep(4)

      assert {:error, :rejected} = FedRegistry.get_fed_socket(origin)
    end
  end

  def build_socket(origin, type) do
    pid = Kernel.spawn(&fed_socket_almost/0)
    assert(type in [:incoming, :outgoing])

    %FedSocket{
      origin: origin,
      pid: pid,
      type: type
    }
  end

  def fed_socket_almost do
    receive do
      :close ->
        :ok

      :ping ->
        :ok
    after
      5_000 -> :timeout
    end
  end
end
