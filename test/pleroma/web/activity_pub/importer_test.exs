# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ImporterTest do
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Web.ActivityPub.Importer
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.CommonAPI

  require Pleroma.Constants

  import Pleroma.Factory

  describe "import_one/2" do
    test "it imports an activity" do
      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "mew"})

      {:ok, activity_for_import} = Transmogrifier.prepare_outgoing(activity.data)

      importing_user = insert(:user)
      assert {:ok, imported_activity} = Importer.import_one(activity_for_import, importing_user)
      imported_activity = Activity.normalize(imported_activity)

      assert imported_activity.id != activity.id
      assert imported_activity.actor == importing_user.ap_id
      assert imported_activity.object.data["actor"] == importing_user.ap_id
      assert imported_activity.object.data["content"] == activity.object.data["content"]
      assert imported_activity.object.data["published"] == activity.object.data["published"]
    end

    test "it strips all mentions" do
      user = insert(:user)
      user2 = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "mew @#{user2.nickname}"})
      assert user2.ap_id in activity.recipients

      {:ok, activity_for_import} = Transmogrifier.prepare_outgoing(activity.data)

      importing_user = insert(:user)
      assert {:ok, imported_activity} = Importer.import_one(activity_for_import, importing_user)
      imported_activity = Activity.normalize(imported_activity)

      assert [importing_user.ap_id] == imported_activity.recipients
      assert [] == imported_activity.object.data["to"]
      assert [importing_user.ap_id] == imported_activity.object.data["cc"]
    end

    test "it keeps inReplyTo and context" do
      user = insert(:user)
      user2 = insert(:user)
      {:ok, replied_to_activity} = CommonAPI.post(user2, %{status: "mew"})
      {:ok, activity} = CommonAPI.post(user, %{status: "mew @#{user2.nickname}", in_reply_to_id: replied_to_activity})
      assert user2.ap_id in activity.recipients

      {:ok, activity_for_import} = Transmogrifier.prepare_outgoing(activity.data)

      importing_user = insert(:user)
      assert {:ok, imported_activity} = Importer.import_one(activity_for_import, importing_user)
      imported_activity = Activity.normalize(imported_activity)

      assert [importing_user.ap_id] == imported_activity.recipients
      assert imported_activity.object.data["context"] == activity.object.data["context"]
      assert imported_activity.object.data["inReplyTo"] == activity.object.data["inReplyTo"]
      assert imported_activity.data["context"] == activity.data["context"]
    end
  end
end
