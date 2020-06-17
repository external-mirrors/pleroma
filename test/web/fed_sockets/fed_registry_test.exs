# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.FedRegistryTest do
  use ExUnit.Case

  alias Pleroma.Web.FedSockets
  alias Pleroma.Web.FedSockets.FedRegistry
  alias Pleroma.Web.FedSockets.SocketInfo

  setup do
    start_supervised({Pleroma.Web.FedSockets.Supervisor, []})
    build_test_socket("good.domain")
    Process.sleep(10)

    :ok
  end

  describe "add_fed_socket/1 without conflicting sockets" do
    test "can be added" do
      Process.sleep(10)
      assert {:ok, %SocketInfo{origin: origin}} = FedRegistry.get_fed_socket("good.domain")
      assert origin == "good.domain"
    end

    test "multiple origins can be added" do
      build_test_socket("anothergood.domain")
      Process.sleep(10)

      assert {:ok, %SocketInfo{origin: origin_1}} = FedRegistry.get_fed_socket("good.domain")

      assert {:ok, %SocketInfo{origin: origin_2}} =
               FedRegistry.get_fed_socket("anothergood.domain")

      assert origin_1 == "good.domain"
      assert origin_2 == "anothergood.domain"
      assert FedRegistry.list_all() |> Enum.count() == 2
    end
  end

  describe "add_fed_socket/1 when duplicate sockets conflict" do
    setup do
      build_test_socket("good.domain")
      build_test_socket("good.domain")
      Process.sleep(10)

      :ok
    end

    test "will be ignored" do
      assert {:ok, %SocketInfo{origin: origin, pid: pid_one}} =
               FedRegistry.get_fed_socket("good.domain")

      assert origin == "good.domain"

      assert FedRegistry.list_all() |> Enum.count() == 1
    end

    test "the newer process will be closed" do
      pid_two = build_test_socket("good.domain")

      assert {:ok, %SocketInfo{origin: origin, pid: pid_one}} =
               FedRegistry.get_fed_socket("good.domain")

      assert origin == "good.domain"
      Process.sleep(10)

      refute Process.alive?(pid_two)

      assert FedRegistry.list_all() |> Enum.count() == 1
    end
  end

  describe "get_fed_socket/1" do
    test "returns missing for unknown hosts" do
      assert {:error, :missing} = FedRegistry.get_fed_socket("not_a_dmoain")
    end

    test "returns rejected for hosts previously rejected" do
      "rejected.domain"
      |> FedSockets.uri_for_origin()
      |> FedRegistry.set_host_rejected()

      assert {:error, :rejected} = FedRegistry.get_fed_socket("rejected.domain")
    end

    test "can retrieve a previously added SocketInfo" do
      build_test_socket("good.domain")
      Process.sleep(10)
      assert {:ok, %SocketInfo{origin: origin}} = FedRegistry.get_fed_socket("good.domain")
      assert origin == "good.domain"
    end

    test "removes references to SocketInfos when the process crashes" do
      assert {:ok, %SocketInfo{origin: origin, pid: pid}} =
               FedRegistry.get_fed_socket("good.domain")

      assert origin == "good.domain"

      Process.exit(pid, :testing)
      Process.sleep(100)
      assert {:error, :missing} = FedRegistry.get_fed_socket("good.domain")
    end
  end

  def build_test_socket(origin) do
    uri = FedSockets.uri_for_origin(origin)
    Kernel.spawn(fn -> fed_socket_almost(uri) end)
  end

  def fed_socket_almost(origin) do
    FedRegistry.add_fed_socket(origin)

    receive do
      :close ->
        :ok
    after
      5_000 -> :timeout
    end
  end
end
