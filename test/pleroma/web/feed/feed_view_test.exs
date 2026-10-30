# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Feed.FeedViewTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Web.Feed.FeedView

  test "date helpers accept a missing date" do
    assert FeedView.to_rfc3339(nil) == ""
    assert FeedView.to_rfc2822(nil) == ""
  end

  test "prepare_activity survives an activity without an inserted_at" do
    activity = Pleroma.Factory.insert(:note_activity)
    object = Pleroma.Object.normalize(activity, fetch: false)

    object
    |> Ecto.Changeset.change(data: Map.delete(object.data, "published"))
    |> Pleroma.Repo.update!()

    %{data: data} = FeedView.prepare_activity(%{activity | inserted_at: nil})
    assert data["published"] == nil
  end

  test "escapes fallback content" do
    data = %{
      "attachment" => [],
      "content" => "",
      "summary" => "<script>alert('feed')</script>"
    }

    expected = "&lt;script&gt;alert(&#39;feed&#39;)&lt;/script&gt;"

    assert FeedView.atom_content_encoded(data) == expected
    assert FeedView.rss_content_encoded(data) == expected
  end

  test "does not preview or classify sensitive attachments" do
    attachment = %{
      "name" => "spoiler",
      "url" => [%{"href" => "https://example.com/spoiler.png", "mediaType" => "image/png"}]
    }

    data = %{
      "attachment" => [attachment],
      "content" => "content warning",
      "sensitive" => true
    }

    assert FeedView.atom_content_encoded(data) == "content warning"
    assert FeedView.rss_content_encoded(data) == "content warning"
    assert FeedView.media_content_xml(attachment, true) == ""
    assert FeedView.media_content_xml(attachment, "true") == ""

    media_content = FeedView.media_content_xml(attachment, false)
    assert media_content =~ "<media:description type=\"plain\">spoiler</media:description>"
    refute media_content =~ "media:rating"

    assert FeedView.media_content_xml(Map.delete(attachment, "name"), false) ==
             ~s(<media:content url="https://example.com/spoiler.png" type="image/png" medium="image"/>\n)
  end

  test "does not treat a legacy false string as sensitive" do
    data = %{
      "attachment" => [
        %{"url" => [%{"href" => "https://example.com/image.png", "mediaType" => "image/png"}]}
      ],
      "content" => "visible",
      "sensitive" => "false"
    }

    assert FeedView.atom_content_encoded(data) =~ "<img"
  end
end
