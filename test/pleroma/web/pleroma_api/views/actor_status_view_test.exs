# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ActorStatusViewTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Object
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.PleromaAPI.ActorStatusView

  import Pleroma.Factory

  test "successfully renders a Create activity with Actor Status" do
    activity = insert(:actor_status_activity)
    object = Object.normalize(activity, fetch: false)

    status = ActorStatusView.render("show.json", activity: activity)

    assert status.actor_status.content == object.data["content"]
  end

  test "successfully renders a Delete activity for Actor Status" do
    user = insert(:user)
    {:ok, _create_activity} = CommonAPI.actor_status(user, %{content: "Delet this!"})
    {:ok, delete_activity} = CommonAPI.delete_actor_status(user)

    status = ActorStatusView.render("show.json", activity: delete_activity)

    assert status.actor_status.content == ""
  end
end
