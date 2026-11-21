# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.AttachmentsCleanupWorkerTest do
  use Pleroma.Web.ConnCase

  use Oban.Testing, repo: Pleroma.Repo

  import Mox

  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.UnstubbedConfigMock, as: ConfigMock
  alias Pleroma.Object

  describe "attachment deletion" do
    setup do: oauth_access(["write:media", "write:statuses"])

    setup do
      ConfigMock
      |> stub_with(Pleroma.Test.StaticConfig)

      image = %Plug.Upload{
        content_type: "image/jpeg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      [image: image]
    end

    setup do: clear_config([:instance, :cleanup_attachments], true)
    setup do: clear_config([Pleroma.Upload, :filters], [Pleroma.Upload.Filter.Dedupe])
    setup do: clear_config([Pleroma.Upload, :uploader], Pleroma.Uploaders.Local)

    test "uploaded media is deleted via DELETE /api/v1/media/:id", %{conn: conn, image: image} do
      result =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image})
        |> json_response_and_validate_schema(:ok)

      assert %Object{} = Object.get_by_id(result["id"])

      {:ok, {:static_dir, upload_path}} = Pleroma.Uploaders.Local.get_file("")

      upload_path =
        Path.join([upload_path, URI.parse(result["url"]).path |> String.replace("/media/", "")])

      assert File.exists?(upload_path)

      # Media object deleted when requested
      assert "" =
               conn
               |> delete("/api/v1/media/#{result["id"]}")
               |> response(200)

      ObanHelpers.perform_all()
      assert not File.exists?(upload_path)
    end

    test "uploaded media is not deleted when there is more than one instance of the same file", %{
      conn: conn,
      image: image
    } do
      result =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image})
        |> json_response_and_validate_schema(:ok)

      result2 =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image})
        |> json_response_and_validate_schema(:ok)

      assert %Object{} = Object.get_by_id(result["id"])

      {:ok, {:static_dir, upload_path}} = Pleroma.Uploaders.Local.get_file("")

      upload_path =
        Path.join([upload_path, URI.parse(result["url"]).path |> String.replace("/media/", "")])

      assert File.exists?(upload_path)

      # Media object deleted when requested
      assert "" =
               conn
               |> delete("/api/v1/media/#{result["id"]}")
               |> response(200)

      ObanHelpers.perform_all()
      # File should still be there
      assert not not File.exists?(upload_path)
      # Delete the second instance of the file
      assert "" =
               conn
               |> delete("/api/v1/media/#{result2["id"]}")
               |> response(200)

      ObanHelpers.perform_all()
      # File should no longer exist
      assert not File.exists?(upload_path)
    end

    test "uploaded media is deleted when the post it is attached to is deleted", %{
      conn: conn,
      image: image
    } do
      result =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image})
        |> json_response_and_validate_schema(:ok)

      {:ok, {:static_dir, upload_path}} = Pleroma.Uploaders.Local.get_file("")

      upload_path =
        Path.join([upload_path, URI.parse(result["url"]).path |> String.replace("/media/", "")])

      assert File.exists?(upload_path)

      status =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/statuses", %{"media_ids" => [result["id"]]})
        |> json_response_and_validate_schema(200)

      delete(conn, "/api/v1/statuses/#{status["id"]}")
      |> json_response_and_validate_schema(200)

      ObanHelpers.perform_all()
      assert not File.exists?(upload_path)
    end

    test "uploaded media is refused to be deleted when the post it is attached to still exists",
         %{conn: conn, image: image} do
      result =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image})
        |> json_response_and_validate_schema(:ok)

      {:ok, {:static_dir, upload_path}} = Pleroma.Uploaders.Local.get_file("")

      upload_path =
        Path.join([upload_path, URI.parse(result["url"]).path |> String.replace("/media/", "")])

      assert File.exists?(upload_path)

      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/statuses", %{"media_ids" => [result["id"]]})
      |> json_response_and_validate_schema(200)

      assert %{"error" => _} =
               conn
               |> delete("/api/v1/media/#{result["id"]}")
               |> json_response(400)

      ObanHelpers.perform_all()
      assert File.exists?(upload_path)
    end

    test "uploaded media is refused to be deleted when attached to a scheduled activity", %{
      conn: conn,
      image: image
    } do
      result =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post("/api/v1/media", %{"file" => image})
        |> json_response_and_validate_schema(:ok)

      scheduled_at =
        NaiveDateTime.add(NaiveDateTime.utc_now(), :timer.minutes(120), :millisecond)
        |> NaiveDateTime.to_iso8601()
        |> Kernel.<>("Z")

      assert %{"scheduled_at" => _} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/v1/statuses", %{
                 "status" => "scheduled",
                 "scheduled_at" => scheduled_at,
                 "media_ids" => [result["id"]]
               })
               |> json_response_and_validate_schema(200)

      assert %{"error" => _} =
               conn
               |> delete("/api/v1/media/#{result["id"]}")
               |> json_response(400)
    end
  end
end
