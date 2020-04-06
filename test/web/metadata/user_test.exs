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
<<<<<<< HEAD
    assert %{acct: username, username: username} = accounts
=======
    assert %{"acct" => username, "username" => username} = accounts
>>>>>>> 68b95896aeca086317f63533fdd54b7050c63231
  end

  test "it renders the relationships", %{"api/v1/accounts/relationships": relationships} do
    [
      %{
<<<<<<< HEAD
        blocked_by: false,
        blocking: false,
        showing_reblogs: true,
        subscribing: false
=======
        "blocked_by" => false,
        "blocking" => false,
        "showing_reblogs" => true,
        "subscribing" => false
>>>>>>> 68b95896aeca086317f63533fdd54b7050c63231
      }
    ] = relationships
  end
end
