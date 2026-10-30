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

  require Pleroma.Constants

  @public Pleroma.Constants.as_public()

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

  describe "Update of own objects" do
    setup do
      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "hello"})
      %{user: user, object_id: activity.data["object"]}
    end

    defp update(object),
      do: %{"type" => "Update", "to" => [@public], "cc" => [], "object" => object}

    test "rejects an invalid object and keeps the post", %{conn: conn} = ctx do
      for bad <- [%{"content" => %{"not" => "a string"}}, %{"attachment" => "garbage"}] do
        object = Map.merge(%{"id" => ctx.object_id, "type" => "Note", "content" => "x"}, bad)
        post_outbox(conn, ctx.user, update(object), 400)
      end

      assert Object.get_by_ap_id(ctx.object_id).data["content"] == "hello"
    end

    test "builds the edit history and the edit time on the server", %{conn: conn} = ctx do
      forged = %{
        "type" => "OrderedCollection",
        "totalItems" => 1,
        "orderedItems" => [%{"type" => "Note", "content" => "forged", "actor" => "x"}]
      }

      object = %{
        "id" => ctx.object_id,
        "type" => "Note",
        "content" => "now",
        "updated" => "2999-01-01T00:00:00Z",
        "formerRepresentations" => forged
      }

      post_outbox(conn, ctx.user, update(object), 201)

      data = Object.get_by_ap_id(ctx.object_id).data
      assert data["content"] == "now"
      assert [%{"content" => "hello"}] = data["formerRepresentations"]["orderedItems"]
      refute data["updated"] =~ "2999"
    end

    test "keeps the vote counts of a local poll", %{conn: conn, user: user} do
      {:ok, activity} =
        CommonAPI.post(user, %{status: "poll", poll: %{options: ["a", "b"], expires_in: 600}})

      %{data: data} = Object.normalize(activity, fetch: false)
      forged = Enum.map(data["oneOf"], &put_in(&1, ["replies", "totalItems"], 1000))

      object = %{
        "id" => data["id"],
        "type" => "Question",
        "content" => "poll edited",
        "oneOf" => forged,
        "votersCount" => 2000
      }

      post_outbox(conn, user, update(object), 201)

      stored = Object.get_by_ap_id(data["id"]).data
      assert stored["content"] == "poll edited"
      assert stored["votersCount"] == data["votersCount"]
      assert Enum.all?(stored["oneOf"], &(&1["replies"]["totalItems"] == 0))
    end
  end

  describe "Create of a Question" do
    setup do
      clear_config([:instance, :poll_limits], %{
        max_options: 4,
        max_option_chars: 20,
        min_expiration: 60,
        max_expiration: 86_400
      })
    end

    defp question(extra) do
      closed = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

      object =
        Map.merge(
          %{
            "type" => "Question",
            "content" => "?",
            "to" => [@public],
            "cc" => [],
            "closed" => closed,
            "oneOf" => [option("a"), option("b")]
          },
          extra
        )

      %{"type" => "Create", "object" => object}
    end

    defp option(name, votes \\ 0),
      do: %{
        "type" => "Note",
        "name" => name,
        "replies" => %{"type" => "Collection", "totalItems" => votes}
      }

    test "accepts a poll within the limits", %{conn: conn} do
      result = post_outbox(conn, insert(:user), question(%{}), 201)

      assert %Object{data: %{"type" => "Question"}} =
               Object.normalize(result["object"], fetch: false)
    end

    test "rejects polls over the limits", %{conn: conn} do
      far = DateTime.utc_now() |> DateTime.add(86_400 * 365) |> DateTime.to_iso8601()

      for extra <- [
            %{"oneOf" => Enum.map(1..5, &option("opt#{&1}"))},
            %{"oneOf" => [option("a"), option(String.duplicate("b", 21))]},
            %{"oneOf" => [option("a")]},
            %{"oneOf" => [option("a"), option("a")]},
            %{"closed" => far},
            %{"closed" => "2000-01-01T00:00:00Z"}
          ] do
        post_outbox(conn, insert(:user), question(extra), 400)
      end
    end

    test "rejects polls with votes", %{conn: conn} do
      for extra <- [
            %{"oneOf" => [option("a", 1000), option("b")]},
            %{"votersCount" => 12_345}
          ] do
        post_outbox(conn, insert(:user), question(extra), 400)
      end
    end
  end

  describe "replies and quotes" do
    setup do
      victim = insert(:user)
      {:ok, secret} = CommonAPI.post(victim, %{status: "secret", visibility: "private"})
      %{victim: victim, secret_id: secret.data["object"]}
    end

    defp note(extra) do
      object =
        Map.merge(%{"type" => "Note", "content" => "hi", "to" => [@public], "cc" => []}, extra)

      %{"type" => "Create", "object" => object}
    end

    test "rejects a reply to a post the user cannot see", %{conn: conn, secret_id: id} do
      post_outbox(conn, insert(:user), note(%{"inReplyTo" => id}), 400)
      assert Object.get_by_ap_id(id).data["repliesCount"] in [nil, 0]
    end

    test "rejects a quote of a private post of another user", %{conn: conn} = ctx do
      {:ok, follower, _} = Pleroma.User.follow(insert(:user), ctx.victim)
      post_outbox(conn, follower, note(%{"quoteUrl" => ctx.secret_id}), 400)
      assert Object.get_by_ap_id(ctx.secret_id).data["quotesCount"] in [nil, 0]
    end

    test "allows a quote of an own private post", %{conn: conn} = ctx do
      result = post_outbox(conn, ctx.victim, note(%{"quoteUrl" => ctx.secret_id}), 201)
      assert Object.normalize(result["object"], fetch: false).data["quoteUrl"] == ctx.secret_id
    end
  end
end
