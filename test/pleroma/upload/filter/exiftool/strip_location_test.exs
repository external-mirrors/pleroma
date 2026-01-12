# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exiftool.StripLocationTest do
  use Pleroma.DataCase, async: true
  alias Pleroma.Upload.Filter

  test "apply exiftool filter" do
    ~w{jpg png webp heic}
    |> Enum.map(fn type ->
      source = Path.absname("test/fixtures/strip_location_gps.#{type}")
      tmp_path = copy_to_tmp(source)

      content_type =
        case type do
          "png" -> "image/png"
          "jpg" -> "image/jpeg"
          "webp" -> "image/webp"
          "heic" -> "image/heic"
        end

      upload = %Pleroma.Upload{
        name: "image_with_GPS_data.#{type}",
        content_type: content_type,
        path: source,
        tempfile: tmp_path
      }

      assert Filter.Exiftool.StripLocation.filter(upload) == {:ok, :filtered}

      assert exiftool_gps_tags(source) != ""
      assert exiftool_gps_tags(tmp_path) == ""
    end)
  end

  describe "ExifGpsStripper.strip_gps_data/2" do
    test "strips GPS data from JPEG, PNG, WebP and HEIC" do
      for type <- ~w{jpg png webp heic} do
        source_path = Path.absname("test/fixtures/strip_location_gps.#{type}")
        tmp_path = copy_to_tmp(source_path)

        assert exiftool_gps_tags(tmp_path) != ""
        assert :ok = ExifGpsStripper.strip_gps_data(tmp_path, tmp_path)
        assert exiftool_gps_tags(tmp_path) == ""
      end
    end

    test "returns :noop for images without GPS metadata" do
      for fixture <- [
            "test/fixtures/image.jpg",
            "test/fixtures/image.png",
            "test/fixtures/image.webp",
            "test/fixtures/image.heic"
          ] do
        source_path = Path.absname(fixture)
        original = File.read!(source_path)
        tmp_path = copy_to_tmp(source_path)

        assert exiftool_gps_tags(tmp_path) == ""
        assert :noop = ExifGpsStripper.strip_gps_data(tmp_path, tmp_path)
        assert File.read!(tmp_path) == original
      end
    end
  end

  test "verify unsupported image types are skipped/noop" do
    fixtures = [
      {"test/fixtures/image.svg", "image/svg+xml"},
      {"test/fixtures/image.gif", "image/gif"}
    ]

    for {fixture, content_type} <- fixtures do
      source_path = Path.absname(fixture)
      tmp_path = copy_to_tmp(source_path)
      original = File.read!(tmp_path)

      upload = %Pleroma.Upload{
        name: Path.basename(source_path),
        content_type: content_type,
        path: source_path,
        tempfile: tmp_path
      }

      assert Filter.Exiftool.StripLocation.filter(upload) == {:ok, :noop}
      assert File.read!(tmp_path) == original
    end
  end

  defp copy_to_tmp(source_path) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "strip_location_#{System.unique_integer([:positive])}#{Path.extname(source_path)}"
      )

    File.cp!(source_path, tmp_path)
    tmp_path
  end

  defp exiftool_gps_tags(file_path) do
    {output, 0} = System.cmd("exiftool", ["-m", "-gps:all", file_path])
    String.trim(output)
  end
end
