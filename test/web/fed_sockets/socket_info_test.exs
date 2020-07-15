# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.SocketInfoTest do
  use ExUnit.Case

  alias Pleroma.Web.FedSockets.SocketInfo

  describe "uri_for_origin" do
    test "provides the fed_socket URL given the origin information" do
      endpoint = "example.com:4000"
      assert SocketInfo.uri_for_origin(endpoint) =~ "ws://"
      assert SocketInfo.uri_for_origin(endpoint) =~ endpoint
    end
  end

  describe "origin" do
    test "will proide the origin field given a url" do
      endpoint = "example.com:4000"
      assert SocketInfo.origin("ws://#{endpoint}") == endpoint
      assert SocketInfo.origin("http://#{endpoint}") == endpoint
      assert SocketInfo.origin("https://#{endpoint}") == endpoint
    end

    test "will proide the origin field given a uri" do
      endpoint = "example.com:4000"
      uri = URI.parse("http://#{endpoint}")

      assert SocketInfo.origin(uri) == endpoint
    end
  end

  describe "creating outgoing connection records" do
    test "can be passed a string" do
      assert %{pid: :pid, origin: _origin, type: :outgoing} =
               SocketInfo.outgoing(:pid, "example.com:4000")
    end

    test "can be passed a URI" do
      uri = URI.parse("http://example.com:4000")
      assert %{pid: :pid, origin: origin, type: :outgoing} = SocketInfo.outgoing(:pid, uri)
      assert origin =~ "example.com:4000"
    end

    test "will include the port number" do
      assert %{pid: :pid, origin: origin, type: :outgoing} =
               SocketInfo.outgoing(:pid, "http://example.com:4000")

      assert origin =~ ":4000"
    end

    test "will not include port 80" do
      assert %{pid: :pid, origin: origin, type: :outgoing} =
               SocketInfo.outgoing(:pid, "http://example.com:80")

      refute origin =~ ":80"
    end

    test "does not require the port" do
      assert %{pid: :pid, origin: "example.com", type: :outgoing} =
               SocketInfo.outgoing(:pid, "http://example.com")
    end
  end

  describe "creating incoming connection records" do
    test "can be passed a string" do
      assert %{pid: :pid, origin: _origin, type: :incoming} =
               SocketInfo.incoming(:pid, "example.com:4000")
    end

    test "can be passed a URI" do
      uri = URI.parse("example.com:4000")
      assert %{pid: :pid, origin: _origin, type: :incoming} = SocketInfo.incoming(:pid, uri)
    end

    test "will include the port number" do
      assert %{pid: :pid, origin: origin, type: :incoming} =
               SocketInfo.incoming(:pid, "http://example.com:4000")

      assert origin =~ ":4000"
    end

    test "will not include port 80" do
      assert %{pid: :pid, origin: origin, type: :incoming} =
               SocketInfo.incoming(:pid, "http://example.com:80")

      refute origin =~ ":80"
    end

    test "does not require the port" do
      assert %{pid: :pid, origin: "example.com", type: :incoming} =
               SocketInfo.incoming(:pid, "http://example.com")
    end
  end
end
