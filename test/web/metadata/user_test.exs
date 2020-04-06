# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.UserTest do
  use Pleroma.DataCase
  import Pleroma.Factory
  alias Pleroma.Web.Preload.Providers.User

  setup do
    user = insert(:user)

    {:ok, User.generate_terms(%{user: user})}
  end

  test "it renders the accounts", %{"api/v1/accounts": accounts} do
    assert %{acct: username, username: username} = accounts
  end

  test "it renders the relationships", %{"api/v1/accounts/relationships": relationships} do
    [
      %{
        blocked_by: false,
        blocking: false,
        showing_reblogs: true,
        subscribing: false
      }
    ] = relationships
  end
end
