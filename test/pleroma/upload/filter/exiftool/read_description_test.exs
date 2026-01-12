# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exiftool.ReadDescriptionTest do
  use Pleroma.DataCase
  alias Pleroma.Upload.Filter

  @uploads %Pleroma.Upload{
    name: "image_with_imagedescription_and_caption-abstract.jpg",
    content_type: "image/jpeg",
    path: Path.absname("test/fixtures/image_with_imagedescription_and_caption-abstract.jpg"),
    tempfile: Path.absname("test/fixtures/image_with_imagedescription_and_caption-abstract.jpg"),
    description: nil
  }

  test "keeps description when not empty" do
    uploads = %Pleroma.Upload{
      name: "image_with_imagedescription_and_caption-abstract.jpg",
      content_type: "image/jpeg",
      path: Path.absname("test/fixtures/image_with_imagedescription_and_caption-abstract.jpg"),
      tempfile:
        Path.absname("test/fixtures/image_with_imagedescription_and_caption-abstract.jpg"),
      description: "Some description"
    }

    assert Filter.Exiftool.ReadDescription.filter(uploads) ==
             {:ok, :noop}
  end

  test "otherwise returns ImageDescription when present" do
    expected_description = exiftool_tag(@uploads.path, "ImageDescription")
    assert is_binary(expected_description)

    assert Filter.Exiftool.ReadDescription.filter(@uploads) ==
             {:ok, :filtered, %{@uploads | description: expected_description}}
  end

  test "Ignores warnings" do
    expected_description =
      exiftool_tag(
        fixture_path("image_with_imagedescription_and_caption-abstract_and_stray_data_after.png"),
        "ImageDescription"
      )

    uploads = %Pleroma.Upload{
      name: "image_with_imagedescription_and_caption-abstract_and_stray_data_after.png",
      content_type: "image/png",
      path:
        Path.absname(
          "test/fixtures/image_with_imagedescription_and_caption-abstract_and_stray_data_after.png"
        ),
      tempfile:
        Path.absname(
          "test/fixtures/image_with_imagedescription_and_caption-abstract_and_stray_data_after.png"
        )
    }

    assert {:ok, :filtered, %{description: ^expected_description}} =
             Filter.Exiftool.ReadDescription.filter(uploads)

    uploads = %Pleroma.Upload{
      name: "image_with_stray_data_after.png",
      content_type: "image/png",
      path: Path.absname("test/fixtures/image_with_stray_data_after.png"),
      tempfile: Path.absname("test/fixtures/image_with_stray_data_after.png")
    }

    assert {:ok, :filtered, %{description: nil}} = Filter.Exiftool.ReadDescription.filter(uploads)
  end

  test "otherwise returns iptc:Caption-Abstract when present" do
    expected_caption =
      exiftool_tag(fixture_path("image_with_caption-abstract.jpg"), "Caption-Abstract")

    upload = %Pleroma.Upload{
      name: "image_with_caption-abstract.jpg",
      content_type: "image/jpeg",
      path: Path.absname("test/fixtures/image_with_caption-abstract.jpg"),
      tempfile: Path.absname("test/fixtures/image_with_caption-abstract.jpg"),
      description: nil
    }

    assert is_binary(expected_caption)

    assert Filter.Exiftool.ReadDescription.filter(upload) ==
             {:ok, :filtered, %{upload | description: expected_caption}}
  end

  test "reads ImageDescription from PNG EXIF chunk" do
    expected_description =
      exiftool_tag(fixture_path("image_with_imagedescription_exif.png"), "ImageDescription")

    assert is_binary(expected_description)

    upload = %Pleroma.Upload{
      name: "image_with_imagedescription_exif.png",
      content_type: "image/png",
      path: fixture_path("image_with_imagedescription_exif.png"),
      tempfile: fixture_path("image_with_imagedescription_exif.png"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(upload) ==
             {:ok, :filtered, %{upload | description: expected_description}}
  end

  test "reads iptc:Caption-Abstract from PNG zTXt profile" do
    expected_caption =
      exiftool_tag(fixture_path("image_with_caption-abstract.png"), "Caption-Abstract")

    assert is_binary(expected_caption)

    upload = %Pleroma.Upload{
      name: "image_with_caption-abstract.png",
      content_type: "image/png",
      path: fixture_path("image_with_caption-abstract.png"),
      tempfile: fixture_path("image_with_caption-abstract.png"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(upload) ==
             {:ok, :filtered, %{upload | description: expected_caption}}
  end

  test "reads ImageDescription from WebP EXIF chunk" do
    expected_description =
      exiftool_tag(fixture_path("strip_location_gps.webp"), "ImageDescription")

    assert is_binary(expected_description)

    upload = %Pleroma.Upload{
      name: "strip_location_gps.webp",
      content_type: "image/webp",
      path: fixture_path("strip_location_gps.webp"),
      tempfile: fixture_path("strip_location_gps.webp"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(upload) ==
             {:ok, :filtered, %{upload | description: expected_description}}
  end

  test "reads ImageDescription from HEIC EXIF item" do
    expected_description =
      exiftool_tag(fixture_path("strip_location_gps.heic"), "ImageDescription")

    assert is_binary(expected_description)

    upload = %Pleroma.Upload{
      name: "strip_location_gps.heic",
      content_type: "image/heic",
      path: fixture_path("strip_location_gps.heic"),
      tempfile: fixture_path("strip_location_gps.heic"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(upload) ==
             {:ok, :filtered, %{upload | description: expected_description}}
  end

  test "reads ImageDescription from GIF XMP" do
    expected_description =
      exiftool_tag(fixture_path("image_with_imagedescription_xmp.gif"), "ImageDescription")

    assert is_binary(expected_description)

    upload = %Pleroma.Upload{
      name: "image_with_imagedescription_xmp.gif",
      content_type: "image/gif",
      path: fixture_path("image_with_imagedescription_xmp.gif"),
      tempfile: fixture_path("image_with_imagedescription_xmp.gif"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(upload) ==
             {:ok, :filtered, %{upload | description: expected_description}}
  end

  test "returns nil for unsupported image types" do
    fixtures = [
      {"image.gif", "image/gif"},
      {"image.svg", "image/svg+xml"}
    ]

    for {name, content_type} <- fixtures do
      upload = %Pleroma.Upload{
        name: name,
        content_type: content_type,
        path: fixture_path(name),
        tempfile: fixture_path(name),
        description: nil
      }

      assert {:ok, :filtered, %{description: nil}} =
               Filter.Exiftool.ReadDescription.filter(upload)
    end
  end

  test "otherwise returns nil" do
    uploads = %Pleroma.Upload{
      name: "image_with_no_description.jpg",
      content_type: "image/jpeg",
      path: Path.absname("test/fixtures/image_with_no_description.jpg"),
      tempfile: Path.absname("test/fixtures/image_with_no_description.jpg"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(uploads) ==
             {:ok, :filtered, uploads}
  end

  test "Return nil when image description from EXIF data exceeds the maximum length" do
    clear_config([:instance, :description_limit], 5)

    assert Filter.Exiftool.ReadDescription.filter(@uploads) ==
             {:ok, :filtered, @uploads}
  end

  test "Ignores content with only whitespace" do
    uploads = %Pleroma.Upload{
      name: "non-existant.jpg",
      content_type: "image/jpeg",
      path:
        Path.absname(
          "test/fixtures/image_with_imagedescription_and_caption-abstract_whitespaces.jpg"
        ),
      tempfile:
        Path.absname(
          "test/fixtures/image_with_imagedescription_and_caption-abstract_whitespaces.jpg"
        ),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(uploads) ==
             {:ok, :filtered, uploads}
  end

  test "Return nil when image description from EXIF data can't be read" do
    uploads = %Pleroma.Upload{
      name: "non-existant.jpg",
      content_type: "image/jpeg",
      path: Path.absname("test/fixtures/non-existant.jpg"),
      tempfile: Path.absname("test/fixtures/non-existant_tmp.jpg"),
      description: nil
    }

    assert Filter.Exiftool.ReadDescription.filter(uploads) ==
             {:ok, :filtered, uploads}
  end

  defp fixture_path(name), do: Path.absname(Path.join("test/fixtures", name))

  defp exiftool_tag(file_path, tag) do
    {output, 0} = System.cmd("exiftool", ["-m", "-s3", "-#{tag}", file_path])

    output
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end
end
