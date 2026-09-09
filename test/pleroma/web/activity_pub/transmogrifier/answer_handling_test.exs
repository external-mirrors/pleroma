# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.AnswerHandlingTest do
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  test "incoming, rewrites Note to Answer and increments vote counters" do
    user = insert(:user)

    {:ok, activity} =
      CommonAPI.post(user, %{
        status: "suya...",
        poll: %{options: ["suya", "suya.", "suya.."], expires_in: 10}
      })

    object = Object.normalize(activity, fetch: false)
    assert object.data["repliesCount"] == nil

    data =
      File.read!("test/fixtures/mastodon-vote.json")
      |> Jason.decode!()
      |> Kernel.put_in(["to"], user.ap_id)
      |> Kernel.put_in(["object", "inReplyTo"], object.data["id"])
      |> Kernel.put_in(["object", "to"], user.ap_id)

    {:ok, %Activity{local: false} = activity} = Transmogrifier.handle_incoming(data)
    answer_object = Object.normalize(activity, fetch: false)
    assert answer_object.data["type"] == "Answer"
    assert answer_object.data["inReplyTo"] == object.data["id"]

    new_object = Object.get_by_ap_id(object.data["id"])
    assert new_object.data["repliesCount"] == nil

    assert Enum.any?(
             new_object.data["oneOf"],
             fn
               %{"name" => "suya..", "replies" => %{"totalItems" => 1}} -> true
               _ -> false
             end
           )
  end

  for {multiple, options_key} <- [{false, "oneOf"}, {true, "anyOf"}] do
    test "incoming vote preserves existing reply and quote counts for #{options_key} polls" do
      user = insert(:user)

      {:ok, poll} =
        CommonAPI.post(user, %{
          status: "suya...",
          poll: %{
            options: ["suya", "suya.", "suya.."],
            expires_in: 600,
            multiple: unquote(multiple)
          }
        })

      ap_id = poll.object.data["id"]
      Object.get_cached_by_ap_id(ap_id)

      {:ok, _reply} =
        CommonAPI.post(user, %{status: "a real reply", in_reply_to_status_id: poll.id})

      {:ok, _quote} = CommonAPI.post(user, %{status: "a quote", quoted_status_id: poll.id})
      assert %{"repliesCount" => 1, "quotesCount" => 1} = Object.get_by_ap_id(ap_id).data

      data =
        File.read!("test/fixtures/mastodon-vote.json")
        |> Jason.decode!()
        |> put_in(["to"], user.ap_id)
        |> put_in(["object", "to"], user.ap_id)
        |> put_in(["object", "inReplyTo"], ap_id)

      {:ok, %Activity{local: false}} = Transmogrifier.handle_incoming(data)
      updated = Object.get_by_ap_id(ap_id)

      assert %{"repliesCount" => 1, "quotesCount" => 1, "votersCount" => 1} = updated.data
      assert data["actor"] in updated.data["voters"]

      option = Enum.find(updated.data[unquote(options_key)], &(&1["name"] == "suya.."))
      assert option["replies"]["totalItems"] == 1

      assert Object.get_cached_by_ap_id(ap_id) == updated
    end
  end

  for public_field <- ["to", "cc"] do
    test "deleting a vote with Public in #{public_field} preserves the poll's reply count" do
      user = insert(:user)

      {:ok, poll} =
        CommonAPI.post(user, %{
          status: "suya...",
          poll: %{options: ["suya", "suya.", "suya.."], expires_in: 600}
        })

      recipients =
        %{"to" => [user.ap_id], "cc" => []}
        |> Map.put(unquote(public_field), ["https://www.w3.org/ns/activitystreams#Public"])

      data =
        File.read!("test/fixtures/mastodon-vote.json")
        |> Jason.decode!()
        |> Map.merge(recipients)
        |> update_in(["object"], &Map.merge(&1, recipients))
        |> put_in(["object", "inReplyTo"], poll.object.data["id"])

      {:ok, %Activity{local: false} = answer} = Transmogrifier.handle_incoming(data)
      assert Object.normalize(answer).data["type"] == "Answer"
      assert Pleroma.Web.ActivityPub.Visibility.public?(Object.normalize(answer))

      {:ok, reply} =
        CommonAPI.post(user, %{status: "a real reply", in_reply_to_status_id: poll.id})

      assert Object.get_by_ap_id(poll.object.data["id"]).data["repliesCount"] == 1

      {:ok, _delete} =
        Transmogrifier.handle_incoming(%{
          "id" => answer.data["id"] <> "/delete",
          "type" => "Delete",
          "actor" => answer.actor,
          "object" => answer.data["object"]
        })

      refute Activity.get_by_id(answer.id)
      assert Object.get_by_ap_id(poll.object.data["id"]).data["repliesCount"] == 1

      {:ok, _delete} = CommonAPI.delete(reply.id, user)
      assert Object.get_by_ap_id(poll.object.data["id"]).data["repliesCount"] == 0
    end
  end

  test "outgoing, rewrites Answer to Note" do
    user = insert(:user)

    {:ok, poll_activity} =
      CommonAPI.post(user, %{
        status: "suya...",
        poll: %{options: ["suya", "suya.", "suya.."], expires_in: 10}
      })

    poll_object = Object.normalize(poll_activity, fetch: false)
    # TODO: Replace with CommonAPI vote creation when implemented
    data =
      File.read!("test/fixtures/mastodon-vote.json")
      |> Jason.decode!()
      |> Kernel.put_in(["to"], user.ap_id)
      |> Kernel.put_in(["object", "inReplyTo"], poll_object.data["id"])
      |> Kernel.put_in(["object", "to"], user.ap_id)

    {:ok, %Activity{local: false} = activity} = Transmogrifier.handle_incoming(data)
    {:ok, data} = Transmogrifier.prepare_activity(activity.data)

    assert data["object"]["type"] == "Note"
  end
end
