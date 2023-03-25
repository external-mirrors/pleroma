# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.MediaControllerTest do
  use Pleroma.Web.ConnCase, async: true

  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.MastodonAPI.MediaView

  import Pleroma.Factory

  describe "GET /api/v1/pleroma/media" do
    setup do
      %{user: user, conn: conn} = oauth_access(["read:media"])
      another_user = insert(:user)

      test_file = %Plug.Upload{
        content_type: "image/jpeg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      uploaded_objects =
        Enum.map(0..3, fn _ ->
          {:ok, object} = ActivityPub.upload(test_file, actor: User.ap_id(user))
          object
        end)

      {:ok, _} = ActivityPub.upload(test_file, actor: User.ap_id(another_user))

      %{
        user: user,
        conn: conn,
        test_file: test_file,
        uploaded_objects: uploaded_objects
      }
    end

    test "it lists all medias uploaded by me", %{
      conn: conn,
      uploaded_objects: uploaded_objects
    } do
      attachments =
        conn
        |> get("/api/v1/pleroma/media")
        |> json_response_and_validate_schema(:ok)

      expected =
        uploaded_objects
        |> Enum.reverse()
        |> Enum.map(fn attachment ->
          MediaView.render("attachment.json", %{attachment: attachment})
        end)
        |> stringify_keys()

      assert attachments == expected
    end

    test "it does not list other objects", %{
      user: user,
      conn: conn,
      uploaded_objects: uploaded_objects
    } do
      _ = insert(:note, user: user)

      attachments =
        conn
        |> get("/api/v1/pleroma/media")
        |> json_response_and_validate_schema(:ok)

      expected =
        uploaded_objects
        |> Enum.reverse()
        |> Enum.map(fn attachment ->
          MediaView.render("attachment.json", %{attachment: attachment})
        end)
        |> stringify_keys()

      assert attachments == expected
    end

    test "it paginates", %{
      conn: conn,
      uploaded_objects: uploaded_objects
    } do
      attachments =
        conn
        |> get("/api/v1/pleroma/media?limit=3")
        |> json_response_and_validate_schema(:ok)

      expected =
        uploaded_objects
        |> Enum.reverse()
        |> Enum.map(fn attachment ->
          MediaView.render("attachment.json", %{attachment: attachment})
        end)
        |> stringify_keys()

      assert attachments == expected |> Enum.take(3)

      max_id =
        attachments
        |> Enum.at(2)
        |> Map.get("id")

      attachments =
        conn
        |> get("/api/v1/pleroma/media?max_id=#{max_id}")
        |> json_response_and_validate_schema(:ok)

      assert attachments == expected |> Enum.take(-1)
    end
  end

  describe "POST /api/v1/pleroma/media/:id" do
    setup do
      %{user: user, conn: conn} = oauth_access(["write:media"])
      another_user = insert(:user)

      test_file = %Plug.Upload{
        content_type: "image/jpeg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      {:ok, uploaded_object} = ActivityPub.upload(test_file, actor: User.ap_id(user))

      {:ok, other_user_object} = ActivityPub.upload(test_file, actor: User.ap_id(another_user))

      {:ok, no_user_object} = ActivityPub.upload(test_file)

      %{
        user: user,
        conn: conn,
        uploaded_object: uploaded_object,
        other_user_object: other_user_object,
        no_user_object: no_user_object
      }
    end

    test "deletes own object", %{conn: conn, uploaded_object: uploaded_object} do
      conn
      |> delete("/api/v1/pleroma/media/#{uploaded_object.id}")
      |> json_response_and_validate_schema(:ok)

      assert %Object{data: %{"type" => "Tombstone"}} = Object.get_by_id(uploaded_object.id)
    end

    test "refuses to delete other's object", %{conn: conn, other_user_object: other_user_object} do
      conn
      |> delete("/api/v1/pleroma/media/#{other_user_object.id}")
      |> json_response_and_validate_schema(:not_found)

      assert %Object{data: %{"type" => "Document"}} = Object.get_by_id(other_user_object.id)
    end

    test "refuses to delete object without owner", %{conn: conn, no_user_object: no_user_object} do
      conn
      |> delete("/api/v1/pleroma/media/#{no_user_object.id}")
      |> json_response_and_validate_schema(:not_found)

      assert %Object{data: %{"type" => "Document"}} = Object.get_by_id(no_user_object.id)
    end

    test "refuses to delete non-medias", %{conn: conn, user: user} do
      note = insert(:note, user: user)

      conn
      |> delete("/api/v1/pleroma/media/#{note.id}")
      |> json_response_and_validate_schema(:not_found)

      assert %Object{data: %{"type" => "Note"}} = Object.get_by_id(note.id)
    end
  end
end
