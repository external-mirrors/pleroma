# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Search.QdrantSearchTest do
  use Pleroma.DataCase, async: true
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory

  alias Pleroma.UnstubbedConfigMock, as: Config
  alias Pleroma.Search.QdrantSearch

  setup do
  end

  describe "Qdrant search" do
    test "indexes a public post on creation" do
      user = insert(:user)

      Tesla.Mock.mock(fn %{
                           method: :put,
                           url: "http://127.0.0.1:6333/collections/posts",
                           body: body
                         } ->
        assert [point] = body["points"]
        assert point["vector"] == []
      end)
    end
  end
end
