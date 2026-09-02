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

  import Bitwise
  import Ecto.Query
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

  # Activity ids are time-ordered flakes and the retention walk goes by id, so
  # an "old" activity needs an old id as well as an old timestamp. Must be
  # applied before anything references the activity (bookmarks, notifications).
  defp age(%Activity{} = activity, old_date, changes) do
    ms = old_date |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)

    old_id =
      FlakeId.to_string(<<ms::integer-size(64), :rand.uniform(1 <<< 62)::integer-size(64)>>)

    changes = Map.merge(%{id: old_id, updated_at: old_date}, changes)

    {1, _} =
      Activity
      |> where([a], a.id == ^activity.id)
      |> Repo.update_all(set: Map.to_list(changes))

    Map.merge(activity, changes)
  rescue
    e in Postgrex.Error ->
      reraise "age/3 must run before anything references the activity: #{Exception.message(e)}",
              __STACKTRACE__
  end

  # Posts made through CommonAPI are local; turn the activity into a remote one
  # and backdate it so it looks like an old federated post.
  defp make_remote_and_old(activity, old_date), do: age(activity, old_date, %{local: false})

  defp make_old(activity, old_date), do: age(activity, old_date, %{})

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

      {:ok, post} = CommonAPI.post(remote_user, %{status: "hey @#{local_user.nickname}"})
      Repo.delete_all(Pleroma.Notification)
      post = make_remote_and_old(post, old_date)
      assert {:ok, [_]} = Pleroma.Notification.create_notifications(post)

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

      flag = make_old(flag, old_date)
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

    test "remembers where it got to and does not rescan", %{old_date: old_date} do
      clear_config([:retention, :batch_size], 1)
      remote_user = insert(:user, local: false)

      post = old_remote_post(remote_user, old_date)
      assert is_nil(Retention.Cursor.get("activities"))

      assert %{contexts: 1} = Retention.run()
      assert Retention.Cursor.get("activities") == post.id

      # An older activity that appears behind the cursor is not visited again
      # until the cursor is reset.
      older = old_remote_post(remote_user, NaiveDateTime.add(old_date, -86_400))
      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(older.data["object"])

      Retention.Cursor.reset("activities")
      assert %{contexts: 1} = Retention.run()
      refute Object.get_by_ap_id(older.data["object"])
    end

    test "keeps an old thread that is still active", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      remote_user2 = insert(:user, local: false)

      post = old_remote_post(remote_user, old_date)

      {:ok, reply} =
        CommonAPI.post(remote_user2, %{status: "still here", in_reply_to_status_id: post.id})

      reply |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()

      assert %{contexts: 0} = Retention.run()
      assert Object.get_by_ap_id(post.data["object"])
    end

    test "keeps threads pinned by each local interaction type", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      local_user = insert(:user)

      liked = old_remote_post(remote_user, old_date)
      {:ok, like} = CommonAPI.favorite(liked.id, local_user)
      make_old(like, old_date)

      repeated = old_remote_post(remote_user, old_date)
      {:ok, announce} = CommonAPI.repeat(repeated.id, local_user)
      make_old(announce, old_date)

      reacted = old_remote_post(remote_user, old_date)
      {:ok, react} = CommonAPI.react_with_emoji(reacted.id, local_user, "👍")
      make_old(react, old_date)

      replied = old_remote_post(remote_user, old_date)
      {:ok, reply} = CommonAPI.post(local_user, %{status: "r", in_reply_to_status_id: replied.id})
      make_old(reply, old_date)

      assert %{contexts: 0} = Retention.run()

      for post <- [liked, repeated, reacted, replied] do
        assert Object.get_by_ap_id(post.data["object"])
      end
    end

    test "a watermark run does not stall the age-based walk", %{old_date: old_date} do
      remote_user = insert(:user, local: false)

      clear_config([:retention, :max_objects], 0)
      {:ok, recent} = CommonAPI.post(remote_user, %{status: "recent"})
      recent |> Ecto.Changeset.change(%{local: false}) |> Repo.update!()
      assert %{contexts: 1} = Retention.run()
      refute Object.get_by_ap_id(recent.data["object"])

      clear_config([:retention, :max_objects], nil)
      old = old_remote_post(remote_user, old_date)
      assert %{contexts: 1} = Retention.run()
      refute Object.get_by_ap_id(old.data["object"])
    end

    test "moves the cursor to the deadline once everything old is done", %{old_date: old_date} do
      remote_user = insert(:user, local: false)
      old_remote_post(remote_user, old_date)

      Retention.run()

      <<cursor_ms::integer-size(64), _::integer-size(64)>> =
        FlakeId.from_string(Retention.Cursor.get("activities"))

      deadline_ms =
        Retention.deadline()
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix(:millisecond)

      assert_in_delta cursor_ms, deadline_ms, 5_000
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
