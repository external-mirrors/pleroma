# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.FedRegistryTest do
  use ExUnit.Case

  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.FedRegistry.RegistryData
  alias Pleroma.Web.FedSockets.FedSocket

  setup do
    start_supervised({Pleroma.Web.FedSockets.Supervisor, []})

    :ok
  end

  describe "add_fed_socket/1 without conflicting sockets" do
    test "can be added" do
      FedRegistry.add_fed_socket(build_test_socket("good.domain"))
      assert {:ok, %FedSocket{origin: origin}} = FedRegistry.get_fed_socket("good.domain")
      assert origin == "good.domain"
    end

    test "multiple origins can be added" do
      FedRegistry.add_fed_socket(build_test_socket("good.domain"))
      FedRegistry.add_fed_socket(build_test_socket("anothergood.domain"))

      assert {:ok, %FedSocket{origin: origin_1}} = FedRegistry.get_fed_socket("good.domain")

      assert {:ok, %FedSocket{origin: origin_2}} =
               FedRegistry.get_fed_socket("anothergood.domain")

      assert origin_1 == "good.domain"
      assert origin_2 == "anothergood.domain"
      assert FedRegistry.list_all() |> Enum.count() == 2
    end

    test "sockets added duplicate times will be ignored" do
      sckt = build_test_socket("good.domain")
      FedRegistry.add_fed_socket(sckt)
      FedRegistry.add_fed_socket(sckt)

      assert {:ok, %FedSocket{origin: origin}} = FedRegistry.get_fed_socket("good.domain")
      assert origin == "good.domain"

      assert FedRegistry.list_all() |> Enum.count() == 1
    end
  end

  describe "add_fed_socket/1 when duplicate sockets conflict" do
    setup do
      sckt_1 = build_test_socket("good.domain")
      sckt_2 = build_test_socket("good.domain")

      %{sckt_1: sckt_1, sckt_2: sckt_2}
    end

    test "there is only one entry with the original created_at time", %{
      sckt_1: sckt_1,
      sckt_2: sckt_2
    } do
      FedRegistry.add_fed_socket(sckt_1)
      {:ok, %{created_at: first_created_at}} = FedRegistry.get_registry_data("good.domain")
      Process.sleep(2)
      FedRegistry.add_fed_socket(sckt_2)

      {:ok, %{created_at: created_at, origin: origin}} =
        FedRegistry.get_registry_data("good.domain")

      assert origin == "good.domain"
      assert first_created_at == created_at

      assert FedRegistry.list_all() |> Enum.count() == 1
    end

    test "the more recent socket is kept, the older one discarded", %{
      sckt_1: %FedSocket{pid: socket_1_pid} = sckt_1,
      sckt_2: %FedSocket{pid: socket_2_pid} = sckt_2
    } do
      FedRegistry.add_fed_socket(sckt_1)
      Process.sleep(5)
      FedRegistry.add_fed_socket(sckt_2)

      {:ok, %{fed_socket: %FedSocket{pid: socket_pid}}} =
        FedRegistry.get_registry_data("good.domain")

      assert socket_pid == socket_2_pid
      refute socket_pid == socket_1_pid
      assert Process.alive?(socket_2_pid)
      refute Process.alive?(socket_1_pid)

      assert FedRegistry.list_all() |> Enum.count() == 1
    end
  end

  describe "get_fed_socket/1" do
    test "returns missing for unknown hosts" do
      assert {:error, :missing} = FedRegistry.get_fed_socket("not_a_dmoain")
    end

    test "returns rejected for hosts previously rejected" do
      FedRegistry.set_host_rejected("rejected.domain")
      assert {:error, :rejected} = FedRegistry.get_fed_socket("rejected.domain")
    end

    test "can retrieve a previously added FedSocket" do
      FedRegistry.add_fed_socket(build_test_socket("good.domain"))
      assert {:ok, %FedSocket{origin: origin}} = FedRegistry.get_fed_socket("good.domain")
      assert origin == "good.domain"
    end

    test "removes references to FedSockets when the process crashes" do
      FedRegistry.add_fed_socket(build_test_socket("good.domain"))

      assert {:ok, %FedSocket{origin: origin, pid: pid}} =
               FedRegistry.get_fed_socket("good.domain")

      assert origin == "good.domain"

      Process.exit(pid, :testing)
      Process.sleep(100)
      assert {:error, :missing} = FedRegistry.get_fed_socket("good.domain")
    end
  end

  describe "list_all/0" do
    test "retrieves all previously added FedSockets" do
      FedRegistry.add_fed_socket(build_test_socket("good.domain"))
      FedRegistry.add_fed_socket(build_test_socket("better.domain"))

      assert [%RegistryData{}, %RegistryData{}] = FedRegistry.list_all()
    end
  end

  describe "touch/1" do
    test "updates the FedSocket last_message field" do
      {:ok, fs} = FedRegistry.add_fed_socket(build_test_socket("good.domain"))
      {:ok, rd} = FedRegistry.get_registry_data("good.domain")

      FedRegistry.touch(fs)
      {:ok, rd2} = FedRegistry.get_registry_data("good.domain")

      assert rd.last_message != rd2.last_message
    end
  end

  describe "delete_host/1" do
    test "deletes the hosts without a connection" do
      {:ok, _fs} = FedRegistry.set_host_rejected("good.domain")
      {:error, :rejected} = FedRegistry.get_fed_socket("good.domain")

      FedRegistry.delete_host("good.domain")

      {:error, :missing} = FedRegistry.get_fed_socket("good.domain")
    end

    test "deletes the hosts with a connection" do
      {:ok, _fs} = FedRegistry.add_fed_socket(build_test_socket("good.domain"))
      {:ok, _fs} = FedRegistry.get_fed_socket("good.domain")

      FedRegistry.delete_host("good.domain")
      Process.sleep(100)

      {:error, :missing} = FedRegistry.get_fed_socket("good.domain")
    end
  end

  def build_test_socket(origin) do
    pid = Kernel.spawn(&fed_socket_almost/0)

    %FedSocket{
      origin: origin,
      pid: pid,
      type: :outgoing
    }
  end

  def fed_socket_almost do
    receive do
      :close ->
        :ok
    after
      5_000 -> :timeout
    end
  end
end
