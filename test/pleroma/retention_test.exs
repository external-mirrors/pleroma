# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.RetentionTest do
  use Pleroma.DataCase, async: false

  alias Pleroma.Activity
  alias Pleroma.Bookmark
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Retention
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  setup do
    clear_config([:instance, :remote_post_retention_days], 90)
    clear_config([:retention, :enabled], true)
    clear_config([:retention, :max_objects], nil)
    clear_config([:retention, :batch_size], 500)
    clear_config([:retention, :keep_non_public], false)

    old_date =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-200 * 86_400)
      |> NaiveDateTime.truncate(:second)

    %{old_date: old_date}
  end

  # Posts made through CommonAPI are local; turn the activity into a remote one
  # and backdate it so it looks like an old federated post.
  defp make_remote_and_old(%Activity{} = activity, old_date) do
    activity
    |> Ecto.Changeset.change(%{local: false, updated_at: old_date})
    |> Repo.update!()
  end

  defp make_old(%Activity{} = activity, old_date) do
    activity
    |> Ecto.Changeset.change(%{updated_at: old_date})
    |> Repo.update!()
  end

  defp old_remote_post(user, old_date, params \\ %{}) do
    {:ok, activity} = CommonAPI.post(user, Map.merge(%{status: "some thing"}, params))
    make_remote_and_old(activity, old_date)
  end

  describe "estimated_object_count/0" do
    test "falls back to an exact count when the planner has no statistics" do
      insert(:note)
      insert(:note)

      assert Retention.estimated_object_count() == Repo.aggregate(Object, :count)
    end
  end

  describe "run/1" do
    test "evicts an old remote thread nobody local touched", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      remote_user2 = insert(:user, local: false)

      post = old_remote_post(remote_user, old_date)

      {:ok, reply} =
        CommonAPI.post(remote_user2, %{status: "reply", in_reply_to_status_id: post.id})

      make_remote_and_old(reply, old_date)

      {:ok, like} = CommonAPI.favorite(post.id, remote_user2)
      make_remote_and_old(like, old_date)

      assert %{contexts: 1, objects: 2, activities: 3} = Retention.run()

      refute Object.get_by_ap_id(post.data["object"])
      refute Object.get_by_ap_id(reply.data["object"])
      assert Repo.all(Activity) == []
    end

    test "keeps recent remote threads" do
      remote_user = insert(:user, local: false)
      {:ok, post} = CommonAPI.post(remote_user, %{status: "fresh"})
      post |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()

      assert %{contexts: 0, objects: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps old local posts", %{old_date: old_date} do
      user = insert(:user)
      {:ok, post} = CommonAPI.post(user, %{status: "mine"})
      make_old(post, old_date)

      assert %{contexts: 0, objects: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps an old remote thread a local user favourited", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      post = old_remote_post(remote_user, old_date)
      {:ok, like} = CommonAPI.favorite(post.id, local_user)
      make_old(like, old_date)

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps an old remote thread a local user replied to", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      post = old_remote_post(remote_user, old_date)

      {:ok, reply} =
        CommonAPI.post(local_user, %{status: "reply", in_reply_to_status_id: post.id})

      make_old(reply, old_date)

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps an old remote thread a local user bookmarked", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      post = old_remote_post(remote_user, old_date)
      {:ok, _} = Bookmark.create(local_user.id, post.id)

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps an old remote post that mentioned a local user", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      post = old_remote_post(remote_user, old_date, %{status: "hey @#{local_user.nickname}"})

      assert [_] = Repo.all(Pleroma.Notification)

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps an old remote post that was reported", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      post = old_remote_post(remote_user, old_date)

      {:ok, _flag} =
        CommonAPI.report(local_user, %{account_id: remote_user.id, status_ids: [post.id]})

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "evicts an old remote thread even if remote users interacted with it", %{
      old_date: old_date
    } do
      remote_user = insert(:user, local: false)
      remote_user2 = insert(:user, local: false)

      post = old_remote_post(remote_user, old_date)
      {:ok, announce} = CommonAPI.repeat(post.id, remote_user2)
      make_remote_and_old(announce, old_date)

      assert %{contexts: 1, objects: 1, activities: 2} = Retention.run()
      refute Object.get_by_ap_id(post.data["object"])
    end

    test "evicts old threads in batches, oldest first", %{old_date: old_date} do
      clear_config([:retention, :batch_size], 1)
      remote_user = insert(:user, local: false)

      older = old_remote_post(remote_user, NaiveDateTime.add(old_date, -86_400))
      newer = old_remote_post(remote_user, old_date)

      assert %{contexts: 1} = Retention.run()
      refute Object.get_by_ap_id(older.data["object"])
      assert Object.get_by_ap_id(newer.data["object"])

      assert %{contexts: 1} = Retention.run()
      refute Object.get_by_ap_id(newer.data["object"])
    end

    test "evicts recent unpinned threads when over the object watermark" do
      clear_config([:retention, :max_objects], 1)
      clear_config([:retention, :batch_size], 1)

      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      {:ok, older} = CommonAPI.post(remote_user, %{status: "older"})

      older
      |> Ecto.Changeset.change(%{
        local: false,
        updated_at:
          NaiveDateTime.utc_now() |> NaiveDateTime.add(-60) |> NaiveDateTime.truncate(:second)
      })
      |> Repo.update!()

      {:ok, newer} = CommonAPI.post(remote_user, %{status: "newer"})
      newer |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()

      {:ok, mine} = CommonAPI.post(local_user, %{status: "mine"})

      assert %{contexts: 1} = Retention.run()
      refute Object.get_by_ap_id(older.data["object"])
      assert Object.get_by_ap_id(newer.data["object"])
      assert Object.get_by_ap_id(mine.data["object"])
    end

    test "does not evict anything below the watermark" do
      clear_config([:retention, :max_objects], 100)
      remote_user = insert(:user, local: false)

      {:ok, post} = CommonAPI.post(remote_user, %{status: "fresh"})
      post |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "with keep_non_public it keeps old non-public remote threads", %{old_date: old_date} do
      clear_config([:retention, :keep_non_public], true)
      remote_user = insert(:user, local: false)

      {:ok, private} = CommonAPI.post(remote_user, %{status: "psst", visibility: "private"})
      make_remote_and_old(private, old_date)

      public = old_remote_post(remote_user, old_date)

      assert %{contexts: 1} = Retention.run()
      assert Object.get_by_ap_id(private.data["object"])
      refute Object.get_by_ap_id(public.data["object"])
    end

    test "never touches activities without a context, even over the watermark" do
      clear_config([:retention, :max_objects], 1)
      remote_user = insert(:user, local: false)
      remote_user2 = insert(:user, local: false)
      local_user = insert(:user)

      {:ok, _, _, follow} = CommonAPI.follow(local_user, remote_user)
      {:ok, block} = CommonAPI.block(remote_user2, local_user)

      # Enough objects to trip the watermark
      {:ok, post} = CommonAPI.post(remote_user, %{status: "a"})
      post |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()
      {:ok, post2} = CommonAPI.post(remote_user, %{status: "b"})
      post2 |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()

      for activity <- [follow, block] do
        assert is_nil(activity.data["context"])

        activity
        |> Ecto.Changeset.change(%{local: false})
        |> Repo.update!()
      end

      Retention.run()

      assert Activity.get_by_id(follow.id)
      assert Activity.get_by_id(block.id)
    end

    test "keeps remote reports and the threads they point at", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      reporter = insert(:user, local: false)
      admin = insert(:user, is_admin: true)

      post = old_remote_post(remote_user, old_date)

      flag =
        Repo.insert!(%Activity{
          data: %{
            "id" => "https://domain1.com/activities/#{Ecto.UUID.generate()}",
            "type" => "Flag",
            "actor" => reporter.ap_id,
            "object" => [remote_user.ap_id, post.data["object"]],
            "context" => "https://domain1.com/contexts/#{Ecto.UUID.generate()}",
            "content" => "spam"
          },
          local: false,
          actor: reporter.ap_id,
          recipients: []
        })

      make_old(flag, old_date)
      {:ok, _} = Pleroma.ReportNote.create(admin.id, flag.id, "looking into it")

      assert %{contexts: 0} = Retention.run()
      assert Activity.get_by_id(flag.id)
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "removes remote activities outside the thread that point at evicted objects", %{
      old_date: old_date
    } do
      remote_user = insert(:user, local: false)
      post = old_remote_post(remote_user, old_date)

      delete =
        Repo.insert!(%Activity{
          data: %{
            "id" => "https://domain1.com/activities/#{Ecto.UUID.generate()}",
            "type" => "Delete",
            "actor" => remote_user.ap_id,
            "object" => post.data["object"]
          },
          local: false,
          actor: remote_user.ap_id,
          recipients: []
        })

      assert %{contexts: 1, objects: 1, activities: 2} = Retention.run()
      refute Activity.get_by_id(delete.id)
    end

    test "never deletes local objects, even inside an otherwise remote thread", %{
      old_date: old_date
    } do
      local_user = insert(:user)
      {:ok, post} = CommonAPI.post(local_user, %{status: "mine, honestly"})
      # Pretend the Create activity federated in from elsewhere
      make_remote_and_old(post, old_date)

      assert %{contexts: 1, objects: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "removes hashtags that no longer have objects", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      old_remote_post(remote_user, old_date, %{status: "#lonelytag"})
      assert Pleroma.Hashtag.get_by_name("lonelytag")

      Retention.run()

      refute Pleroma.Hashtag.get_by_name("lonelytag")
    end
  end
end
