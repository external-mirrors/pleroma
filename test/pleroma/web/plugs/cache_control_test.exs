# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.CacheControlTest do
  use Pleroma.Web.ConnCase, async: true
  alias Plug.Conn

  @dir "test/frontend_static_cache_control_test"

  setup do
    File.mkdir_p!(@dir)

    frontend_path = Path.join([@dir, "frontends", "pleroma", "fantasy"])

    File.mkdir_p!(frontend_path)
    File.touch!(Path.join(frontend_path, "index.html"))
    clear_config([:instance, :static_dir], @dir)
    clear_config([:frontends, :primary], %{"name" => "pleroma", "ref" => "fantasy"})

    on_exit(fn ->
      File.rm_rf(@dir)
    end)
  end

  test "Verify Cache-Control header on static assets", %{conn: conn} do
    conn = get(conn, "/index.html")

    assert Conn.get_resp_header(conn, "cache-control") == ["public, no-cache"]
  end

  test "Verify Cache-Control header on the API", %{conn: conn} do
    conn = get(conn, "/api/v1/instance")

    assert Conn.get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
  end
end
