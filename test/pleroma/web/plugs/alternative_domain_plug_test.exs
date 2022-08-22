# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.AlternativeDomainPlugTest do
  use Pleroma.Web.ConnCase
  use Plug.Test

  alias Pleroma.Web.Domains
  alias Pleroma.Web.Plugs.AlternativeDomainPlug

  describe "Assigning base url based on domain" do
    setup do
      clear_config(
        [Pleroma.Web.Domains, :alternative_domains],
        [
          %{host: "mewmew.org", port: 8080, proto: "https"},
          %{host: "au.mewmew.org", port: 443, proto: "https"},
          %{host: "mewmew.onion", port: 80, proto: "http"}
        ]
      )

      :ok
    end

    test "default host header" do
      conn =
        build_conn()
        |> AlternativeDomainPlug.call(%{})

      expected_base = Pleroma.Web.Endpoint.url()

      assert Domains.get_current_base() == expected_base
      assert conn.assigns.base_url == expected_base
    end

    test "https with port" do
      conn =
        build_conn()
        |> put_req_header("host", "mewmew.org")
        |> AlternativeDomainPlug.call(%{})

      expected_base = "https://mewmew.org:8080"

      assert Domains.get_current_base() == expected_base
      assert conn.assigns.base_url == expected_base
    end

    test "https with default port" do
      conn =
        build_conn()
        |> put_req_header("host", "au.mewmew.org")
        |> AlternativeDomainPlug.call(%{})

      expected_base = "https://au.mewmew.org"

      assert Domains.get_current_base() == expected_base
      assert conn.assigns.base_url == expected_base
    end

    test "http with default port" do
      conn =
        build_conn()
        |> put_req_header("host", "mewmew.onion")
        |> AlternativeDomainPlug.call(%{})

      expected_base = "http://mewmew.onion"

      assert Domains.get_current_base() == expected_base
      assert conn.assigns.base_url == expected_base
    end

    test "fallback" do
      conn =
        build_conn()
        |> put_req_header("host", "i.dont.know")
        |> AlternativeDomainPlug.call(%{})

      expected_base = Pleroma.Web.Endpoint.url()

      assert Domains.get_current_base() == expected_base
      assert conn.assigns.base_url == expected_base
    end
  end
end
