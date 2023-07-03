# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Migrators.MediaRepositoryMigratorTest do
  use Pleroma.DataCase

  alias Pleroma.Migrators.MediaRepositoryMigrator
  alias Pleroma.Repo
  alias Pleroma.UploadedFile

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

    test "it does not return objects with a corresponding UploadedFile" do
      document = insert(:attachment)
      {:ok, _uploaded_file} = UploadedFile.create(%{object: document, path: "some/path"})

      result = MediaRepositoryMigrator.query() |> Repo.all()
      assert [] == result
    end
  end
end
