# Pleroma: A lightweight social networking server
# Copyright © Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exif.ReadDescriptionTest do
  use Pleroma.DataCase

  alias Pleroma.Upload.Filter.Exif.ReadDescription

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "pleroma_description_#{System.unique_integer([:positive])}.jpg"
      )

    File.cp!("test/fixtures/image.jpg", path)
    on_exit(fn -> File.rm(path) end)

    {:ok, upload: %Pleroma.Upload{tempfile: path, content_type: "image/jpeg"}}
  end

  test "preserves an existing description", %{upload: upload} do
    upload = %{upload | description: "User-supplied description"}
    write_metadata(upload, "-ImageDescription=Embedded description")

    assert ReadDescription.filter(upload) == {:ok, :noop}
  end

  test "reads an IPTC caption when ImageDescription is absent", %{upload: upload} do
    write_metadata(upload, "-Caption-Abstract=Fallback caption")

    assert {:ok, :filtered, %{description: "Fallback caption"}} = ReadDescription.filter(upload)
  end

  test "falls back to IPTC when ImageDescription is blank", %{upload: upload} do
    write_metadata(upload, ["-ImageDescription=   ", "-Caption-Abstract=Fallback caption"])

    assert {:ok, :filtered, %{description: "Fallback caption"}} = ReadDescription.filter(upload)
  end

  test "falls back to IPTC when ImageDescription exceeds the limit", %{upload: upload} do
    clear_config([:instance, :description_limit], 20)

    write_metadata(upload, [
      "-ImageDescription=#{String.duplicate("x", 21)}",
      "-Caption-Abstract=Fallback caption"
    ])

    assert {:ok, :filtered, %{description: "Fallback caption"}} = ReadDescription.filter(upload)
  end

  test "ignores descriptions exceeding the configured limit", %{upload: upload} do
    clear_config([:instance, :description_limit], 5)
    write_metadata(upload, ["-ImageDescription=Too long", "-Caption-Abstract=Also too long"])

    assert ReadDescription.filter(upload) == {:ok, :noop}
  end

  test "ignores whitespace-only metadata", %{upload: upload} do
    write_metadata(upload, ["-ImageDescription=   ", "-Caption-Abstract=   "])

    assert ReadDescription.filter(upload) == {:ok, :noop}
  end

  test "ignores images without a description", %{upload: upload} do
    assert ReadDescription.filter(upload) == {:ok, :noop}
  end

  test "ignores files that cannot be read", %{upload: upload} do
    File.rm!(upload.tempfile)

    assert ReadDescription.filter(upload) == {:ok, :noop}
  end

  test "ignores non-image uploads", %{upload: upload} do
    write_metadata(upload, "-ImageDescription=Embedded description")

    assert ReadDescription.filter(%{upload | content_type: "application/octet-stream"}) ==
             {:ok, :noop}
  end

  defp write_metadata(upload, tags) do
    {_, 0} =
      System.cmd(
        "exiftool",
        ["-m", "-overwrite_original"] ++ List.wrap(tags) ++ [upload.tempfile]
      )
  end
end
