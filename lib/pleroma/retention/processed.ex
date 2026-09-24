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

  Remote tombstones stop deleted posts from being fetched again while their
  threads are still active. After `tombstone_days` they are pruned, together
  with remote activities still pointing at them, unless a local activity
  does.
  """

  import Ecto.Query

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Retention
  alias Pleroma.Retention.Cursor

  @types ~w(Delete Undo Update)
  @cursor "processed_activities"
  @tombstone_cursor "tombstones"
  @default_batch_size 50_000

  @doc """
  Prunes the next batch of processed remote activities and returns how many
  were deleted. Does nothing without `processed_activity_days`.
  """
  @spec prune_activities(keyword()) :: non_neg_integer()
  def prune_activities(config) do
    case settings(config, :processed_activity_days) do
      {deadline, budget} -> walk(Cursor.id_at(deadline), budget)
      nil -> 0
    end
  end

  @doc """
  Prunes the next batch of remote tombstones deleted more than
  `tombstone_days` ago and returns how many were deleted. Does nothing
  without `tombstone_days`.

  Tombstones are walked in deletion order with a persisted cursor, so the
  ones that are kept (local, or pointed at by a local activity) are not
  looked at again on every run.
  """
  @spec prune_tombstones(keyword()) :: non_neg_integer()
  def prune_tombstones(config) do
    case settings(config, :tombstone_days) do
      {deadline, budget} ->
        {:ok, deleted} =
          Repo.transaction(fn -> walk_tombstones(deadline, budget) end, timeout: :infinity)

        deleted

      nil ->
        0
    end
  end

  defp settings(config, key) do
    days = config[key]
    budget = config[:batch_size] || @default_batch_size

    if is_integer(days) and days >= 0 and is_integer(budget) and budget > 0,
      do: {NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400), budget}
  end

  defp walk_tombstones(deadline, budget) do
    rows =
      deadline
      |> tombstones_after(Cursor.get(@tombstone_cursor), budget)
      |> Repo.all(timeout: :infinity)

    case List.last(rows) do
      nil -> :ok
      last -> Cursor.put(@tombstone_cursor, position(last.updated_at, last.id))
    end

    rows |> Enum.filter(& &1.deletable) |> delete_tombstones()
  end

  defp tombstones_after(deadline, from, budget) do
    prefix = Retention.local_prefix()

    Object
    |> where([o], fragment("? ->> 'type' = 'Tombstone'", o.data))
    |> where([o], o.updated_at < ^deadline)
    |> after_position(from)
    |> order_by([o], asc: o.updated_at, asc: o.id)
    |> limit(^budget)
    |> select([o], %{
      id: o.id,
      updated_at: o.updated_at,
      ap_id: fragment("? ->> 'id'", o.data),
      deletable:
        fragment(
          "left(? ->> 'id', ?) != ? AND NOT EXISTS (SELECT 1 FROM activities a WHERE associated_object_id(a.data) = ? ->> 'id' AND a.local)",
          o.data,
          ^String.length(prefix),
          ^prefix,
          o.data
        )
    })
  end

  # Tombstone positions are flake-shaped: the deletion time in milliseconds,
  # then the object id to break ties between tombstones deleted together.
  defp position(updated_at, id) do
    ms = updated_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)
    FlakeId.to_string(<<ms::integer-size(64), id::integer-size(64)>>)
  end

  defp after_position(query, nil), do: query

  defp after_position(query, position) do
    <<ms::integer-size(64), id::integer-size(64)>> = FlakeId.from_string(position)
    time = ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_naive()
    where(query, [o], fragment("(?, ?) > (?, ?)", o.updated_at, o.id, ^time, ^id))
  end

  defp delete_tombstones([]), do: 0

  defp delete_tombstones(rows) do
    # Normally just the remote Delete, if it has not been pruned yet.
    Activity
    |> Activity.Queries.by_object_id(Enum.map(rows, & &1.ap_id))
    |> where([a], a.local == false)
    |> Repo.delete_all(timeout: :infinity)

    {deleted, _} =
      Object
      |> where([o], o.id in ^Enum.map(rows, & &1.id))
      |> Repo.delete_all(timeout: :infinity)

    deleted
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
