# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.Timelines do
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.MastodonAPI.StatusView
  alias Pleroma.Web.Preload.Providers.Provider

  @behaviour Provider
  @public_url :"/api/v1/timelines/public"
  @home_url :"/api/v1/timelines/home"

  @impl Provider
  def generate_terms(auth_user, %{user: user}) do
    %{}
    |> build_public_tag(auth_user, user)
    |> build_home_tag(auth_user, user)
  end

  def generate_terms(auth_user, _), do: generate_terms(auth_user, %{user: nil})

  def build_public_tag(acc, _auth_user, nil), do: acc

  def build_public_tag(acc, nil, user) do
    if Pleroma.Config.get([:restrict_unauthenticated, :timelines, :federated], true) do
      acc
    else
      Map.put(acc, @public_url, public_timeline(user))
    end
  end

  def build_public_tag(acc, _auth_user, user) do
    Map.put(acc, @public_url, public_timeline(user))
  end

  def build_home_tag(acc, auth_user, user) when is_nil(auth_user) or is_nil(user), do: acc

  def build_home_tag(acc, auth_user, user) do
    params = create_timeline_params(user)

    recipients = [user.ap_id | User.following(user)]

    activities =
      recipients
      |> ActivityPub.fetch_activities(params)
      |> Enum.reverse()

    home_timeline =
      StatusView.render("index.json", activities: activities, for: auth_user, as: :activity)

    Map.put(acc, @home_url, home_timeline)
  end

  defp public_timeline(user) do
    activities =
      create_timeline_params(user)
      |> Map.put("local_only", false)
      |> ActivityPub.fetch_public_activities()

    StatusView.render("index.json", activities: activities, for: user, as: :activity)
  end

  defp create_timeline_params(user) do
    %{}
    |> Map.put("type", ["Create", "Announce"])
    |> Map.put("blocking_user", user)
    |> Map.put("muting_user", user)
    |> Map.put("user", user)
  end
end
