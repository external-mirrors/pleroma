# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Retention.ProcessedTest do
  use Pleroma.DataCase, async: false

  alias Pleroma.Activity
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Retention.Cursor
  alias Pleroma.Retention.Processed

  import Bitwise
  import Pleroma.Factory

  @config [processed_activity_days: 7, batch_size: 500]

  defp days_ago(days) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-days * 86_400)
    |> NaiveDateTime.truncate(:second)
  end

  # Activity ids are time-ordered flakes; the walk goes by id.
  defp id_from(time) do
    <<ms::integer-size(64), _::binary>> = time |> Cursor.id_at() |> FlakeId.from_string()
    FlakeId.to_string(<<ms::integer-size(64), :rand.uniform(1 <<< 62)::integer-size(64)>>)
  end

  defp activity(type, days, opts \\ []) do
    local = Keyword.get(opts, :local, false)
    user = opts[:user] || insert(:user, local: local)
    time = days_ago(days)

    Repo.insert!(%Activity{
      id: id_from(time),
      data: %{
        "id" => "#{user.ap_id}/activities/#{Ecto.UUID.generate()}",
        "type" => type,
        "actor" => user.ap_id,
        "object" => opts[:object] || "https://remote.example/objects/#{Ecto.UUID.generate()}"
      },
      local: local,
      actor: user.ap_id,
      recipients: [],
      inserted_at: time,
      updated_at: time
    })
  end

  describe "prune_activities/1" do
    test "prunes remote Delete, Undo and Update activities once processed" do
      old = for type <- ~w(Delete Undo Update), do: activity(type, 10)

      assert Processed.prune_activities(@config) == 3

      for a <- old, do: refute(Activity.get_by_id(a.id))
    end

    test "keeps them for processed_activity_days, to recognise duplicates" do
      recent = activity("Delete", 3)

      assert Processed.prune_activities(@config) == 0
      assert Activity.get_by_id(recent.id)
    end

    test "keeps local activities" do
      local = activity("Delete", 10, local: true)

      assert Processed.prune_activities(@config) == 0
      assert Activity.get_by_id(local.id)
    end

    test "keeps other activity types" do
      kept = for type <- ~w(Create Like Announce Follow Flag), do: activity(type, 10)

      assert Processed.prune_activities(@config) == 0
      for a <- kept, do: assert(Activity.get_by_id(a.id))
    end

    test "keeps an Update that a local user still has a notification for" do
      local_user = insert(:user)
      update = activity("Update", 10)

      Repo.insert!(%Notification{user_id: local_user.id, activity_id: update.id, type: "update"})

      assert Processed.prune_activities(@config) == 0
      assert Activity.get_by_id(update.id)
    end

    test "does nothing without processed_activity_days" do
      old = activity("Delete", 10)

      assert Processed.prune_activities(Keyword.delete(@config, :processed_activity_days)) == 0
      assert Activity.get_by_id(old.id)
    end

    test "ignores nonsensical settings" do
      old = activity("Delete", 10)

      assert Processed.prune_activities(Keyword.put(@config, :batch_size, 0)) == 0
      assert Processed.prune_activities(Keyword.put(@config, :processed_activity_days, -1)) == 0
      assert is_nil(Cursor.get("processed_activities"))
      assert Activity.get_by_id(old.id)
    end

    test "walks in batches and does not rescan" do
      config = Keyword.put(@config, :batch_size, 1)
      older = activity("Delete", 12)
      newer = activity("Delete", 11)

      assert Processed.prune_activities(config) == 1
      refute Activity.get_by_id(older.id)
      assert Activity.get_by_id(newer.id)

      assert Processed.prune_activities(config) == 1
      refute Activity.get_by_id(newer.id)

      # An old activity behind the cursor is not visited again.
      behind = activity("Delete", 20)
      assert Processed.prune_activities(config) == 0
      assert Activity.get_by_id(behind.id)
    end
  end

  describe "prune_tombstones/1" do
    @config [tombstone_days: 30, batch_size: 500]

    defp tombstone(days, opts \\ []) do
      base = if opts[:local], do: Pleroma.Web.Endpoint.url(), else: "https://remote.example"
      time = days_ago(days)

      Repo.insert!(%Object{
        data: %{
          "id" => "#{base}/objects/#{Ecto.UUID.generate()}",
          "type" => "Tombstone",
          "formerType" => "Note",
          "deleted" => NaiveDateTime.to_iso8601(time)
        },
        inserted_at: days_ago(days + 100),
        updated_at: time
      })
    end

    test "prunes remote tombstones deleted longer ago than tombstone_days" do
      old = tombstone(40)
      delete = activity("Delete", 40, object: old.data["id"])

      assert Processed.prune_tombstones(@config) == 1
      refute Object.get_by_id(old.id)
      refute Activity.get_by_id(delete.id)
    end

    test "keeps recent tombstones, so deleted posts are not fetched again" do
      recent = tombstone(10)

      assert Processed.prune_tombstones(@config) == 0
      assert Object.get_by_id(recent.id)
    end

    test "keeps local tombstones" do
      local = tombstone(40, local: true)

      assert Processed.prune_tombstones(@config) == 0
      assert Object.get_by_id(local.id)
    end

    test "keeps tombstones a local activity points at" do
      pointed_at = tombstone(40)
      local_activity = activity("Undo", 40, local: true, object: pointed_at.data["id"])

      assert Processed.prune_tombstones(@config) == 0
      assert Object.get_by_id(pointed_at.id)
      assert Activity.get_by_id(local_activity.id)
    end

    test "keeps other objects" do
      note = insert(:note, updated_at: days_ago(400))

      assert Processed.prune_tombstones(@config) == 0
      assert Object.get_by_id(note.id)
    end

    test "prunes at most batch_size tombstones, oldest first" do
      older = tombstone(50)
      newer = tombstone(40)

      assert Processed.prune_tombstones(Keyword.put(@config, :batch_size, 1)) == 1
      refute Object.get_by_id(older.id)
      assert Object.get_by_id(newer.id)
    end

    test "walks tombstones once and does not look at skipped ones again" do
      config = Keyword.put(@config, :batch_size, 1)
      local = tombstone(50, local: true)
      remote = tombstone(40)

      assert Processed.prune_tombstones(config) == 0
      assert Processed.prune_tombstones(config) == 1
      refute Object.get_by_id(remote.id)

      # Behind the cursor now: not visited again.
      behind = tombstone(45)
      assert Processed.prune_tombstones(config) == 0
      assert Object.get_by_id(behind.id)
      assert Object.get_by_id(local.id)
    end

    test "ignores nonsensical settings" do
      old = tombstone(40)

      assert Processed.prune_tombstones(Keyword.put(@config, :batch_size, 0)) == 0
      assert Processed.prune_tombstones(Keyword.put(@config, :tombstone_days, -1)) == 0
      assert Object.get_by_id(old.id)
    end

    test "does nothing without tombstone_days" do
      old = tombstone(40)

      assert Processed.prune_tombstones(Keyword.delete(@config, :tombstone_days)) == 0
      assert Object.get_by_id(old.id)
    end
  end
end
