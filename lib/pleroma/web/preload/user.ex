# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.User do
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.Preload.Providers.Provider

  @behaviour Provider
  @account_url :"/api/v1/accounts"

  @impl Provider
  def generate_terms(auth_user, %{user: user}) do
    %{}
    |> build_accounts_tag(auth_user, user)
  end

  def build_accounts_tag(acc, _auth_user, user) do
    account_data = AccountView.render("show.json", %{user: user, for: user})
    Map.put(acc, @account_url, account_data)
  end
end
