# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.User do
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.Preload.Providers.Provider

  @behaviour Provider

  @impl Provider
  def generate_terms(params \\ %{})

  def generate_terms(%{user: nil}), do: %{}

  def generate_terms(%{user: user}) do
    %{}
    |> build_accounts_tag(user)
    |> build_relationships_tag(user)
  end

  def generate_terms(_), do: %{}

  def build_accounts_tag(acc, user) do
    account_data = AccountView.render("show.json", %{user: user, for: user})
    Map.put(acc, :"api/v1/accounts", account_data)
  end

  def build_relationships_tag(acc, user) do
    relationship_data = AccountView.render("relationships.json", %{user: user, targets: [user]})
    Map.put(acc, :"api/v1/accounts/relationships", relationship_data)
  end
end
