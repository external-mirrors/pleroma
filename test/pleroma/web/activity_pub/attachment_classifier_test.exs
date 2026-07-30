# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.AttachmentClassifierTest do
  use Pleroma.DataCase

  import Mox

  alias Pleroma.HTTP.SafeStreamMock
  alias Pleroma.Web.ActivityPub.AttachmentClassifier

  setup :verify_on_exit!

  test "does not inspect known MIME types or ActivityStreams Images" do
    object = %{
      "attachment" => [
        %{
          "type" => "Document",
          "mediaType" => "image/png",
          "url" => [%{"href" => "https://example.com/known", "mediaType" => "image/png"}]
        },
        %{
          "type" => "Image",
          "url" => [
            %{
              "href" => "https://example.com/image",
              "mediaType" => "application/octet-stream"
            }
          ]
        }
      ]
    }

    assert AttachmentClassifier.fix(object) == object
  end

  test "inspects at most four candidates per activity" do
    expect(SafeStreamMock, :fetch_prefix, 4, fn _url, 8_192, _opts ->
      {:error, :unavailable}
    end)

    attachments =
      Enum.map(1..5, fn index ->
        %{
          "type" => "Document",
          "url" => [
            %{
              "href" => "https://example.com/#{index}",
              "mediaType" => "application/octet-stream"
            }
          ]
        }
      end)

    object = %{"attachment" => attachments}
    assert AttachmentClassifier.fix(object) == object
  end

  test "reuses a successful classification for duplicate candidate URLs" do
    body = File.read!("test/fixtures/image.jpg")

    expect(SafeStreamMock, :fetch_prefix, 1, fn "https://example.com/image", 8_192, _opts ->
      {:ok, binary_part(body, 0, 8_192)}
    end)

    attachment = %{
      "type" => "Document",
      "url" => [
        %{
          "href" => "https://example.com/image",
          "mediaType" => "application/octet-stream"
        }
      ]
    }

    object = %{"attachment" => [attachment, attachment]}

    classified =
      attachment
      |> Map.put("mediaType", "image/jpeg")
      |> put_in(["url", Access.at(0), "mediaType"], "image/jpeg")

    assert AttachmentClassifier.fix(object) == %{"attachment" => [classified, classified]}
  end

  test "inspects parameterized generic MIME types" do
    expect(SafeStreamMock, :fetch_prefix, fn "https://example.com/image", 8_192, _opts ->
      {:error, :unavailable}
    end)

    attachment = %{
      "type" => "Document",
      "url" => [
        %{
          "href" => "https://example.com/image",
          "mediaType" => "application/octet-stream; charset=binary"
        }
      ]
    }

    object = %{"attachment" => [attachment]}
    assert AttachmentClassifier.fix(object) == object
  end
end
