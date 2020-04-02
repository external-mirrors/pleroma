# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Metadata.Providers.User do
  alias Pleroma.User
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.Metadata.Providers.Provider

  @behaviour Provider

  @impl Provider
  def build_tags(params) do
    []
    |> build_accounts_tag(params)
    |> build_relationships_tag(params)
  end

  def build_accounts_tag(acc \\ [], %{user: user}) do
    "show.json"
    |> AccountView.render(%{user: user, for: user})
    |> Jason.encode!()
    |> check_for_empty()
    |> case do
      "" ->
        acc

      safe_data ->
        [make_tag("user:account", safe_data) | acc]
    end
  end

  def build_relationships_tag(acc \\ [], %{user: %{id: user_id} = user}) do
    targets = User.get_all_by_ids(List.wrap(user_id))

    "relationships.json"
    |> AccountView.render(%{user: user, targets: targets})
    |> Jason.encode!()
    |> check_for_empty()
    |> case do
      "" ->
        acc

      safe_data ->
        [make_tag("user:relationships", safe_data) | acc]
    end
  end

  defp check_for_empty(data) do
    if data != "" and data != "\u200B" do
      data
    else
      ""
    end
  end

  defp make_tag(key, data) do
    {:meta, [property: key, content: data], []}
  end
end
