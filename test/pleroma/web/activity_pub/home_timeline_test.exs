# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.HomeTimelineTest do
  use Pleroma.DataCase

  import Mock
  import Pleroma.Factory

  alias Pleroma.Pagination
  alias Pleroma.Web.ActivityPub.ActivityPub

  defp setting(name), do: Repo.query!("SELECT current_setting($1)", [name]).rows |> hd() |> hd()

  describe "exact home timeline queries" do
    test "uses exact GIN only for home selection and restores the caller's setting" do
      user = insert(:user)
      Repo.query!("SET LOCAL gin_fuzzy_search_limit = 321")

      with_mock Pagination, [:passthrough],
        fetch_paginated: fn _query, _opts, :keyset, nil ->
          send(self(), {:gin_limit, setting("gin_fuzzy_search_limit")})
          []
        end do
        assert ActivityPub.fetch_home_activities([user.ap_id], %{user: user}) == []
        assert_received {:gin_limit, "0"}
        assert setting("gin_fuzzy_search_limit") == "321"

        assert ActivityPub.fetch_activities([user.ap_id], %{user: user}) == []
        assert_received {:gin_limit, "321"}
      end
    end

    test "restores settings inside an existing transaction" do
      user = insert(:user)

      assert {:ok, :ok} =
               Repo.transaction(fn ->
                 Repo.query!("SET LOCAL gin_fuzzy_search_limit = 123")
                 ActivityPub.fetch_home_activities([user.ap_id], %{user: user})
                 assert setting("gin_fuzzy_search_limit") == "123"
                 :ok
               end)
    end

    test "restores the caller's transaction after a database error" do
      user = insert(:user)
      Repo.query!("SET LOCAL gin_fuzzy_search_limit = 123")

      with_mock Pagination, [:passthrough],
        fetch_paginated: fn _query, _opts, :keyset, nil ->
          Repo.query!("SELECT 1 / 0")
        end do
        assert_raise Postgrex.Error, fn ->
          ActivityPub.fetch_home_activities([user.ap_id], %{user: user})
        end
      end

      assert setting("gin_fuzzy_search_limit") == "123"
      assert Repo.query!("SELECT 1").rows == [[1]]
    end
  end
end
