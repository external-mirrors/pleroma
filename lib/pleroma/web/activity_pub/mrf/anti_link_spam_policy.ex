# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.AntiLinkSpamPolicy do
  alias Pleroma.User

  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  @impl true
  def history_awareness, do: :auto

  # has the user successfully posted before?
  defp old_user?(%User{} = u) do
    u.note_count > 0 || u.follower_count > 0
  end

  # does the post contain links?
  defp contains_links?(%{"content" => content} = _object) do
    content
    |> Floki.parse_fragment!()
    |> Floki.filter_out("a.mention,a.hashtag,a[rel~=\"tag\"],a.zrl")
    |> Floki.attribute("a", "href")
    |> length() > 0
  end

  defp contains_links?(_), do: false

  @impl true
  def filter(%{"type" => "Create", "actor" => actor, "object" => object} = activity) do
    with {:ok, %User{local: false} = u} <- User.get_or_fetch_by_ap_id(actor),
         {:contains_links, true} <- {:contains_links, contains_links?(object)},
         {:old_user, true} <- {:old_user, old_user?(u)} do
      {:pass, activity}
    else
      {:ok, %User{local: true}} ->
        {:pass, activity}

      {:contains_links, false} ->
        {:pass, activity}

      {:old_user, false} ->
        reason = "User has no posts nor followers"
        {:reject, %{activity: activity, reason: reason}}

      {:error, _} ->
        reason = "Failed to get or fetch user by ap_id"
        {:reject, %{activity: activity, reason: reason}}

      e ->
        reason = "Unhandled error"
        {:reject, %{activity: activity, reason: reason, error: e}}
    end
  end

  # in all other cases, pass through
  def filter(activity) do
    {:pass, activity}
  end

  @impl true
  def describe, do: {:ok, %{}}
end
