# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.AttachmentRelationshipTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.AttachmentRelationship

  import Pleroma.Factory

  describe "exists?/2" do
    test "behaves" do
      object = insert(:note)
      attachment = insert(:note)

      refute AttachmentRelationship.exists?(object, attachment)
      AttachmentRelationship.create(object, attachment)
      assert AttachmentRelationship.exists?(object, attachment)
    end
  end

  describe "create_many/2" do
    test "creates many relationships" do
      object = insert(:note)
      attachments =
        [1..5]
        |> Enum.map(fn _ -> insert(:note) end)

      AttachmentRelationship.create_many(object, attachments)

      attachments
      |> Enum.map(fn attachment ->
        assert AttachmentRelationship.exists?(object, attachment)
      end)
    end
  end

  describe "attachments_of/1" do
    test "gets attachments" do
      object = insert(:note)
      attachments =
        [1..5]
        |> Enum.map(fn _ -> insert(:note) end)

      AttachmentRelationship.create_many(object, attachments)

      assert attachments == AttachmentRelationship.attachments_of(object)
    end
  end

  describe "references_of/1" do
    test "gets references" do
      object = insert(:note)
      object2 = insert(:note)
      attachment = insert(:note)

      AttachmentRelationship.create(object, attachment)
      AttachmentRelationship.create(object2, attachment)

      refs = AttachmentRelationship.references_of(attachment)

      assert [_, _] = refs
    end
  end
end
