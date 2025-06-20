# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.StreamerTestAsync do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Conversation.Participation
  alias Pleroma.List
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.Streamer

  @moduletag needs_streamer: true, capture_log: true

  setup do
    clear_config([:instance, :skip_thread_containment])
    # Force async streaming for these tests that have complex DB operations
    clear_config([Pleroma.Web.Streamer, :sync_streaming], false)
  end

  describe "lists" do
    setup do: oauth_access(["read"])

    test "it doesn't send unwanted DMs to list", %{user: user_a, token: user_a_token} do
      user_b = insert(:user)
      user_c = insert(:user)

      {:ok, user_a, user_b} = User.follow(user_a, user_b)

      {:ok, list} = List.create("Test", user_a)
      {:ok, list} = List.follow(list, user_b)

      Streamer.get_topic_and_add_socket("list", user_a, user_a_token, %{"list" => list.id})

      {:ok, _activity} =
        CommonAPI.post(user_b, %{
          status: "@#{user_c.nickname} Test",
          visibility: "direct"
        })

      refute_receive _
    end

    test "it doesn't send unwanted private posts to list", %{user: user_a, token: user_a_token} do
      user_b = insert(:user)

      {:ok, list} = List.create("Test", user_a)
      {:ok, list} = List.follow(list, user_b)

      Streamer.get_topic_and_add_socket("list", user_a, user_a_token, %{"list" => list.id})

      {:ok, _activity} =
        CommonAPI.post(user_b, %{
          status: "Test",
          visibility: "private"
        })

      refute_receive _
    end

    test "it sends wanted private posts to list", %{user: user_a, token: user_a_token} do
      user_b = insert(:user)

      {:ok, user_a, user_b} = User.follow(user_a, user_b)

      {:ok, list} = List.create("Test", user_a)
      {:ok, list} = List.follow(list, user_b)

      Streamer.get_topic_and_add_socket("list", user_a, user_a_token, %{"list" => list.id})

      {:ok, activity} =
        CommonAPI.post(user_b, %{
          status: "Test",
          visibility: "private"
        })

      assert_receive {:render_with_user, _, _, ^activity, _}
      refute Streamer.filtered_by_user?(user_a, activity)
    end
  end

  describe "direct streams" do
    setup do: oauth_access(["read"])

    test "it sends conversation update to the 'direct' stream", %{user: user, token: oauth_token} do
      another_user = insert(:user)

      Streamer.get_topic_and_add_socket("direct", user, oauth_token)

      {:ok, _create_activity} =
        CommonAPI.post(another_user, %{
          status: "hey @#{user.nickname}",
          visibility: "direct"
        })

      assert_receive {:text, received_event}

      assert %{"event" => "conversation", "payload" => received_payload} =
               Jason.decode!(received_event)

      assert %{"last_status" => last_status} = Jason.decode!(received_payload)
      [participation] = Participation.for_user(user)
      assert last_status["pleroma"]["direct_conversation_id"] == participation.id
    end

    test "it doesn't send conversation update to the 'direct' stream when the last message in the conversation is deleted",
         %{user: user, token: oauth_token} do
      another_user = insert(:user)

      Streamer.get_topic_and_add_socket("direct", user, oauth_token)

      {:ok, create_activity} =
        CommonAPI.post(another_user, %{
          status: "hi @#{user.nickname}",
          visibility: "direct"
        })

      create_activity_id = create_activity.id
      assert_receive {:render_with_user, _, _, ^create_activity, _}
      assert_receive {:text, received_conversation1}
      assert %{"event" => "conversation", "payload" => _} = Jason.decode!(received_conversation1)

      {:ok, _} = CommonAPI.delete(create_activity_id, another_user)

      assert_receive {:text, received_event}

      assert %{"event" => "delete", "payload" => ^create_activity_id} =
               Jason.decode!(received_event)

      refute_receive _
    end

    @tag :erratic
    test "it sends conversation update to the 'direct' stream when a message is deleted", %{
      user: user,
      token: oauth_token
    } do
      another_user = insert(:user)
      Streamer.get_topic_and_add_socket("direct", user, oauth_token)

      {:ok, create_activity} =
        CommonAPI.post(another_user, %{
          status: "hi @#{user.nickname}",
          visibility: "direct"
        })

      {:ok, create_activity2} =
        CommonAPI.post(another_user, %{
          status: "hi @#{user.nickname} 2",
          in_reply_to_status_id: create_activity.id,
          visibility: "direct"
        })

      assert_receive {:render_with_user, _, _, ^create_activity, _}
      assert_receive {:render_with_user, _, _, ^create_activity2, _}
      assert_receive {:text, received_conversation1}
      assert %{"event" => "conversation", "payload" => _} = Jason.decode!(received_conversation1)
      assert_receive {:text, received_conversation1}
      assert %{"event" => "conversation", "payload" => _} = Jason.decode!(received_conversation1)

      {:ok, _} = CommonAPI.delete(create_activity2.id, another_user)

      assert_receive {:text, received_event}
      assert %{"event" => "delete", "payload" => _} = Jason.decode!(received_event)

      assert_receive {:text, received_event}

      assert %{"event" => "conversation", "payload" => received_payload} =
               Jason.decode!(received_event)

      assert %{"last_status" => last_status} = Jason.decode!(received_payload)
      assert last_status["id"] == to_string(create_activity.id)
    end
  end
end
