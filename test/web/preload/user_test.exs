# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.UserTest do
  use Pleroma.DataCase
  import Pleroma.Factory
  alias Pleroma.Web.Preload.Providers.User

  describe "browsing user is not logged in" do
    setup do
      user = insert(:user)

      {:ok, User.generate_terms(nil, %{user: user})}
    end

    test "account is rendered", %{"/api/v1/accounts": accounts} do
      assert %{acct: user, username: user} = accounts
    end
  end
end
