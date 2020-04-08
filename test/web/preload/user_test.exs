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

    test "accounts are not rendered", %{"api/v1/accounts": accounts} do
      assert %{} == accounts
    end

    test "it does not render relationships", %{"api/v1/accounts/relationships": relationships} do
      assert [%{}] == relationships
    end
  end

  describe "browsing user is not the same as the browsed user" do
    setup do
      user = insert(:user)
      browser_user = insert(:user)

      {:ok, %{user: user, browser_user: browser_user}}
    end

    test "account is rendered", %{user: user, browser_user: browser_user} do
      %{"api/v1/accounts": accounts} = User.generate_terms(browser_user, %{user: user})

      assert %{acct: user, username: user} = accounts
    end

    test "does render relationships", %{user: user, browser_user: browser_user} do
      %{"api/v1/accounts/relationships": relationships} =
        User.generate_terms(browser_user, %{user: user})

      refute %{} == relationships
    end

    test "does render relationships for the user", %{user: user, browser_user: browser_user} do
      %{"api/v1/accounts/relationships": relationships} =
        User.generate_terms(browser_user, %{user: user})

      assert [
               %{
                 followed_by: false
               }
             ] = relationships

      Pleroma.User.follow(user, browser_user)

      %{"api/v1/accounts/relationships": relationships} =
        User.generate_terms(browser_user, %{user: user})

      assert [
               %{
                 followed_by: true
               }
             ] = relationships
    end
  end

  describe "browsing user is the same as the browsed user" do
    setup do
      user = insert(:user)

      {:ok, User.generate_terms(user, %{user: user})}
    end

    test "account is rendered", %{"api/v1/accounts": accounts} do
      assert %{acct: user, username: user} = accounts
    end

    test "it does render relationships", %{"api/v1/accounts/relationships": [relationships]} do
      refute %{} == relationships
    end
  end
end
