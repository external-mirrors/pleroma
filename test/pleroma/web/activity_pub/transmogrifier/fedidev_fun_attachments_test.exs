# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.FedidevFunAttachmentsTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.HTTP.SafeStreamMock
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.MastodonAPI.StatusView

  import Mox
  import Pleroma.Factory

  setup :verify_on_exit!

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  defp ensure_remote_actor!(ap_id) when is_binary(ap_id) do
    case User.get_cached_by_ap_id(ap_id) do
      %User{} ->
        :ok

      _ ->
        insert(:user,
          local: false,
          ap_id: ap_id,
          follower_address: ap_id <> "/followers",
          following_address: ap_id <> "/following",
          featured_address: ap_id <> "/collections/featured",
          inbox: ap_id <> "/inbox"
        )

        :ok
    end
  end

  defp ingest_data!(data) do
    ensure_remote_actor!(data["actor"])

    assert {:ok, activity} = Transmogrifier.handle_incoming(data)
    object = Object.normalize(activity.data["object"], fetch: false)

    {activity, object}
  end

  defp ingest_fixture!(rel_path) do
    rel_path
    |> File.read!()
    |> Jason.decode!()
    |> ingest_data!()
  end

  defp generic_document_data(url) do
    data = File.read!("test/fixtures/fedidev.fun/attachment_url_list.json") |> Jason.decode!()

    data
    |> put_in(["object", "attachment", "type"], "Document")
    |> put_in(["object", "attachment", "url"], [
      %{"type" => "Link", "href" => url, "mediaType" => "application/octet-stream"}
    ])
  end

  test "drops non-http(s) attachment href" do
    {_activity, object} = ingest_fixture!("test/fixtures/fedidev.fun/attachment_payto_link.json")
    assert object.data["attachment"] == []
  end

  test "drops embedded non-attachment objects" do
    {_activity, object} =
      ingest_fixture!("test/fixtures/fedidev.fun/attachment_embedded_note.json")

    assert object.data["attachment"] == []
  end

  test "accepts attachment url as list and keeps the first link" do
    {_activity, object} = ingest_fixture!("test/fixtures/fedidev.fun/attachment_url_list.json")

    [attachment] = object.data["attachment"]
    [%{"href" => href} | _] = attachment["url"]

    assert href == "https://fedidev.fun/images/007.png"
  end

  test "keeps ingestion content-type sniffing disabled by default" do
    {_activity, object} =
      "https://fedidev.fun/images/extensionless"
      |> generic_document_data()
      |> ingest_data!()

    [attachment] = object.data["attachment"]

    assert [%{"mediaType" => "application/octet-stream"}] = attachment["url"]
    assert %{type: "unknown"} = StatusView.render("attachment.json", %{attachment: attachment})
  end

  test "detects extensionless Document images when explicitly enabled" do
    clear_config([:media_proxy, :ingestion_content_type_sniffing], true)

    url = "https://fedidev.fun/images/extensionless"
    body = File.read!("test/fixtures/image.jpg")

    expect(SafeStreamMock, :fetch_prefix, fn ^url, 8_192, opts ->
      refute Repo.in_transaction?()
      assert {"range", "bytes=0-8191"} in opts[:headers]
      assert {"accept-encoding", "identity"} in opts[:headers]
      assert opts[:pool] == :media
      assert opts[:timeout] == 5_000
      {:ok, binary_part(body, 0, 8_192)}
    end)

    data = generic_document_data(url)
    {_activity, object} = ingest_data!(data)
    [attachment] = object.data["attachment"]

    assert [%{"mediaType" => "image/jpeg"}] = attachment["url"]
    assert %{type: "image"} = StatusView.render("attachment.json", %{attachment: attachment})
    assert {:ok, _activity} = Transmogrifier.handle_incoming(data)
  end

  test "drops malformed attachment list entries" do
    data = File.read!("test/fixtures/fedidev.fun/attachment_url_list.json") |> Jason.decode!()
    data = update_in(data, ["object", "attachment"], &["malformed" | List.wrap(&1)])

    {_activity, object} = ingest_data!(data)

    assert length(object.data["attachment"]) == 1
  end

  test "accepts a URI string in an attachment url list" do
    data = File.read!("test/fixtures/fedidev.fun/attachment_url_list.json") |> Jason.decode!()

    data =
      put_in(data, ["object", "attachment", "url"], [
        "https://fedidev.fun/images/007.png"
      ])

    {_activity, object} = ingest_data!(data)

    assert [%{"url" => [%{"href" => "https://fedidev.fun/images/007.png"}]}] =
             object.data["attachment"]
  end
end
