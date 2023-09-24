defmodule Pleroma.Workers.Cron.PruneDatabaseWorkerTest do
  use Pleroma.DataCase, async: true
  import Pleroma.Factory

  alias Pleroma.Activity
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.Workers.Cron.PruneDatabaseWorker

  setup do
    deadline = Pleroma.Config.get([:instance, :remote_post_retention_days]) + 1

    date =
      Timex.now()
      |> Timex.shift(days: -deadline)
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    user = insert(:user)
    user2 = insert(:user)

    {:ok, date: date, user: user, user2: user2}
  end

  test "it prunes old Undo activities from the database", %{
    date: date,
    user: user,
    user2: user2
  } do
    note = insert(:note, user: user, inserted_at: date)

    # undo: the like should be removed as well as the undo
    like1 = insert(:like_activity, user: user, note_activity: note, inserted_at: date)
    undo_old = insert(:undo_activity, user: user, activity_to_undo: like1, inserted_at: date)

    # undo: the like should be removed but not the undo
    like2 = insert(:like_activity, user: user2, note_activity: note, inserted_at: date)
    undo_new = insert(:undo_activity, user: user2, activity_to_undo: like2)

    PruneDatabaseWorker.perform(%Oban.Job{})
    ObanHelpers.perform_all()

    refute Activity.get_by_id(like1.id)
    refute Activity.get_by_id(undo_old.id)

    refute Activity.get_by_id(like2.id)
    assert Activity.get_by_id(undo_new.id)
  end

  test "it prunes old Delete activities from the database", %{
    date: date,
    user: user
  } do
    note1 = insert(:note, user: user, inserted_at: date)
    note2 = insert(:note, user: user, inserted_at: date)

    # delete: the note should be removed as well as the delete
    delete_old = insert(:delete_activity, user: user, note: note1, inserted_at: date)

    # delete: the note should be removed but not the delete
    delete_new = insert(:delete_activity, user: user, note: note2)

    PruneDatabaseWorker.perform(%Oban.Job{})
    ObanHelpers.perform_all()

    refute Activity.get_by_ap_id(note1.data["id"])
    refute Activity.get_by_id(delete_old.id)

    refute Activity.get_by_ap_id(note2.data["id"])
    assert Activity.get_by_id(delete_new.id)
  end

  test "it prunes old Remove activities from the database", %{
    date: date,
    user: user
  } do
    note1 = insert(:note, user: user, inserted_at: date)
    note2 = insert(:note, user: user, inserted_at: date)

    insert(:add_activity, user: user, note: note1, inserted_at: date)
    insert(:add_activity, user: user, note: note2, inserted_at: date)

    # remove_old should be pruned
    remove_old = insert(:remove_activity, user: user, note: note1, inserted_at: date)

    # remove_new should not be pruned
    remove_new = insert(:remove_activity, user: user, note: note2)

    PruneDatabaseWorker.perform(%Oban.Job{})
    ObanHelpers.perform_all()

    refute Activity.get_by_id(remove_old.id)
    assert Activity.get_by_id(remove_new.id)
  end
end
