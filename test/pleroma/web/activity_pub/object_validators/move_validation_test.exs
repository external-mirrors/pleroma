# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.MoveValidationTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.ObjectValidator

  import Pleroma.Factory

  setup do
    %{ap_id: old_ap_id} = old_user = insert(:user)
    new_user = insert(:user, also_known_as: [old_ap_id])

    {:ok, move_data, _meta} = Builder.move(old_user, new_user)

    %{move_data: move_data, old_user: old_user, new_user: new_user}
  end

  test "it validates a move", %{move_data: move_data, old_user: old_user, new_user: new_user} do
    assert {:ok, move, _meta} = ObjectValidator.validate(move_data, [])

    assert move["type"] == "Move"
    assert move["actor"] == old_user.ap_id
    assert move["object"] == old_user.ap_id
    assert move["target"] == new_user.ap_id
    assert move["to"] == [old_user.follower_address]
  end

  test "it rejects moves to accounts that don't list the origin in alsoKnownAs", %{
    move_data: move_data,
    old_user: old_user
  } do
    stranger = insert(:user)
    move_data = Map.put(move_data, "target", stranger.ap_id)

    assert {:error, changeset} = ObjectValidator.validate(move_data, [])
    assert {"Target account must have the origin in `alsoKnownAs`", _} = changeset.errors[:target]

    assert old_user.ap_id not in stranger.also_known_as
  end

  test "it rejects moves to unknown accounts", %{move_data: move_data} do
    move_data = Map.put(move_data, "target", "https://example.com/users/nobody")

    assert {:error, _} = ObjectValidator.validate(move_data, [])
  end

  test "it rejects moves of other accounts", %{move_data: move_data} do
    other = insert(:user)
    move_data = Map.put(move_data, "actor", other.ap_id)

    assert {:error, _} = ObjectValidator.validate(move_data, [])
  end
end
