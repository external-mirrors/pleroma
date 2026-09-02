# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Retention do
  @moduledoc """
  Bounded retention of remote content.

  Local content is data; remote content is a cache of somebody else's data.
  This module treats it that way: a remote thread is evictable when nobody
  local has interacted with it and it has been quiet for longer than
  `remote_post_retention_days`, or when the objects table has grown past the
  configured watermark. Local posts are never evicted.

  A thread is pinned (never evicted) if any activity in it

    * is local (posts, replies, favourites, repeats and reactions by local
      users all carry the thread's context),
    * is bookmarked by a local user,
    * still has a notification for a local user (mentions),
    * is a report (Flag),

  or if any object in it is referenced by a report.

  Only activities that carry a context take part; relationship activities
  such as Follow or Block and chat messages have none and are never touched.

  Eviction works in bounded batches so it can run continuously from a cron
  worker (`Pleroma.Workers.Cron.RetentionWorker`); the aim is a database that
  plateaus rather than one that has to be shrunk in maintenance windows.
  """

  import Ecto.Query

  alias Pleroma.Activity
  alias Pleroma.Bookmark
  alias Pleroma.Config
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo

  require Logger
  require Pleroma.Constants

  @type stats :: %{
          contexts: non_neg_integer(),
          objects: non_neg_integer(),
          activities: non_neg_integer()
        }

  @empty_stats %{contexts: 0, objects: 0, activities: 0}

  @doc """
  Runs one eviction batch using the `:retention` config and returns what was removed.
  """
  @spec run(keyword()) :: stats()
  def run(config \\ Config.get(:retention, [])) do
    deadline = deadline()
    over_watermark = over_watermark?(config[:max_objects])

    query =
      deadline
      |> evictable_contexts_query(
        keep_non_public: config[:keep_non_public],
        ignore_deadline: over_watermark
      )
      |> order_by([a], asc: max(a.updated_at), asc: fragment("min(?::text)", a.id))
      |> limit(^(config[:batch_size] || 500))
      |> select([a], %{
        activity_ids: type(fragment("array_agg(?)", a.id), {:array, FlakeId.Ecto.CompatType}),
        object_ids: fragment("array_agg(associated_object_id(?))", a.data)
      })

    # Select and delete in one transaction, so a local interaction that lands
    # in between cannot be left pointing at an evicted object.
    {:ok, stats} =
      Repo.transaction(
        fn ->
          query
          |> Repo.all(timeout: :infinity)
          |> evict()
        end,
        timeout: :infinity
      )

    if stats.contexts > 0, do: delete_unused_hashtags()

    stats
  end

  @doc """
  The point in time before which a quiet remote thread becomes evictable.
  """
  @spec deadline() :: NaiveDateTime.t()
  def deadline do
    days = Config.get([:instance, :remote_post_retention_days])
    NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400)
  end

  @doc """
  Activities grouped by thread context, restricted to threads that may be evicted.

  The query has no `select`; callers pick what they need from the group (the
  context alone for `IN (subquery)`, or aggregates of ids for deletion).

  Options:

    * `:keep_non_public` - also pin threads containing a non-public post
    * `:ignore_deadline` - consider every unpinned thread, not just quiet ones
  """
  @spec evictable_contexts_query(NaiveDateTime.t(), keyword()) :: Ecto.Query.t()
  def evictable_contexts_query(deadline, opts \\ []) do
    ignore_deadline = Keyword.get(opts, :ignore_deadline, false) == true

    Activity
    |> join(:left, [a], b in Bookmark, on: a.id == b.activity_id)
    |> join(:left, [a], n in Notification, on: a.id == n.activity_id)
    |> where([a], not is_nil(fragment("? ->> 'context'", a.data)))
    |> where([a], fragment("? ->> 'context'", a.data) not in subquery(reported_contexts_query()))
    |> group_by([a], fragment("? ->> 'context'", a.data))
    |> having([a], max(a.updated_at) < ^deadline or ^ignore_deadline)
    |> having([a], not fragment("bool_or(?)", a.local))
    |> having([_, b], fragment("max(?::text) is null", b.id))
    |> having([_, _, n], fragment("max(?) is null", n.id))
    |> maybe_keep_non_public(Keyword.get(opts, :keep_non_public, false) == true)
  end

  defp maybe_keep_non_public(query, false), do: query

  defp maybe_keep_non_public(query, true) do
    having(
      query,
      [a],
      not fragment(
        # Posts (checked on Create Activity) is non-public
        "bool_or((not(?->'to' \\? ? OR ?->'cc' \\? ?)) and ? ->> 'type' = 'Create')",
        a.data,
        ^Pleroma.Constants.as_public(),
        a.data,
        ^Pleroma.Constants.as_public(),
        a.data
      )
    )
  end

  # Contexts touched by reports: the contexts of the reported objects, plus the
  # Flag activities' own contexts (a report gets a fresh context of its own).
  # Flag objects are a list mixing actor ids, object ids and embedded copies
  # of objects with an "id"; a single object instead of a list is tolerated.
  defp reported_contexts_query do
    flags = where(Activity, [f], fragment("? ->> 'type' = 'Flag'", f.data))

    reported_objects =
      flags
      |> join(
        :inner,
        [f],
        fo in fragment(
          "jsonb_array_elements(CASE WHEN jsonb_typeof(? -> 'object') = 'array' THEN ? -> 'object' ELSE jsonb_build_array(? -> 'object') END)",
          f.data,
          f.data,
          f.data
        ),
        on: true
      )
      |> join(:inner, [_, fo], o in Object,
        on: fragment("? ->> 'id' = coalesce(? ->> 'id', ? #>> '{}')", o.data, fo.value, fo.value)
      )
      |> where([_, _, o], not is_nil(fragment("? ->> 'context'", o.data)))
      |> select([_, _, o], fragment("? ->> 'context'", o.data))

    flags
    |> where([f], not is_nil(fragment("? ->> 'context'", f.data)))
    |> select([f], fragment("? ->> 'context'", f.data))
    |> union(^reported_objects)
  end

  @doc """
  Deletes the given threads. Each entry carries the activity ids and object
  ids collected by `run/1`, so deletion uses primary key and ap_id indexes only.
  """
  @spec evict([%{activity_ids: [String.t()], object_ids: [String.t() | nil]}]) :: stats()
  def evict([]), do: @empty_stats

  def evict(threads) do
    activity_ids = Enum.flat_map(threads, & &1.activity_ids)
    object_ids = threads |> Enum.flat_map(& &1.object_ids) |> Enum.reject(&is_nil/1)

    {:ok, stats} =
      Repo.transaction(
        fn ->
          {objects, deleted_ap_ids} =
            Object
            |> where([o], fragment("? ->> 'id'", o.data) in ^object_ids)
            |> where(
              [o],
              fragment(
                "left(? ->> 'actor', ?) != ?",
                o.data,
                ^local_prefix_length(),
                ^local_prefix()
              )
            )
            |> select([o], fragment("? ->> 'id'", o.data))
            |> Repo.delete_all(timeout: :infinity)

          {activities, _} =
            Activity
            |> where([a], a.id in ^activity_ids)
            |> where([a], a.local == false)
            |> where([a], fragment("? ->> 'type' != 'Flag'", a.data))
            |> Repo.delete_all(timeout: :infinity)

          # Remote activities outside the thread that point at objects we just
          # removed (e.g. Deletes carry no context). Flags are kept as they
          # may have report notes attached.
          {referencing, _} =
            Activity
            |> where([a], a.local == false)
            |> where([a], fragment("associated_object_id(?)", a.data) in ^deleted_ap_ids)
            |> where([a], fragment("? ->> 'type' != 'Flag'", a.data))
            |> Repo.delete_all(timeout: :infinity)

          %{
            contexts: length(threads),
            objects: objects,
            activities: activities + referencing
          }
        end,
        timeout: :infinity
      )

    stats
  end

  @doc """
  Whether the objects table is estimated to hold more rows than `max_objects`.
  """
  @spec over_watermark?(non_neg_integer() | nil) :: boolean()
  def over_watermark?(nil), do: false
  def over_watermark?(max_objects), do: estimated_object_count() > max_objects

  @doc """
  Row count of the objects table from planner statistics, falling back to an
  exact count when the table has never been analyzed.
  """
  @spec estimated_object_count() :: non_neg_integer()
  def estimated_object_count do
    %{rows: [[estimate]]} =
      Repo.query!("SELECT reltuples::bigint FROM pg_class WHERE oid = 'objects'::regclass")

    if estimate > 0, do: estimate, else: Repo.aggregate(Object, :count, timeout: :infinity)
  end

  @doc """
  Removes hashtags no longer attached to any object and not followed by anyone.
  """
  @spec delete_unused_hashtags() :: :ok
  def delete_unused_hashtags do
    Repo.query!(
      """
      DELETE FROM hashtags AS ht
      WHERE NOT EXISTS (
        SELECT 1 FROM hashtags_objects hto
        WHERE ht.id = hto.hashtag_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM user_follows_hashtag ufh
        WHERE ht.id = ufh.hashtag_id
      )
      """,
      [],
      timeout: :infinity
    )

    :ok
  end

  # Actor ids of local users start with the instance url; an exact prefix
  # comparison avoids LIKE wildcards and host/port ambiguity.
  defp local_prefix, do: Pleroma.Web.Endpoint.url() <> "/"
  defp local_prefix_length, do: String.length(local_prefix())
end
