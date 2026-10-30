# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ActivityPubControllerC2STest do
  # Regression tests for the C2S audit of 2026-10-30. C2S sends client JSON
  # through the local pipeline, so the rules that CommonAPI enforces must also
  # hold here.
  use Pleroma.Web.ConnCase
  use Oban.Testing, repo: Pleroma.Repo

  alias Pleroma.Object
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  setup do
    Mox.stub_with(Pleroma.UnstubbedConfigMock, Pleroma.Test.StaticConfig)
    :ok
  end

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  setup do: clear_config([:instance, :federating], true)

  defp post_outbox(conn, user, data, status) do
    conn
    |> assign(:user, user)
    |> put_req_header("content-type", "application/activity+json")
    |> post("/users/#{user.nickname}/outbox", data)
    |> json_response(status)
  end

  defp emoji_tag(name, url) do
    %{"type" => "Emoji", "name" => name, "icon" => %{"type" => "Image", "url" => url}}
  end

  describe "EmojiReact" do
    setup do
      {:ok, activity} = CommonAPI.post(insert(:user), %{status: "hi"})
      %{object_id: activity.data["object"]}
    end

    test "rejects a reaction name that is not a single emoji", %{conn: conn, object_id: id} do
      name = "visit evil.example now :x: <b>bold</b>"

      data = %{
        "type" => "EmojiReact",
        "object" => id,
        "content" => name,
        "tag" => [emoji_tag(name, "https://tracker.example/pixel.png")]
      }

      post_outbox(conn, insert(:user), data, 400)
      assert Object.get_by_ap_id(id).data["reactions"] in [nil, []]
    end

    test "accepts a custom emoji with a remote image", %{conn: conn, object_id: id} do
      data = %{
        "type" => "EmojiReact",
        "object" => id,
        "content" => ":blobcat:",
        "tag" => [emoji_tag("blobcat", "https://remote.example/blobcat.png")]
      }

      post_outbox(conn, insert(:user), data, 201)

      assert [["blobcat", [_], "https://remote.example/blobcat.png"]] =
               Object.get_by_ap_id(id).data["reactions"]
    end
  end
end
