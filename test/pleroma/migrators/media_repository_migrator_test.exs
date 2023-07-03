# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Migrators.MediaRepositoryMigratorTest do
  use Pleroma.DataCase

  alias Pleroma.Migrators.MediaRepositoryMigrator
  alias Pleroma.Repo

  import Pleroma.Factory

  describe "query/0" do
    test "it returns Documents and Images" do
      document = insert(:attachment)
      image = insert(:attachment, data: %{"type" => "Image"})
      _note = insert(:note)

      result = MediaRepositoryMigrator.query() |> Repo.all()
      assert [_, _] = result
      assert image in result
      assert document in result
    end
  end
end
