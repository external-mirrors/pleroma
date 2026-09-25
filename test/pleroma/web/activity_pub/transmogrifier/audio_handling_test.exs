# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.AudioHandlingTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.Transmogrifier

  import Pleroma.Factory

  defp listen_data do
    insert(:user, ap_id: "http://mastodon.example.org/users/admin")

    %{
      "@context" => "https://www.w3.org/ns/activitystreams",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "type" => "Listen",
      "id" => "http://mastodon.example.org/users/admin/listens/1234/activity",
      "actor" => "http://mastodon.example.org/users/admin",
      "object" => %{
        "type" => "Audio",
        "to" => ["https://www.w3.org/ns/activitystreams#Public"],
        "cc" => [],
        "id" => "http://mastodon.example.org/users/admin/listens/1234",
        "attributedTo" => "http://mastodon.example.org/users/admin",
        "title" => "lain radio episode 1",
        "artist" => "lain",
        "album" => "lain radio",
        "length" => 180_000
      }
    }
  end

  test "it rejects incoming listens exceeding remote_limit before persistence" do
    clear_config([:instance, :remote_limit], 10)
    data = put_in(listen_data(), ["object", "content"], String.duplicate("x", 11))

    assert {:error, {:validate, {:error, :remote_limit}}} =
             Transmogrifier.handle_incoming(data)

    refute Activity.get_by_ap_id(data["id"])
    refute Object.get_by_ap_id(data["object"]["id"])
  end

  test "it accepts incoming listens at the character limit" do
    clear_config([:instance, :remote_limit], 10)
    content = String.duplicate("é", 10)
    data = put_in(listen_data(), ["object", "content"], content)

    assert {:ok, %Activity{} = activity} = Transmogrifier.handle_incoming(data)
    assert Object.normalize(activity).data["content"] == content
  end

  test "it accepts incoming listens with null content" do
    data = put_in(listen_data(), ["object", "content"], nil)

    assert {:ok, %Activity{}} = Transmogrifier.handle_incoming(data)
  end

  for shape <- [:object, :list] do
    @tag tag_shape: shape
    test "it accepts incoming listens with a Hashtag #{shape}", %{tag_shape: shape} do
      hashtag = %{
        "type" => "Hashtag",
        "name" => "#music",
        "href" => "http://mastodon.example.org/tags/music"
      }

      tags = if shape == :object, do: hashtag, else: [hashtag]
      data = put_in(listen_data(), ["object", "tag"], tags)

      assert {:ok, %Activity{} = activity} = Transmogrifier.handle_incoming(data)
      object = Object.get_by_ap_id(activity.data["object"])

      assert object.data["tag"] == [hashtag, "music"]
      assert Object.hashtags(object) == ["music"]
    end
  end

  test "it works for incoming listens" do
    data = listen_data()
    {:ok, %Activity{local: false} = activity} = Transmogrifier.handle_incoming(data)

    object = Object.normalize(activity, fetch: false)

    assert object.data["title"] == "lain radio episode 1"
    assert object.data["artist"] == "lain"
    assert object.data["album"] == "lain radio"
    assert object.data["length"] == 180_000
  end

  test "Funkwhale Audio object" do
    Tesla.Mock.mock(fn
      %{url: "https://channels.tests.funkwhale.audio/federation/actors/compositions"} ->
        %Tesla.Env{
          status: 200,
          body: File.read!("test/fixtures/tesla_mock/funkwhale_channel.json"),
          headers: HttpRequestMock.activitypub_object_headers()
        }
    end)

    data = File.read!("test/fixtures/tesla_mock/funkwhale_create_audio.json") |> Jason.decode!()

    {:ok, %Activity{local: false} = activity} = Transmogrifier.handle_incoming(data)

    assert object = Object.normalize(activity, fetch: false)

    assert object.data["to"] == ["https://www.w3.org/ns/activitystreams#Public"]

    assert object.data["cc"] == [
             "https://channels.tests.funkwhale.audio/federation/actors/compositions/followers"
           ]

    assert object.data["url"] == "https://channels.tests.funkwhale.audio/library/tracks/74"

    assert object.data["attachment"] == [
             %{
               "mediaType" => "audio/ogg",
               "type" => "Link",
               "url" => [
                 %{
                   "href" =>
                     "https://channels.tests.funkwhale.audio/api/v1/listen/3901e5d8-0445-49d5-9711-e096cf32e515/?upload=42342395-0208-4fee-a38d-259a6dae0871&download=false",
                   "mediaType" => "audio/ogg",
                   "type" => "Link"
                 }
               ]
             }
           ]
  end
end
