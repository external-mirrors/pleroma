# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Activity.Search do
  alias Pleroma.Activity
  alias Pleroma.Object.Fetcher
  alias Pleroma.Pagination
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Visibility

  require Pleroma.Constants

  import Ecto.Query

  def search(user, search_query, options \\ []) do
    index_type = if Pleroma.Config.get([:database, :rum_enabled]), do: :rum, else: :gin
    limit = Enum.min([Keyword.get(options, :limit), 40])
    offset = Keyword.get(options, :offset, 0)
    author = Keyword.get(options, :author)

    search_function =
      if :persistent_term.get({Pleroma.Repo, :postgres_version}) >= 11 do
        :websearch
      else
        :plain
      end

    try do
      Activity
      |> Activity.with_preloaded_object()
      |> Activity.restrict_deactivated_users()
      |> restrict_create()
      |> restrict_visible(user)
      |> restrict_searchable(user)
      |> query_with(index_type, search_query, search_function)
      |> maybe_restrict_local(user)
      |> maybe_restrict_author(author)
      |> maybe_restrict_blocked(user)
      |> Pagination.fetch_paginated(
        %{"offset" => offset, "limit" => limit, "skip_order" => index_type == :rum},
        :offset
      )
      |> maybe_fetch(user, search_query)
    rescue
      _ -> maybe_fetch([], user, search_query)
    end
  end

  def maybe_restrict_author(query, %User{} = author) do
    Activity.Queries.by_author(query, author)
  end

  def maybe_restrict_author(query, _), do: query

  def maybe_restrict_blocked(query, %User{} = user) do
    Activity.Queries.exclude_authors(query, User.blocked_users_ap_ids(user))
  end

  def maybe_restrict_blocked(query, _), do: query

  defp restrict_create(q) do
    from([a, o] in q, where: fragment("?->>'type' = 'Create'", a.data))
  end

  defp get_config(item) do
    Pleroma.Config.get([Pleroma.Activity.Search, item])
  end

  defp restrict_searchable(q, user) do
    cond do
      is_nil(user) && get_config(:allow_public) ->
        q

      get_config(:allow_all_visible) ->
        q

      is_nil(user) ->
        q |> where([a, o], false)

      get_config(:allow_public) && get_config(:allow_interacted) ->
        restrict_interacted(q, user, also_public: true)

      get_config(:allow_public) ->
        restrict_public(q, user)

      get_config(:allow_interacted) ->
        restrict_interacted(q, user, also_public: false)

      true ->
        q |> where([a, o], false)
    end
  end

  defp restrict_visible(q, user) when not is_nil(user) do
    intended_recipients = [
      Pleroma.Constants.as_public(),
      Pleroma.Web.ActivityPub.Utils.as_local_public(),
      user.ap_id
      | User.following(user)
    ]

    from([a, o] in q,
      where: fragment("? && ?", ^intended_recipients, a.recipients)
    )
  end

  defp restrict_visible(q, anon) do
    restrict_public(q, anon)
  end

  defp restrict_public(q, user) when not is_nil(user) do
    intended_recipients = [
      Pleroma.Constants.as_public(),
      Pleroma.Web.ActivityPub.Utils.as_local_public()
    ]

    from([a, o] in q,
      where: fragment("? && ?", ^intended_recipients, a.recipients)
    )
  end

  defp restrict_public(q, _user) do
    from([a, o] in q,
      where: ^Pleroma.Constants.as_public() in a.recipients
    )
  end

  @interact_activity_types [
    "Like",
    "EmojiReact",
    "EmojiReaction",
    "Announce"
  ]
  defp restrict_interacted(q, user, opts) when not is_nil(user) do
    intended_recipients =
      if opts[:also_public] do
        [
          Pleroma.Constants.as_public(),
          Pleroma.Web.ActivityPub.Utils.as_local_public(),
          user.ap_id
        ]
      else
        [user.ap_id]
      end

    q =
      Activity.with_preloaded_bookmark(q, user)
      |> join(
        :left_lateral,
        [a, o, b],
        interact in fragment(
          "SELECT * FROM activities AS interact WHERE interact.actor = ? AND (?->>'id') = associated_object_id(interact.data) AND ARRAY[interact.data->>'type'] && ? LIMIT 1",
          ^user.ap_id,
          o.data,
          ^@interact_activity_types
        )
      )
      |> join(
        :left_lateral,
        [a, o, b, react],
        reply in fragment(
          "SELECT * FROM objects AS reply WHERE reply.data->>'actor' = ? AND reply.data->>'inReplyTo' IS NOT NULL AND reply.data->>'inReplyTo' = ?->>'id' LIMIT 1",
          ^user.ap_id,
          o.data
        )
      )
      |> where(
        [a, o, b, react, reply],
        fragment("? && ?", ^intended_recipients, a.recipients) or
          not is_nil(b) or
          not is_nil(react) or
          not is_nil(reply)
      )

    q
  end

  defp query_with(q, :gin, search_query, :plain) do
    %{rows: [[tsc]]} =
      Ecto.Adapters.SQL.query!(
        Pleroma.Repo,
        "select current_setting('default_text_search_config')::regconfig::oid;"
      )

    from([a, o] in q,
      where:
        fragment(
          "to_tsvector(?::oid::regconfig, ?->>'content') @@ plainto_tsquery(?)",
          ^tsc,
          o.data,
          ^search_query
        )
    )
  end

  defp query_with(q, :gin, search_query, :websearch) do
    %{rows: [[tsc]]} =
      Ecto.Adapters.SQL.query!(
        Pleroma.Repo,
        "select current_setting('default_text_search_config')::regconfig::oid;"
      )

    from([a, o] in q,
      where:
        fragment(
          "to_tsvector(?::oid::regconfig, ?->>'content') @@ websearch_to_tsquery(?)",
          ^tsc,
          o.data,
          ^search_query
        )
    )
  end

  defp query_with(q, :rum, search_query, :plain) do
    from([a, o] in q,
      where:
        fragment(
          "? @@ plainto_tsquery(?)",
          o.fts_content,
          ^search_query
        ),
      order_by: [fragment("? <=> now()::date", o.inserted_at)]
    )
  end

  defp query_with(q, :rum, search_query, :websearch) do
    from([a, o] in q,
      where:
        fragment(
          "? @@ websearch_to_tsquery(?)",
          o.fts_content,
          ^search_query
        ),
      order_by: [fragment("? <=> now()::date", o.inserted_at)]
    )
  end

  defp maybe_restrict_local(q, user) do
    limit = Pleroma.Config.get([:instance, :limit_to_local_content], :unauthenticated)

    case {limit, user} do
      {:all, _} -> restrict_local(q)
      {:unauthenticated, %User{}} -> q
      {:unauthenticated, _} -> restrict_local(q)
      {false, _} -> q
    end
  end

  defp restrict_local(q), do: where(q, local: true)

  defp maybe_fetch(activities, user, search_query) do
    with true <- Regex.match?(~r/https?:/, search_query),
         {:ok, object} <- Fetcher.fetch_object_from_id(search_query),
         %Activity{} = activity <- Activity.get_create_by_object_ap_id(object.data["id"]),
         true <- Visibility.visible_for_user?(activity, user) do
      [activity | activities]
    else
      _ -> activities
    end
  end
end
