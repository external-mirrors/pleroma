# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.SideEffects.DeleteTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase, async: true

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.SideEffects
  alias Pleroma.Web.CommonAPI

  alias Pleroma.LoggerMock
  alias Pleroma.Web.ActivityPub.ActivityPubMock

  import Mox
  import Pleroma.Factory

  describe "user deletion" do
    setup do
      user = insert(:user)

      {:ok, delete_user_data, _meta} = Builder.delete(user, user.ap_id)
      {:ok, delete_user, _meta} = ActivityPub.persist(delete_user_data, local: true)

      %{
        user: user,
        delete_user: delete_user
      }
    end

    test "it handles user deletions", %{delete_user: delete, user: user} do
      {:ok, _delete, meta} = SideEffects.handle(delete)
      SideEffects.handle_after_transaction(meta)
      ObanHelpers.perform_all()

      refute User.get_cached_by_ap_id(user.ap_id).is_active
    end
  end

  describe "object deletion" do
    setup do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, op} = CommonAPI.post(other_user, %{status: "big oof"})
      {:ok, quoted} = CommonAPI.post(other_user, %{status: "quote me"})

      {:ok, post} =
        CommonAPI.post(user, %{status: "hey", in_reply_to_id: op, quote_id: quoted.id})

      {:ok, favorite} = CommonAPI.favorite(post.id, user)
      object = Object.normalize(post, fetch: false)
      {:ok, delete_data, _meta} = Builder.delete(user, object.data["id"])
      {:ok, delete, _meta} = ActivityPub.persist(delete_data, local: true)

      %{
        user: user,
        delete: delete,
        post: post,
        object: object,
        op: op,
        quoted: quoted,
        favorite: favorite
      }
    end

    test "it handles object deletions", %{
      delete: delete,
      post: post,
      object: object,
      user: user,
      op: op,
      quoted: quoted,
      favorite: favorite
    } do
      object_id = object.id
      user_id = user.id
      test_pid = self()

      ActivityPubMock
      |> expect(:stream_out, fn ^delete -> send(test_pid, :delete_streamed) end)
      |> expect(:stream_out_participations, fn %Object{id: ^object_id}, %User{id: ^user_id} ->
        send(test_pid, :participations_streamed)
      end)

      {:ok, _delete, meta} = SideEffects.handle(delete)
      refute_received :delete_streamed
      refute_received :participations_streamed

      SideEffects.handle_after_transaction(meta)
      assert_received :delete_streamed
      assert_received :participations_streamed

      user = User.get_cached_by_ap_id(object.data["actor"])

      object = Object.get_by_id(object.id)
      assert object.data["type"] == "Tombstone"
      refute Activity.get_by_id(post.id)
      refute Activity.get_by_id(favorite.id)

      user = User.get_by_id(user.id)
      assert user.note_count == 0

      object = Object.normalize(op.data["object"], fetch: false)

      assert object.data["repliesCount"] == 0

      quoted_object = Object.normalize(quoted.data["object"], fetch: false)
      assert quoted_object.data["quotesCount"] == 0
    end

    test "it handles object deletions when the object itself has been pruned", %{
      delete: delete,
      post: post,
      object: object,
      user: user,
      op: op,
      quoted: quoted
    } do
      object_ap_id = object.data["id"]
      user_id = user.id

      {:ok, _object} = Object.prune(object)

      ActivityPubMock
      |> expect(:stream_out, fn ^delete -> nil end)
      |> expect(:stream_out_participations, fn %Object{data: %{"id" => ^object_ap_id}},
                                               %User{id: ^user_id} ->
        nil
      end)

      {:ok, _delete, meta} = SideEffects.handle(delete)
      SideEffects.handle_after_transaction(meta)

      object = Object.get_by_ap_id(object_ap_id)
      assert object.data["type"] == "Tombstone"
      refute Activity.get_by_id(post.id)
      assert User.get_by_id(user.id).note_count == 0

      parent_object = Object.normalize(op.data["object"], fetch: false)
      assert parent_object.data["repliesCount"] == 0

      quoted_object = Object.normalize(quoted.data["object"], fetch: false)
      assert quoted_object.data["quotesCount"] == 0
    end

    test "pruned private objects do not decrement public reply or quote counters" do
      author = insert(:user)
      other_user = insert(:user)
      public_user = insert(:user)
      {:ok, parent} = CommonAPI.post(other_user, %{status: "parent"})
      {:ok, quoted} = CommonAPI.post(other_user, %{status: "quoted"})

      {:ok, _public_post} =
        CommonAPI.post(public_user, %{
          status: "public",
          in_reply_to_id: parent,
          quote_id: quoted.id
        })

      {:ok, private_post} =
        CommonAPI.post(author, %{
          status: "private",
          visibility: "private",
          in_reply_to_id: parent,
          quote_id: quoted.id
        })

      private_object = Object.normalize(private_post, fetch: false)
      {:ok, delete_data, _meta} = Builder.delete(author, private_object.data["id"])
      {:ok, delete, _meta} = ActivityPub.persist(delete_data, local: true)
      {:ok, _private_object} = Object.prune(private_object)

      assert {:ok, _delete, _meta} = SideEffects.handle(delete)
      assert Object.normalize(parent.data["object"], fetch: false).data["repliesCount"] == 1
      assert Object.normalize(quoted.data["object"], fetch: false).data["quotesCount"] == 1
    end

    test "it handles first deletes when the target is already a tombstone", %{
      delete: delete,
      post: post,
      object: object,
      user: user
    } do
      object_ap_id = object.data["id"]
      user_id = user.id

      {:ok, object} = Repo.delete(object)
      Cachex.del(:object_cache, "object:#{object.data["id"]}")

      {:ok, tombstone_data, _} = Builder.tombstone(user.ap_id, object_ap_id)
      {:ok, _tombstone} = Object.create(tombstone_data)

      ActivityPubMock
      |> expect(:stream_out, fn ^delete -> nil end)
      |> expect(:stream_out_participations, fn %Object{data: %{"id" => ^object_ap_id}},
                                               %User{id: ^user_id} ->
        nil
      end)

      {:ok, _delete, meta} = SideEffects.handle(delete)
      SideEffects.handle_after_transaction(meta)

      object = Object.get_by_ap_id(object_ap_id)
      assert object.data["type"] == "Tombstone"
      refute Activity.get_by_id(post.id)
    end

    test "it logs issues with objects deletion", %{
      delete: delete,
      object: object
    } do
      {:ok, _object} =
        object
        |> Object.change(%{data: Map.delete(object.data, "actor")})
        |> Repo.update()

      LoggerMock
      |> expect(:error, fn str -> assert str =~ "The object doesn't have an actor" end)

      {:error, :no_object_actor} = SideEffects.handle(delete)
    end
  end
end
