# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.DeleteHandlingTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  for {param, field, count} <- [
        {:in_reply_to_status_id, "inReplyTo", "repliesCount"},
        {:quoted_status_id, "quoteUrl", "quotesCount"}
      ],
      visibility <- ["public", "unlisted", "private", "direct"] do
    test "deleting a remote #{visibility} #{field} preserves the remaining #{count}" do
      user = insert(:user)
      {:ok, parent} = CommonAPI.post(user, %{status: "parent"})
      params = Map.put(%{status: "visible response"}, unquote(param), parent.id)
      {:ok, _visible_response} = CommonAPI.post(user, params)

      data = File.read!("test/fixtures/mastodon-post-activity.json") |> Jason.decode!()
      {:ok, remote} = User.get_or_fetch_by_ap_id(data["actor"])

      {to, cc} =
        case unquote(visibility) do
          "public" -> {["https://www.w3.org/ns/activitystreams#Public"], [user.ap_id]}
          "unlisted" -> {[user.ap_id], ["https://www.w3.org/ns/activitystreams#Public"]}
          "private" -> {[remote.follower_address], [user.ap_id]}
          "direct" -> {[user.ap_id], []}
        end

      object =
        data["object"]
        |> Map.put("to", to)
        |> Map.put("cc", cc)
        |> Map.put(unquote(field), parent.object.data["id"])

      data = data |> Map.put("to", to) |> Map.put("cc", cc) |> Map.put("object", object)
      {:ok, incoming} = Transmogrifier.handle_incoming(data)
      assert Visibility.get_visibility(incoming) == unquote(visibility)

      expected_count = if unquote(visibility) in ["public", "unlisted"], do: 2, else: 1
      assert Object.get_by_ap_id(parent.object.data["id"]).data[unquote(count)] == expected_count

      {:ok, _delete} =
        Transmogrifier.handle_incoming(%{
          "id" => incoming.data["id"] <> "/delete",
          "type" => "Delete",
          "actor" => incoming.actor,
          "object" => incoming.data["object"],
          "to" => to,
          "cc" => cc
        })

      assert Object.get_by_ap_id(parent.object.data["id"]).data[unquote(count)] == 1
    end
  end

  test "it works for incoming deletes" do
    activity = insert(:note_activity)
    deleting_user = insert(:user)

    data =
      File.read!("test/fixtures/mastodon-delete.json")
      |> Jason.decode!()
      |> Map.put("actor", deleting_user.ap_id)
      |> put_in(["object", "id"], activity.data["object"])

    {:ok, %Activity{actor: actor, local: false, data: %{"id" => id}}} =
      Transmogrifier.handle_incoming(data)

    assert id == data["id"]

    # We delete the Create activity because we base our timelines on it.
    # This should be changed after we unify objects and activities
    refute Activity.get_by_id(activity.id)
    assert actor == deleting_user.ap_id

    # Objects are replaced by a tombstone object.
    object = Object.normalize(activity.data["object"], fetch: false)
    assert object.data["type"] == "Tombstone"
  end

  test "it works for incoming when the object has been pruned" do
    activity = insert(:note_activity)

    {:ok, object} =
      Object.normalize(activity.data["object"], fetch: false)
      |> Repo.delete()

    # TODO: mock cachex
    Cachex.del(:object_cache, "object:#{object.data["id"]}")

    deleting_user = insert(:user)

    data =
      File.read!("test/fixtures/mastodon-delete.json")
      |> Jason.decode!()
      |> Map.put("actor", deleting_user.ap_id)
      |> put_in(["object", "id"], activity.data["object"])

    {:ok, %Activity{actor: actor, local: false, data: %{"id" => id}}} =
      Transmogrifier.handle_incoming(data)

    assert id == data["id"]

    # We delete the Create activity because we base our timelines on it.
    # This should be changed after we unify objects and activities
    refute Activity.get_by_id(activity.id)
    assert actor == deleting_user.ap_id
  end

  test "it fails for incoming deletes with spoofed origin" do
    activity = insert(:note_activity)
    %{ap_id: ap_id} = insert(:user, ap_id: "https://gensokyo.2hu/users/raymoo")

    data =
      File.read!("test/fixtures/mastodon-delete.json")
      |> Jason.decode!()
      |> Map.put("actor", ap_id)
      |> put_in(["object", "id"], activity.data["object"])

    assert match?({:error, _}, Transmogrifier.handle_incoming(data))
  end

  test "it works for incoming user deletes" do
    %{ap_id: ap_id} = insert(:user, ap_id: "http://mastodon.example.org/users/admin")

    data =
      File.read!("test/fixtures/mastodon-delete-user.json")
      |> Jason.decode!()

    {:ok, _} = Transmogrifier.handle_incoming(data)
    ObanHelpers.perform_all()

    refute User.get_cached_by_ap_id(ap_id).is_active
  end

  test "it fails for incoming user deletes with spoofed origin" do
    %{ap_id: ap_id} = insert(:user)

    data =
      File.read!("test/fixtures/mastodon-delete-user.json")
      |> Jason.decode!()
      |> Map.put("actor", ap_id)

    assert match?({:error, _}, Transmogrifier.handle_incoming(data))

    assert User.get_cached_by_ap_id(ap_id)
  end
end
