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

  ## How a run works

  Grouping the whole activities table by thread is far too expensive to do
  every hour on a large instance, so `run/1` walks the table incrementally
  instead. Activity ids are ordered by creation time, so a run scans the next
  `batch_size` activities after a persisted cursor (`Pleroma.Retention.Cursor`)
  up to the id that corresponds to the retention deadline, collects the
  threads they belong to, and verifies just those threads through the
  `(type, context)` index. Threads that pass are evicted; the cursor moves on.
  Every activity is thus visited exactly once, when it becomes old enough,
  and a thread is re-checked whenever another of its activities ages out.
  A thread that was kept because an activity's `updated_at` was bumped
  after insertion is only re-checked on the next full walk, i.e. after a
  cursor reset. Over the object watermark a second walk, with its own
  cursor, runs up to the present instead of the deadline.

  The first run starts from the oldest activity, which doubles as the
  initial cut on an instance that never pruned. `prune_objects --keep-threads`
  does the same job in one go and is faster for that purpose.
  """

  import Ecto.Query

  alias Pleroma.Activity
  alias Pleroma.Bookmark
  alias Pleroma.Config
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Retention.Cursor

  require Logger
  require Pleroma.Constants

  @type stats :: %{
          contexts: non_neg_integer(),
          objects: non_neg_integer(),
          activities: non_neg_integer()
        }

  @empty_stats %{contexts: 0, objects: 0, activities: 0}

  @default_batch_size 50_000
  # Activities per verification chunk; the cursor is persisted after each.
  @chunk 5_000

  # Activity types that may carry a thread's context. Restricting the
  # per-thread lookups to these lets them use the (type, context) index.
  #
  # Invariant: every type that *adopts* another activity's context must be
  # listed, or its thread's local pins become invisible to the walk and the
  # thread gets evicted. Today only Create, Announce, Like and EmojiReact do
  # (see Pleroma.Web.ActivityPub.Builder). The others carry a context of
  # their own (or did in older data) and are listed so they get evicted
  # rather than left behind. The regression test "keeps threads pinned by
  # each local interaction type" guards this.
  @context_types ~w(Create Announce Like EmojiReact Update Delete Undo Flag Listen Move)

  @doc """
  Runs one eviction batch using the `:retention` config and returns what was removed.
  """
  @spec run(keyword()) :: stats()
  def run(config \\ Config.get(:retention, [])) do
    deadline = deadline()
    over_watermark = over_watermark?(config[:max_objects])
    budget = config[:batch_size] || @default_batch_size

    # Over the watermark every unpinned thread is fair game, so a separate
    # walk goes right up to the present. It must not share the cursor with
    # the age-based walk, or that one would be left behind the deadline.
    {cursor, boundary} =
      if over_watermark,
        do: {"activities_watermark", id_at(NaiveDateTime.utc_now())},
        else: {"activities", id_at(deadline)}

    opts = [
      keep_non_public: config[:keep_non_public],
      ignore_deadline: over_watermark,
      skip_reported: reported_contexts()
    ]

    from = Cursor.get(cursor)
    rows = candidates(from, boundary, budget)

    stats =
      rows
      |> Enum.chunk_every(@chunk)
      |> Enum.reduce(@empty_stats, fn chunk, acc ->
        stats = chunk |> contexts_of() |> evict_threads(deadline, opts)
        # Persist progress per chunk, so a killed or crashed run resumes
        # where it stopped instead of re-walking the whole range.
        Cursor.put(cursor, chunk |> List.last() |> elem(0))
        Map.merge(acc, stats, fn _key, x, y -> x + y end)
      end)

    # Fewer rows than asked for: everything up to the boundary is done.
    if length(rows) < budget and after?(boundary, from), do: Cursor.put(cursor, boundary)
    if stats.contexts > 0, do: delete_unused_hashtags()

    stats
  end

  # The next `budget` activities after `from`, up to `boundary`.
  defp candidates(from, boundary, budget) do
    Activity
    |> where([a], a.id <= ^boundary)
    |> maybe_after(from)
    |> order_by([a], asc: a.id)
    |> limit(^budget)
    |> select([a], {a.id, a.local, fragment("? ->> 'context'", a.data)})
    |> Repo.all(timeout: :infinity)
  end

  defp maybe_after(query, nil), do: query
  defp maybe_after(query, from), do: where(query, [a], a.id > ^from)

  defp contexts_of(rows) do
    for {_id, false, context} when is_binary(context) <- rows, uniq: true, do: context
  end

  defp after?(_id, nil), do: true
  defp after?(id, other), do: FlakeId.from_string(id) > FlakeId.from_string(other)

  # Verifies the given threads against the pin rules and evicts those that
  # pass, in one transaction so a local interaction landing in between cannot
  # be left pointing at an evicted object.
  defp evict_threads([], _deadline, _opts), do: @empty_stats

  defp evict_threads(contexts, deadline, opts) do
    query =
      deadline
      |> evictable_contexts_query(Keyword.put(opts, :contexts, contexts))
      |> select([a], %{
        activity_ids: type(fragment("array_agg(?)", a.id), {:array, FlakeId.Ecto.CompatType}),
        object_ids: fragment("array_agg(associated_object_id(?))", a.data)
      })

    {:ok, stats} =
      Repo.transaction(
        fn ->
          query
          |> Repo.all(timeout: :infinity)
          |> evict()
        end,
        timeout: :infinity
      )

    stats
  end

  # The activity id a flake would have received at the given time. Ids at or
  # below it belong to activities created before then.
  defp id_at(%NaiveDateTime{} = time) do
    ms = time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond) |> max(0)
    FlakeId.to_string(<<ms::integer-size(64), 0::integer-size(64)>>)
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
    * `:contexts` - only look at these threads, using the `(type, context)`
      index; without it the whole table is grouped
    * `:skip_reported` - a `MapSet` of reported contexts already removed from
      `:contexts` by the caller, so the subquery for them can be skipped
  """
  @spec evictable_contexts_query(NaiveDateTime.t(), keyword()) :: Ecto.Query.t()
  def evictable_contexts_query(deadline, opts \\ []) do
    ignore_deadline = Keyword.get(opts, :ignore_deadline, false) == true

    contexts =
      case {Keyword.get(opts, :contexts), Keyword.get(opts, :skip_reported)} do
        {nil, _} -> nil
        {contexts, nil} -> contexts
        {contexts, reported} -> Enum.reject(contexts, &MapSet.member?(reported, &1))
      end

    Activity
    |> join(:left, [a], b in Bookmark, on: a.id == b.activity_id)
    |> join(:left, [a], n in Notification, on: a.id == n.activity_id)
    |> where([a], not is_nil(fragment("? ->> 'context'", a.data)))
    |> maybe_exclude_reported(is_nil(Keyword.get(opts, :skip_reported)))
    |> maybe_only_contexts(contexts)
    |> group_by([a], fragment("? ->> 'context'", a.data))
    |> having([a], max(a.updated_at) < ^deadline or ^ignore_deadline)
    |> having([a], not fragment("bool_or(?)", a.local))
    |> having([_, b], fragment("max(?::text) is null", b.id))
    |> having([_, _, n], fragment("max(?) is null", n.id))
    |> maybe_keep_non_public(Keyword.get(opts, :keep_non_public, false) == true)
  end

  defp maybe_exclude_reported(query, false), do: query

  defp maybe_exclude_reported(query, true) do
    where(
      query,
      [a],
      fragment("? ->> 'context'", a.data) not in subquery(reported_contexts_query())
    )
  end

  @doc "Contexts of reported objects and of the reports themselves."
  @spec reported_contexts() :: MapSet.t(String.t())
  def reported_contexts do
    reported_contexts_query() |> Repo.all(timeout: :infinity) |> MapSet.new()
  end

  defp maybe_only_contexts(query, nil), do: query

  defp maybe_only_contexts(query, contexts) do
    query
    |> where([a], fragment("? ->> 'type'", a.data) in ^@context_types)
    |> where([a], fragment("? ->> 'context'", a.data) in ^contexts)
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
  ids collected per thread, so deletion uses primary key and ap_id indexes only.
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
