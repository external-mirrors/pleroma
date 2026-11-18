# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ActorStatusControllerTest do
  use Pleroma.Web.ConnCase, async: true

  alias Pleroma.Object
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  describe "POST /api/v1/pleroma/actor_status" do
    test "creates status and updates user" do
      user = insert(:user)
      %{conn: conn} = oauth_access(["write:accounts"], user: user)

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

      updated_user = Pleroma.User.get_by_ap_id(user.ap_id)
      object = Object.get_by_id(updated_user.actor_status_id)

      assert object.data["content"] == content
    end

    test "deletes status and updates user" do
      user = insert(:user)
      %{conn: conn} = oauth_access(["write:accounts"], user: user)

      {:ok, _activity} = CommonAPI.actor_status(user, %{content: "delet this"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/pleroma/actor_status", %{
          "content" => ""
        })

      assert %{
               "actor_status_content" => "",
               "account" => %{"pleroma" => %{"actor_status_content" => ""}}
             } = json_response_and_validate_schema(conn, 200)

      updated_user = Pleroma.User.get_by_ap_id(user.ap_id)
      refute updated_user.actor_status_id
    end

    test "returns error if disabled without creating status" do
      clear_config([:instance, :actor_statuses], false)

      user = insert(:user)
      %{conn: conn} = oauth_access(["write:accounts"], user: user)

      refute user.actor_status_id

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/pleroma/actor_status", %{"content" => "Shouldn't work"})

      assert %{"error" => "Unsupported feature"} =
               json_response_and_validate_schema(conn, 400)

      updated_user = Pleroma.User.get_by_ap_id(user.ap_id)
      refute updated_user.actor_status_id
    end
  end
end
