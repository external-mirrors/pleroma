# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exif.SmokeTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Upload.Filter.Exif.ReadDescription
  alias Pleroma.Upload.Filter.Exif.StripLocation

  setup_all do
    unless System.find_executable("exiftool") do
      raise "exiftool not found in PATH (required for EXIF filter smoke tests)"
    end

    :ok
  end

  test "StripLocation removes GPS metadata from JPEG" do
    source = fixture_path("image.jpg")
    tmp_path = copy_to_tmp(source)

    assert exiftool_gps_tags(tmp_path) == ""

    exiftool_write!(tmp_path, [
      "-GPSLatitude=12.3456",
      "-GPSLatitudeRef=N",
      "-GPSLongitude=65.4321",
      "-GPSLongitudeRef=E"
    ])

    assert exiftool_gps_tags(tmp_path) != ""

    upload = %Pleroma.Upload{
      name: "image.jpg",
      content_type: "image/jpeg",
      path: source,
      tempfile: tmp_path
    }

    assert StripLocation.filter(upload) == {:ok, :filtered}
    assert exiftool_gps_tags(tmp_path) == ""
  end

  test "StripLocation removes GPS metadata from PNG" do
    source = fixture_path("image.png")
    tmp_path = copy_to_tmp(source)

    assert exiftool_gps_tags(tmp_path) == ""

    exiftool_write!(tmp_path, [
      "-GPSLatitude=12.3456",
      "-GPSLatitudeRef=N",
      "-GPSLongitude=65.4321",
      "-GPSLongitudeRef=E"
    ])

    assert exiftool_gps_tags(tmp_path) != ""

    upload = %Pleroma.Upload{
      name: "image.png",
      content_type: "image/png",
      path: source,
      tempfile: tmp_path
    }

    assert StripLocation.filter(upload) == {:ok, :filtered}
    assert exiftool_gps_tags(tmp_path) == ""
  end

  test "StripLocation removes GPS metadata from WebP" do
    source = fixture_path("image.webp")
    tmp_path = copy_to_tmp(source)

    assert exiftool_gps_tags(tmp_path) == ""

    exiftool_write!(tmp_path, [
      "-GPSLatitude=12.3456",
      "-GPSLatitudeRef=N",
      "-GPSLongitude=65.4321",
      "-GPSLongitudeRef=E"
    ])

    assert exiftool_gps_tags(tmp_path) != ""

    upload = %Pleroma.Upload{
      name: "image.webp",
      content_type: "image/webp",
      path: source,
      tempfile: tmp_path
    }

    assert StripLocation.filter(upload) == {:ok, :filtered}
    assert exiftool_gps_tags(tmp_path) == ""
  end

  test "ReadDescription sets description from ImageDescription (JPEG EXIF)" do
    source = fixture_path("image.jpg")
    tmp_path = copy_to_tmp(source)
    expected_description = "Test description"

    exiftool_write!(tmp_path, ["-ImageDescription=#{expected_description}"])

    upload = %Pleroma.Upload{
      name: "image.jpg",
      content_type: "image/jpeg",
      path: source,
      tempfile: tmp_path,
      description: nil
    }

    assert {:ok, :filtered, %{description: ^expected_description}} =
             ReadDescription.filter(upload)
  end

  defp fixture_path(name), do: Path.absname(Path.join("test/fixtures", name))

  defp copy_to_tmp(source_path) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "pleroma_exif_smoke_#{System.unique_integer([:positive])}#{Path.extname(source_path)}"
      )

    File.cp!(source_path, tmp_path)
    tmp_path
  end

  defp exiftool_write!(file_path, args) when is_list(args) do
    {_, 0} = System.cmd("exiftool", ["-m", "-overwrite_original" | args] ++ [file_path])
    :ok
  end

  defp exiftool_gps_tags(file_path) do
    {output, 0} = System.cmd("exiftool", ["-m", "-gps:all", file_path])
    String.trim(output)
  end
end
