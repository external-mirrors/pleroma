# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Retention.ProcessedTest do
  use Pleroma.DataCase, async: false

  alias Pleroma.Activity
  alias Pleroma.Notification
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
end
