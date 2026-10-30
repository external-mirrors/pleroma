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

  describe "Answer (poll votes)" do
    setup do
      author = insert(:user)

      {:ok, poll} =
        CommonAPI.post(author, %{status: "?", poll: %{options: ["a", "b"], expires_in: 600}})

      %{author: author, poll_id: poll.data["object"]}
    end

    defp vote(poll_id, author, name) do
      %{
        "type" => "Create",
        "object" => %{
          "type" => "Answer",
          "name" => name,
          "inReplyTo" => poll_id,
          "to" => [author.ap_id],
          "cc" => []
        }
      }
    end

    defp vote_counts(poll_id) do
      Object.get_by_ap_id(poll_id).data["oneOf"]
      |> Map.new(&{&1["name"], &1["replies"]["totalItems"]})
    end

    test "counts one vote per voter on a single-choice poll", ctx do
      voter = insert(:user)
      post_outbox(ctx.conn, voter, vote(ctx.poll_id, ctx.author, "a"), 201)
      post_outbox(ctx.conn, voter, vote(ctx.poll_id, ctx.author, "a"), 400)
      post_outbox(ctx.conn, voter, vote(ctx.poll_id, ctx.author, "b"), 400)

      assert vote_counts(ctx.poll_id) == %{"a" => 1, "b" => 0}
    end

    test "rejects votes of the author, on unknown options and on closed polls", ctx do
      post_outbox(ctx.conn, ctx.author, vote(ctx.poll_id, ctx.author, "a"), 400)
      post_outbox(ctx.conn, insert(:user), vote(ctx.poll_id, ctx.author, "c"), 400)

      object = Object.get_by_ap_id(ctx.poll_id)

      object
      |> Object.change(%{data: Map.put(object.data, "closed", "2000-01-01T00:00:00Z")})
      |> Object.update_and_set_cache()

      post_outbox(ctx.conn, insert(:user), vote(ctx.poll_id, ctx.author, "a"), 400)

      assert vote_counts(ctx.poll_id) == %{"a" => 0, "b" => 0}
    end

    test "rejects votes on polls the voter cannot see", %{conn: conn, author: author} do
      {:ok, poll} =
        CommonAPI.post(author, %{
          status: "?",
          visibility: "private",
          poll: %{options: ["a", "b"], expires_in: 600}
        })

      post_outbox(conn, insert(:user), vote(poll.data["object"], author, "a"), 400)
      assert vote_counts(poll.data["object"]) == %{"a" => 0, "b" => 0}
    end
  end

  describe "Add (pins)" do
    defp pin(user, object_id),
      do: %{"type" => "Add", "target" => user.featured_address, "object" => object_id}

    defp featured(user) do
      build_conn()
      |> put_req_header("accept", "application/activity+json")
      |> get("/users/#{user.nickname}/collections/featured")
      |> json_response(200)
      |> Map.get("orderedItems")
    end

    test "rejects pins of other users' posts", %{conn: conn} do
      bob = insert(:user)
      alice = insert(:user)
      {:ok, alice, bob} = Pleroma.User.follow(alice, bob)

      {:ok, private} = CommonAPI.post(bob, %{status: "followers", visibility: "private"})
      {:ok, dm} = CommonAPI.post(bob, %{status: "@#{alice.nickname} dm", visibility: "direct"})
      {:ok, public} = CommonAPI.post(bob, %{status: "public"})

      for post <- [private, dm, public] do
        post_outbox(conn, alice, pin(alice, post.data["object"]), 400)
      end

      assert featured(alice) == []
    end

    test "pins only public or unlisted own posts", %{conn: conn} do
      alice = insert(:user)
      {:ok, private} = CommonAPI.post(alice, %{status: "followers", visibility: "private"})
      {:ok, unlisted} = CommonAPI.post(alice, %{status: "unlisted", visibility: "unlisted"})

      post_outbox(conn, alice, pin(alice, private.data["object"]), 400)
      post_outbox(conn, alice, pin(alice, unlisted.data["object"]), 201)

      assert [%{"content" => "unlisted"}] = featured(alice)
    end

    test "the featured collection hides non-public posts that are already pinned" do
      alice = insert(:user)
      {:ok, private} = CommonAPI.post(alice, %{status: "followers", visibility: "private"})
      {:ok, alice} = Pleroma.User.add_pinned_object_id(alice, private.data["object"])

      assert featured(alice) == []
    end
  end
end
