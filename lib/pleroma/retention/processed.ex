# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Retention.Processed do
  @moduledoc """
  Prunes remote data that only mattered while it was being processed.

  Remote Delete, Undo and Update activities have done their work once their
  side effects are applied: the object is a tombstone, the like is gone, the
  profile or post is updated. They are kept for `processed_activity_days`
  only, because incoming activities are recognised as duplicates by their
  stored copy, and deliveries of the same Delete keep arriving for a while.
  An Update a local user still has a notification for is kept.

  The walk goes by activity id with a persisted cursor, like
  `Pleroma.Retention`, so each activity is looked at once.
  """

  import Ecto.Query

  alias Pleroma.Activity
  alias Pleroma.Repo
  alias Pleroma.Retention.Cursor

  @types ~w(Delete Undo Update)
  @cursor "processed_activities"
  @default_batch_size 50_000

  @doc """
  Prunes the next batch of processed remote activities and returns how many
  were deleted. Does nothing without `processed_activity_days`.
  """
  @spec prune_activities(keyword()) :: non_neg_integer()
  def prune_activities(config) do
    case config[:processed_activity_days] do
      days when is_integer(days) ->
        deadline = NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400)
        walk(Cursor.id_at(deadline), config[:batch_size] || @default_batch_size)

      _ ->
        0
    end
  end

  defp walk(boundary, budget) do
    from = Cursor.get(@cursor)

    if Cursor.after?(boundary, from) do
      # The end of this batch: the budget-th activity, or the boundary when
      # fewer are left.
      upto = nth_id(from, boundary, budget) || boundary

      {deleted, _} =
        Activity
        |> in_range(from, upto)
        |> where([a], a.local == false)
        |> where([a], fragment("? ->> 'type'", a.data) in ^@types)
        |> where(
          [a],
          fragment("NOT EXISTS (SELECT 1 FROM notifications n WHERE n.activity_id = ?)", a.id)
        )
        |> Repo.delete_all(timeout: :infinity)

      Cursor.put(@cursor, upto)
      deleted
    else
      0
    end
  end

  defp nth_id(from, boundary, budget) do
    Activity
    |> in_range(from, boundary)
    |> order_by([a], asc: a.id)
    |> offset(^(budget - 1))
    |> limit(1)
    |> select([a], a.id)
    |> Repo.one(timeout: :infinity)
  end

  defp in_range(query, nil, upto), do: where(query, [a], a.id <= ^upto)
  defp in_range(query, from, upto), do: where(query, [a], a.id > ^from and a.id <= ^upto)
end
