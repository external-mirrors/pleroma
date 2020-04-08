# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.User do
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.Preload.Providers.Provider

  @behaviour Provider

  @impl Provider
  def generate_terms(auth_user, %{user: user}) do
    %{}
    |> build_accounts_tag(auth_user, user)
    |> build_relationships_tag(auth_user, user)
  end

  def generate_terms(_auth_user, _), do: %{}

  def build_accounts_tag(acc, nil, _user) do
    Map.put(acc, :"api/v1/accounts", %{})
  end

  def build_accounts_tag(acc, auth_user, user) do
    account_data = AccountView.render("show.json", %{user: user, for: auth_user})
    Map.put(acc, :"api/v1/accounts", account_data)
  end

  def build_relationships_tag(acc, auth_user, user) do
    relationship_data =
      AccountView.render("relationships.json", %{user: auth_user, targets: [user]})

    Map.put(acc, :"api/v1/accounts/relationships", relationship_data)
  end
end
