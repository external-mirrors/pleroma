# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Activity.SearchTest do
  alias Pleroma.Activity.Search
  alias Pleroma.Web.CommonAPI
  import Pleroma.Factory

  use Pleroma.DataCase, async: true

  test "it finds something" do
    user = insert(:user)
    {:ok, post} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})

    [result] = Search.search(nil, "wednesday")

    assert result.id == post.id
  end

  describe "when allowing searching everything visible" do
    setup do
      clear_config([Pleroma.Activity.Search, :allow_all_visible], true)
      user = insert(:user)
      searcher = insert(:user)

      {:ok, public} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})
      {:ok, private} = CommonAPI.post(user, %{status: "wednesday private", visibility: "private"})

      {:ok, private_mentioned} =
        CommonAPI.post(user, %{
          status: "wednesday private @#{searcher.nickname}",
          visibility: "private"
        })

      %{
        user: user,
        searcher: searcher,
        public: public,
        private: private,
        private_mentioned: private_mentioned
      }
    end

    test "found all visible statuses", %{
      searcher: searcher,
      public: public,
      private_mentioned: private_mentioned
    } do
      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert public.id in ids
      assert private_mentioned.id in ids
    end

    test "found private statuses", %{searcher: searcher, user: user, private: private} do
      {:ok, _, _, _} = CommonAPI.follow(searcher, user)

      results = Search.search(searcher, "wednesday")
      assert [_, _, _] = results

      ids = Enum.map(results, & &1.id)
      assert private.id in ids
    end
  end

  describe "when allowing searching everything public" do
    setup do
      clear_config([Pleroma.Activity.Search, :allow_all_visible], false)
      clear_config([Pleroma.Activity.Search, :allow_interacted], false)
      clear_config([Pleroma.Activity.Search, :allow_public], true)
      user = insert(:user)
      searcher = insert(:user)

      {:ok, public} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})

      {:ok, unlisted} =
        CommonAPI.post(user, %{status: "it's wednesday my dudes", visibility: "unlisted"})

      {:ok, _private} =
        CommonAPI.post(user, %{status: "wednesday private", visibility: "private"})

      {:ok, _private_mentioned} =
        CommonAPI.post(user, %{
          status: "wednesday private @#{searcher.nickname}",
          visibility: "private"
        })

      %{
        user: user,
        searcher: searcher,
        public: public,
        unlisted: unlisted
      }
    end

    test "found all visible statuses", %{
      user: user,
      searcher: searcher,
      public: public,
      unlisted: unlisted
    } do
      {:ok, _, _, _} = CommonAPI.follow(searcher, user)

      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert public.id in ids
      assert unlisted.id in ids
    end
  end

  describe "when allowing searching everything interacted" do
    setup do
      clear_config([Pleroma.Activity.Search, :allow_all_visible], false)
      clear_config([Pleroma.Activity.Search, :allow_interacted], true)
      clear_config([Pleroma.Activity.Search, :allow_public], false)
      user = insert(:user)
      searcher = insert(:user)

      {:ok, public} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})

      {:ok, unlisted} =
        CommonAPI.post(user, %{status: "it's wednesday my dudes", visibility: "unlisted"})

      {:ok, private} = CommonAPI.post(user, %{status: "wednesday private", visibility: "private"})

      {:ok, private_mentioned} =
        CommonAPI.post(user, %{
          status: "wednesday private @#{searcher.nickname}",
          visibility: "private"
        })

      %{
        user: user,
        searcher: searcher,
        public: public,
        unlisted: unlisted,
        private: private,
        private_mentioned: private_mentioned
      }
    end

    test "found mentioned statuses", %{searcher: searcher, private_mentioned: private_mentioned} do
      results = Search.search(searcher, "wednesday")
      assert [_] = results

      ids = Enum.map(results, & &1.id)
      assert private_mentioned.id in ids
    end

    test "found bookmarked statuses", %{searcher: searcher, unlisted: unlisted} do
      Pleroma.Bookmark.create(searcher.id, unlisted.id)

      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert unlisted.id in ids
    end

    test "found liked statuses", %{searcher: searcher, unlisted: unlisted} do
      {:ok, _} = CommonAPI.favorite(searcher, unlisted.id)

      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert unlisted.id in ids
    end

    test "found repeated statuses", %{searcher: searcher, unlisted: unlisted} do
      {:ok, _} = CommonAPI.repeat(unlisted.id, searcher)

      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert unlisted.id in ids
    end

    test "found reacted statuses", %{searcher: searcher, unlisted: unlisted} do
      {:ok, _} = CommonAPI.react_with_emoji(unlisted.id, searcher, "🐈‍⬛")

      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert unlisted.id in ids
    end

    test "found no duplicated statuses", %{
      searcher: searcher,
      unlisted: unlisted,
      private_mentioned: private_mentioned
    } do
      Pleroma.Bookmark.create(searcher.id, unlisted.id)
      Pleroma.Bookmark.create(searcher.id, private_mentioned.id)
      {:ok, _} = CommonAPI.favorite(searcher, unlisted.id)
      {:ok, _} = CommonAPI.repeat(unlisted.id, searcher)
      {:ok, _} = CommonAPI.react_with_emoji(unlisted.id, searcher, "🐈‍⬛")

      results = Search.search(searcher, "wednesday")
      assert [_, _] = results

      ids = Enum.map(results, & &1.id)
      assert unlisted.id in ids
    end
  end

  test "it finds local-only posts for authenticated users" do
    user = insert(:user)
    reader = insert(:user)
    {:ok, post} = CommonAPI.post(user, %{status: "it's wednesday my dudes", visibility: "local"})

    [result] = Search.search(reader, "wednesday")

    assert result.id == post.id
  end

  test "it does not find local-only posts for anonymous users" do
    user = insert(:user)
    {:ok, _post} = CommonAPI.post(user, %{status: "it's wednesday my dudes", visibility: "local"})

    assert [] = Search.search(nil, "wednesday")
  end

  test "using plainto_tsquery on postgres < 11" do
    old_version = :persistent_term.get({Pleroma.Repo, :postgres_version})
    :persistent_term.put({Pleroma.Repo, :postgres_version}, 10.0)
    on_exit(fn -> :persistent_term.put({Pleroma.Repo, :postgres_version}, old_version) end)

    user = insert(:user)
    {:ok, post} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})
    {:ok, _post2} = CommonAPI.post(user, %{status: "it's wednesday my bros"})

    # plainto doesn't understand complex queries
    assert [result] = Search.search(nil, "wednesday -dudes")

    assert result.id == post.id
  end

  test "using websearch_to_tsquery" do
    user = insert(:user)
    {:ok, _post} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})
    {:ok, other_post} = CommonAPI.post(user, %{status: "it's wednesday my bros"})

    assert [result] = Search.search(nil, "wednesday -dudes")

    assert result.id == other_post.id
  end
end
