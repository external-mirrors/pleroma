# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ActorStatusViewTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Object
  alias Pleroma.Web.PleromaAPI.ActorStatusView

  import Pleroma.Factory

  test "successfully renders a Create activity with Actor Status" do
    activity = insert(:actor_status_activity)
    object = Object.normalize(activity, fetch: false)

    status = ActorStatusView.render("show.json", activity: activity)

    assert status.actor_status_content == object.data["content"]
  end
end
