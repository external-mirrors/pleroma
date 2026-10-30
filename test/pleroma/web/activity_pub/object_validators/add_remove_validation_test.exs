# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.AddRemoveValidationTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  require Pleroma.Constants

  defp collection_activity(type, user, object_id) do
    %{
      "id" => "#{user.ap_id}/activities/#{Ecto.UUID.generate()}",
      "type" => type,
      "actor" => user.ap_id,
      "object" => object_id,
      "target" => user.featured_address,
      "to" => [Pleroma.Constants.as_public()],
      "cc" => [user.follower_address]
    }
  end

  setup do
    {:ok, post} = CommonAPI.post(insert(:user), %{status: "not yours"})
    %{object_id: post.data["object"]}
  end

  test "a remote Add of another actor's object is rejected", %{object_id: object_id} do
    remote =
      insert(:user,
        local: false,
        ap_id: "https://remote.example/users/pinner",
        featured_address: "https://remote.example/users/pinner/collections/featured"
      )

    add = collection_activity("Add", remote, object_id)
    assert {:error, %Ecto.Changeset{}} = ObjectValidator.validate(add, local: false)
  end

  test "a Remove of another actor's object is accepted, so bad pins can go away",
       %{object_id: object_id} do
    user = insert(:user)
    remove = collection_activity("Remove", user, object_id)
    assert {:ok, _, _} = ObjectValidator.validate(remove, local: true)
  end
end
