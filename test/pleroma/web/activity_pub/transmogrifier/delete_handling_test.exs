# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.DeleteHandlingTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.ActivityPubMock
  alias Pleroma.Web.ActivityPub.MRFMock
  alias Pleroma.Web.ActivityPub.SideEffects
  alias Pleroma.Web.ActivityPub.SideEffectsMock
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.CommonAPI

  alias Pleroma.LoggerMock

  import Mox
  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  defp delete_data(activity, deleting_user) do
    File.read!("test/fixtures/mastodon-delete.json")
    |> Jason.decode!()
    |> Map.put("actor", deleting_user.ap_id)
    |> put_in(["object", "id"], activity.data["object"])
  end

  defp delete_count_for_object(object_id) do
    Activity
    |> where([activity], fragment("?->>'type' = ?", activity.data, "Delete"))
    |> where([activity], fragment("associated_object_id(?) = ?", activity.data, ^object_id))
    |> Repo.aggregate(:count)
  end

  test "it works for incoming deletes" do
    activity = insert(:note_activity)
    deleting_user = insert(:user)

    data = delete_data(activity, deleting_user)

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

  test "it treats duplicate incoming deletes as idempotent" do
    activity = insert(:note_activity)
    deleting_user = insert(:user)
    object_id = activity.data["object"]

    data = delete_data(activity, deleting_user)

    {:ok, %Activity{} = first_delete} = Transmogrifier.handle_incoming(data)
    assert delete_count_for_object(object_id) == 1

    assert {:ok, %Activity{id: id}} = Transmogrifier.handle_incoming(data)
    assert id == first_delete.id

    spoofed_replay = Map.put(data, "actor", insert(:user).ap_id)
    assert {:error, :already_deleted} = Transmogrifier.handle_incoming(spoofed_replay)

    duplicate_data = Map.put(data, "id", data["id"] <> "/duplicate")

    assert {:error, :already_deleted} = Transmogrifier.handle_incoming(duplicate_data)

    refute Activity.get_by_ap_id(duplicate_data["id"])
    assert delete_count_for_object(object_id) == 1
  end

  test "it ignores stale live objects in cache when detecting duplicate deletes" do
    activity = insert(:note_activity)
    deleting_user = insert(:user)
    stale_object = Object.get_by_ap_id(activity.data["object"])
    data = delete_data(activity, deleting_user)

    assert {:ok, %Activity{}} = Transmogrifier.handle_incoming(data)
    Object.set_cache(stale_object)

    duplicate_data = Map.put(data, "id", data["id"] <> "/stale-cache")

    assert {:error, :already_deleted} = Transmogrifier.handle_incoming(duplicate_data)
    assert delete_count_for_object(activity.data["object"]) == 1
  end

  test "it invalidates caches again after a Delete commits" do
    user = insert(:user)
    {:ok, parent} = CommonAPI.post(user, %{status: "parent"})
    {:ok, activity} = CommonAPI.post(user, %{status: "reply", in_reply_to_id: parent.id})

    object = Object.get_by_ap_id(activity.data["object"])
    parent_object = Object.get_by_ap_id(parent.data["object"])
    cached_user = User.get_by_id(user.id)
    data = delete_data(activity, user)

    SideEffectsMock
    |> expect(:handle, fn delete, meta ->
      result = SideEffects.handle(delete, meta)

      Object.set_cache(object)
      Object.set_cache(parent_object)
      User.set_cache(cached_user)

      result
    end)

    assert {:ok, %Activity{}} = Transmogrifier.handle_incoming(data)
    assert Object.get_cached_by_ap_id(object.data["id"]).data["type"] == "Tombstone"
    assert Object.get_cached_by_ap_id(parent_object.data["id"]).data["repliesCount"] == 0
    assert User.get_cached_by_ap_id(user.ap_id).note_count == 1
  end

  test "it completes an exact replay of a persisted Delete with missing side effects" do
    user = insert(:user)
    {:ok, activity} = CommonAPI.post(user, %{status: "retry persisted Delete"})
    object_id = activity.data["object"]
    data = delete_data(activity, user)

    assert {:ok, persisted_delete, _meta} = ActivityPub.persist(data, local: false)
    assert %Object{data: %{"type" => "Note"}} = Object.get_by_ap_id(object_id)

    ActivityPubMock
    |> expect(:stream_out, fn %Activity{
                                data: %{"deleted_activity_id" => deleted_activity_id}
                              } ->
      assert deleted_activity_id == activity.id
    end)
    |> expect(:stream_out_participations, fn _object, _user -> :ok end)

    MRFMock
    |> expect(:pipeline_filter, fn message, meta ->
      {:ok, Map.put(message, "deleted_activity_id", "wrong-activity"), meta}
    end)

    assert {:ok, %Activity{id: delete_id}} = Transmogrifier.handle_incoming(data)
    assert delete_id == persisted_delete.id
    assert delete_count_for_object(object_id) == 1
    assert %Object{data: %{"type" => "Tombstone"}} = Object.get_by_ap_id(object_id)
    refute Activity.get_by_id(activity.id)
  end

  test "it completes a persisted Delete when a tombstone still has its Create" do
    user = insert(:user)
    {:ok, activity} = CommonAPI.post(user, %{status: "retry tombstone Delete"})
    object = Object.get_by_ap_id(activity.data["object"])
    data = delete_data(activity, user)

    {:ok, cached_user} = User.add_pinned_object_id(user, object.data["id"])
    assert {:ok, _tombstone} = Object.swap_object_with_tombstone(object)
    Object.invalid_object_cache(object)
    assert {:ok, persisted_delete, _meta} = ActivityPub.persist(data, local: false)

    SideEffectsMock
    |> expect(:handle, fn delete, meta ->
      result = SideEffects.handle(delete, meta)
      User.set_cache(cached_user)
      result
    end)

    assert {:ok, %Activity{id: delete_id}} = Transmogrifier.handle_incoming(data)
    assert delete_id == persisted_delete.id
    assert delete_count_for_object(object.data["id"]) == 1
    refute Activity.get_by_id(activity.id)
    refute Map.has_key?(User.get_cached_by_ap_id(user.ap_id).pinned_objects, object.data["id"])
  end

  test "it rolls back failed delete side effects so the activity can be retried" do
    activity = insert(:note_activity)
    deleting_user = insert(:user)
    object = Object.get_by_ap_id(activity.data["object"])
    data = delete_data(activity, deleting_user)

    {:ok, object} =
      object
      |> Object.change(%{data: Map.delete(object.data, "actor")})
      |> Repo.update()

    Cachex.del(:object_cache, "object:#{object.data["id"]}")

    LoggerMock
    |> expect(:error, fn message -> assert message =~ "The object doesn't have an actor" end)

    assert {:error, {:side_effects, {:error, :no_object_actor}}} =
             Transmogrifier.handle_incoming(data)

    refute Activity.get_by_ap_id(data["id"])
    assert %Object{data: %{"type" => "Note"}} = Object.get_by_ap_id(object.data["id"])
    assert Activity.get_by_id(activity.id)

    current_object = Object.get_by_ap_id(object.data["id"])

    {:ok, _object} =
      current_object
      |> Object.change(%{data: Map.put(current_object.data, "actor", deleting_user.ap_id)})
      |> Repo.update()

    Cachex.del(:object_cache, "object:#{object.data["id"]}")

    assert {:ok, %Activity{data: %{"id" => delete_id}}} =
             Transmogrifier.handle_incoming(data)

    assert delete_id == data["id"]
  end

  test "it invalidates caches when an exception rolls back mutated Delete side effects" do
    deleting_user = insert(:user)
    {:ok, activity} = CommonAPI.post(deleting_user, %{status: "rollback cached state"})
    object = Object.get_by_ap_id(activity.data["object"])
    data = delete_data(activity, deleting_user)

    {:ok, object} =
      object
      |> Object.change(%{data: Map.put(object.data, "inReplyTo", %{})})
      |> Repo.update()

    Cachex.del(:object_cache, "object:#{object.data["id"]}")

    assert_raise Protocol.UndefinedError, fn ->
      Transmogrifier.handle_incoming(data)
    end

    assert User.get_by_id(deleting_user.id).note_count == 1
    assert User.get_cached_by_ap_id(deleting_user.ap_id).note_count == 1
    assert %Object{data: %{"type" => "Note"}} = Object.get_by_ap_id(object.data["id"])
    assert Activity.get_by_id(activity.id)
    refute Activity.get_by_ap_id(data["id"])
  end

  test "it rejects MRF rewrites of the Delete actor or target" do
    activity = insert(:note_activity)
    other_activity = insert(:note_activity)
    deleting_user = insert(:user)
    other_deleting_user = insert(:user)
    data = delete_data(activity, deleting_user)

    MRFMock
    |> expect(:pipeline_filter, fn message, meta ->
      {:ok, Map.put(message, "object", other_activity.data["object"]), meta}
    end)

    assert {:error, :delete_identity_changed} = Transmogrifier.handle_incoming(data)

    assert Activity.get_by_id(activity.id)
    assert Activity.get_by_id(other_activity.id)
    refute Activity.get_by_ap_id(data["id"])

    MRFMock
    |> expect(:pipeline_filter, fn message, meta ->
      {:ok, Map.put(message, "actor", other_deleting_user.ap_id), meta}
    end)

    assert {:error, :delete_identity_changed} =
             data
             |> Map.update!("id", &(&1 <> "/actor-rewrite"))
             |> Transmogrifier.handle_incoming()

    assert Activity.get_by_id(activity.id)

    MRFMock
    |> expect(:pipeline_filter, fn message, meta ->
      {:ok, Map.update!(message, "id", &(&1 <> "/mrf-rewrite")), meta}
    end)

    assert {:error, :delete_identity_changed} = Transmogrifier.handle_incoming(data)
    assert Activity.get_by_id(activity.id)
  end

  test "it works for incoming when the object has been pruned" do
    activity = insert(:note_activity)

    {:ok, object} =
      Object.normalize(activity.data["object"], fetch: false)
      |> Repo.delete()

    Object.set_cache(object)

    deleting_user = insert(:user)

    data = delete_data(activity, deleting_user)

    SideEffectsMock
    |> expect(:handle, fn delete, meta ->
      result = SideEffects.handle(delete, meta)
      Object.set_cache(object)
      result
    end)

    {:ok, %Activity{actor: actor, local: false, data: %{"id" => id}}} =
      Transmogrifier.handle_incoming(data)

    assert id == data["id"]

    # We delete the Create activity because we base our timelines on it.
    # This should be changed after we unify objects and activities
    refute Activity.get_by_id(activity.id)
    assert actor == deleting_user.ap_id
    assert Object.get_cached_by_ap_id(object.data["id"]).data["type"] == "Tombstone"
  end

  test "it handles a first Delete for a canonical tombstone without an actor" do
    activity = insert(:note_activity)
    object = Object.get_by_ap_id(activity.data["object"])
    deleting_user = User.get_cached_by_ap_id(object.data["actor"])
    data = delete_data(activity, deleting_user)

    assert {:ok, tombstone} = Object.swap_object_with_tombstone(object)
    refute tombstone.data["actor"]
    Cachex.del(:object_cache, "object:#{object.data["id"]}")

    assert {:ok, %Activity{data: %{"id" => delete_id}}} =
             Transmogrifier.handle_incoming(data)

    assert delete_id == data["id"]
    refute Activity.get_by_id(activity.id)
  end

  test "it fails for incoming deletes with spoofed origin" do
    activity = insert(:note_activity)
    %{ap_id: ap_id} = insert(:user, ap_id: "https://gensokyo.2hu/users/raymoo")

    data =
      activity
      |> delete_data(%{ap_id: ap_id})

    assert {:error, {:validate, {:error, _}}} = Transmogrifier.handle_incoming(data)
  end

  test "it works for incoming user deletes" do
    %{ap_id: ap_id} = insert(:user, ap_id: "http://mastodon.example.org/users/admin")

    data =
      File.read!("test/fixtures/mastodon-delete-user.json")
      |> Jason.decode!()

    {:ok, first_delete} = Transmogrifier.handle_incoming(data)

    assert {:ok, %Activity{id: id}} = Transmogrifier.handle_incoming(data)
    assert id == first_delete.id

    duplicate_data = Map.update!(data, "id", &(&1 <> "/duplicate"))
    assert {:error, :already_deleted} = Transmogrifier.handle_incoming(duplicate_data)
    assert delete_count_for_object(ap_id) == 1

    ObanHelpers.perform_all()

    refute User.get_cached_by_ap_id(ap_id).is_active
  end

  test "it completes an exact replay of a persisted user Delete" do
    user = insert(:user, ap_id: "http://mastodon.example.org/users/admin")

    data =
      File.read!("test/fixtures/mastodon-delete-user.json")
      |> Jason.decode!()

    assert {:ok, persisted_delete, _meta} = ActivityPub.persist(data, local: false)
    assert User.get_cached_by_ap_id(user.ap_id).is_active
    assert {:ok, _user} = User.set_activation(user, false)
    refute_enqueued(worker: Pleroma.Workers.DeleteWorker)

    assert {:ok, %Activity{id: delete_id}} = Transmogrifier.handle_incoming(data)
    assert delete_id == persisted_delete.id
    assert delete_count_for_object(user.ap_id) == 1
    refute User.get_cached_by_ap_id(user.ap_id).is_active

    assert_enqueued(
      worker: Pleroma.Workers.DeleteWorker,
      args: %{"op" => "delete_user", "user_id" => user.id}
    )

    assert {:ok, %Activity{id: ^delete_id}} = Transmogrifier.handle_incoming(data)
    assert length(all_enqueued(worker: Pleroma.Workers.DeleteWorker)) == 1
  end

  test "it fails for incoming user deletes with spoofed origin" do
    %{ap_id: ap_id} = insert(:user)

    data =
      File.read!("test/fixtures/mastodon-delete-user.json")
      |> Jason.decode!()
      |> Map.put("actor", ap_id)

    assert {:error, {:validate, {:error, _}}} = Transmogrifier.handle_incoming(data)

    assert User.get_cached_by_ap_id(ap_id)
  end
end
