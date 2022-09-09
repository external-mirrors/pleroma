# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.UploadedFileTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.UploadedFile

  import Pleroma.Factory

  describe "get_by_object_id/1" do
    test "doesn't exist" do
      object = insert(:note)

      assert UploadedFile.get_by_object_id(object.id) == nil
    end

    test "exists" do
      object = insert(:note)
      {:ok, file} = UploadedFile.create(%{object: object, path: "foo"})

      assert file.id == UploadedFile.get_by_object_id(object.id).id
    end
  end
end
