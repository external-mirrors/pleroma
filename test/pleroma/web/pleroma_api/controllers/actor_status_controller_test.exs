# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ActorStatusControllerTest do
  use Pleroma.Web.ConnCase, async: true

  describe "POST /api/v1/pleroma/actor_status" do
    test "creates status and updates user" do
      %{conn: conn} = oauth_access(["write:accounts"])

      content = "Hello, Navi!"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/pleroma/actor_status", %{
          "content" => content
        })

      assert %{
               "actor_status_content" => "Hello, Navi!",
               "account" => %{"pleroma" => %{"actor_status_content" => ^content}}
             } = json_response_and_validate_schema(conn, 200)
    end
  end
end
