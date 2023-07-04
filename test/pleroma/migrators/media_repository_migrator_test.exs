# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Migrators.MediaRepositoryMigratorTest do
  use Pleroma.DataCase, async: false

  alias Pleroma.Migrators.MediaRepositoryMigrator
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.UploadedFile

  import Pleroma.Factory

  @url_prefix "#{Pleroma.Web.Endpoint.url()}/media/"

  defp get_url_spec(url) do
    String.replace_prefix(url, @url_prefix, "")
  end

  describe "query/0" do
    test "it returns Documents and Images" do
      document = insert(:attachment)
      image = insert(:attachment, data: %{"type" => "Image"})
      _note = insert(:note)

      result = MediaRepositoryMigrator.query() |> Repo.all()
      assert [_, _] = result
      assert image in result
      assert document in result
    end

    test "it does not return objects with a corresponding UploadedFile" do
      document = insert(:attachment)
      {:ok, _uploaded_file} = UploadedFile.create(%{object: document, path: "some/path"})

      result = MediaRepositoryMigrator.query() |> Repo.all()
      assert [] == result
    end
  end

  describe "add_media_info/1" do
    test "it adds an UploadedFile" do
      document = insert(:attachment)

      url_spec =
        document.data["url"]
        |> Enum.at(0)
        |> Map.get("href")
        |> get_url_spec()

      {:ok, _} = MediaRepositoryMigrator.add_media_info(document)

      uploaded_file = UploadedFile.get_by_object(document)
      assert uploaded_file.path == url_spec
    end

    test "if the url spec does not start with base url, it should fail" do
      clear_config([Pleroma.Upload, :base_url], "https://some.example/media/")

      document = insert(:attachment)

      {:error, _} = MediaRepositoryMigrator.add_media_info(document)

      uploaded_file = UploadedFile.get_by_object(document)
      assert uploaded_file == nil
    end

    test "it adds an UploadedFile for urls starting with one of the additional_base_urls" do
      clear_config([Pleroma.Upload, :base_url], "https://some.example/media/")

      clear_config(
        [:add_media_repository_info, :additional_base_urls],
        ["#{Pleroma.Web.Endpoint.url()}/media/"]
      )

      document = insert(:attachment)

      url_spec =
        document.data["url"]
        |> Enum.at(0)
        |> Map.get("href")
        |> get_url_spec()

      {:ok, _} = MediaRepositoryMigrator.add_media_info(document)

      uploaded_file = UploadedFile.get_by_object(document)
      assert uploaded_file.path == url_spec
    end

    test "it removes the ?name= query" do
      document =
        insert(:attachment, href: "#{Pleroma.Web.Endpoint.url()}/media/1.jpg?name=something.jpg")

      expected_url_spec = "1.jpg"

      {:ok, _} = MediaRepositoryMigrator.add_media_info(document)

      uploaded_file = UploadedFile.get_by_object(document)
      assert uploaded_file.path == expected_url_spec
    end

    test "it urldecodes the path" do
      document =
        insert(:attachment, href: "#{Pleroma.Web.Endpoint.url()}/media/%3A.jpg?name=something.jpg")

      expected_url_spec = ":.jpg"

      {:ok, _} = MediaRepositoryMigrator.add_media_info(document)

      uploaded_file = UploadedFile.get_by_object(document)
      assert uploaded_file.path == expected_url_spec
    end

    test "it ignores non-local objects" do
      document = insert(:attachment, data: %{"id" => "https://some.example/media/1.jpg"})

      {:ok, _} = MediaRepositoryMigrator.add_media_info(document)

      uploaded_file = UploadedFile.get_by_object(document)
      refute uploaded_file
    end

    test "it processes objects without an id" do
      document = insert(:attachment, data: %{"id" => "https://some.example/media/1.jpg"})
      document_without_id = %Object{document | data: document.data |> Map.drop(["id"])}

      url_spec =
        document.data["url"]
        |> Enum.at(0)
        |> Map.get("href")
        |> get_url_spec()

      {:ok, _} = MediaRepositoryMigrator.add_media_info(document_without_id)

      uploaded_file = UploadedFile.get_by_object(document)
      assert uploaded_file.path == url_spec

      document_refetched = Object.get_by_id(document_without_id.id)
      assert Object.local?(document_refetched)
    end
  end
end
