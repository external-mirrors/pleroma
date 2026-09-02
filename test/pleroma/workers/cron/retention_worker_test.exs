# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.Cron.RetentionWorkerTest do
  use Pleroma.DataCase, async: false

  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Workers.Cron.RetentionWorker

  import Ecto.Query
  import Pleroma.Factory

  setup do
    clear_config([:instance, :remote_post_retention_days], 90)

    remote_user = insert(:user, local: false)
    {:ok, post} = CommonAPI.post(remote_user, %{status: "old"})

    old_date =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-200 * 86_400)
      |> NaiveDateTime.truncate(:second)

    ms = old_date |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)
    old_id = FlakeId.to_string(<<ms::integer-size(64), 1::integer-size(64)>>)

    {1, _} =
      Pleroma.Activity
      |> where([a], a.id == ^post.id)
      |> Repo.update_all(set: [id: old_id, local: false, updated_at: old_date])

    %{object_id: post.data["object"]}
  end

  test "does nothing when disabled", %{object_id: object_id} do
    clear_config([:retention, :enabled], false)

    assert :ok = RetentionWorker.perform(%Oban.Job{})
    assert Object.get_by_ap_id(object_id)
  end

  test "evicts when enabled", %{object_id: object_id} do
    clear_config([:retention, :enabled], true)
    clear_config([:retention, :batch_size], 500)

    assert :ok = RetentionWorker.perform(%Oban.Job{})
    refute Object.get_by_ap_id(object_id)
  end
end
