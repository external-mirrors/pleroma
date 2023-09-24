defmodule Pleroma.Activity.PrunerTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Activity
  alias Pleroma.Activity.Pruner

  import Pleroma.Factory

  describe "prune activities" do
    @spec test_prune(atom(), String.t(), (() -> any())) :: :ok
    defp test_prune(activity, activity_type, prunefn) do
      deadline = Pleroma.Config.get([:instance, :remote_post_retention_days]) + 1

      date =
        Timex.now()
        |> Timex.shift(days: -deadline)
        |> Timex.to_naive_datetime()
        |> NaiveDateTime.truncate(:second)

      user = insert(:user)

      new_activity = insert(activity, type: activity_type, user: user)

      old_activity =
        insert(activity,
          type: activity_type,
          user: user,
          inserted_at: date
        )

      prunefn.()
      assert Activity.get_by_id(new_activity.id)
      refute Activity.get_by_id(old_activity.id)
    end

    test "it prunes old Delete objects" do
      test_prune(:delete_activity, "Delete", &Pruner.prune_deletes/0)
    end

    test "it prunes old Undo objects" do
      test_prune(:undo_activity, "Undo", &Pruner.prune_undos/0)
    end

    test "it prunes old Remove objects" do
      test_prune(:remove_activity, "Remove", &Pruner.prune_removes/0)
    end
  end
end
