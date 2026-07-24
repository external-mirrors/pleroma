# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.DeleteConcurrencyTest do
  use Pleroma.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.MRF
  alias Pleroma.Web.ActivityPub.MRFMock
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.CommonAPI

  import Mox
  import Pleroma.Factory

  test "concurrent Deletes for one object are serialized" do
    parent = self()

    Sandbox.unboxed_run(Repo, fn ->
      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "delete concurrently"})
      object_id = activity.data["object"]
      object = Object.get_by_ap_id(object_id)
      object_database_id = to_string(object.id)

      try do
        MRFMock
        |> stub(:pipeline_filter, fn
          %{"type" => "Delete"} = message, meta ->
            send(parent, {:delete_at_mrf, self()})

            receive do
              :continue_delete -> {:ok, message, meta}
            end

          message, meta ->
            MRF.pipeline_filter(message, meta)
        end)

        first =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:delete_task_started, self()})
              Transmogrifier.handle_incoming(delete_data(activity, user, "first"))
            end)
          end)

        assert_receive {:delete_task_started, _first_task}, 1_000
        assert_receive {:delete_at_mrf, first_pipeline}, 1_000

        second =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(parent, {:delete_task_started, self()})
              Transmogrifier.handle_incoming(delete_data(activity, user, "second"))
            end)
          end)

        assert_receive {:delete_task_started, _second_task}, 1_000

        second_before_first_commit =
          receive do
            {:delete_at_mrf, pid} -> pid
          after
            250 -> nil
          end

        send(first_pipeline, :continue_delete)

        second_pipeline =
          second_before_first_commit ||
            receive do
              {:delete_at_mrf, pid} -> pid
            after
              1_000 -> flunk("second Delete did not continue after the first committed")
            end

        send(second_pipeline, :continue_delete)

        results = [Task.await(first, 5_000), Task.await(second, 5_000)]

        assert is_nil(second_before_first_commit)
        assert Enum.count(results, &match?({:ok, %Activity{}}, &1)) == 1
        assert {:error, :already_deleted} in results
        assert delete_count_for_object(object_id) == 1
      after
        Oban.Job
        |> where(
          [job],
          fragment("?->>'activity' = ?", job.args, ^activity.id) or
            fragment("?->>'activity_id' = ?", job.args, ^activity.id) or
            fragment("?->>'object' = ?", job.args, ^object_database_id)
        )
        |> Repo.delete_all()

        Activity
        |> where([activity], activity.actor == ^user.ap_id)
        |> Repo.delete_all()

        Object
        |> where([object], fragment("?->>'id' = ?", object.data, ^object_id))
        |> Repo.delete_all()

        User
        |> where([stored_user], stored_user.id == ^user.id)
        |> Repo.delete_all()

        Object.invalid_object_cache(object)
        User.invalidate_cache(user)
      end
    end)
  end

  defp delete_data(activity, user, suffix) do
    File.read!("test/fixtures/mastodon-delete.json")
    |> Jason.decode!()
    |> Map.put("id", "#{activity.data["object"]}/delete/#{suffix}")
    |> Map.put("actor", user.ap_id)
    |> put_in(["object", "id"], activity.data["object"])
  end

  defp delete_count_for_object(object_id) do
    Activity
    |> where([activity], fragment("?->>'type' = ?", activity.data, "Delete"))
    |> where([activity], fragment("associated_object_id(?) = ?", activity.data, ^object_id))
    |> Repo.aggregate(:count)
  end
end
