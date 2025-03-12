# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectView do
  use Pleroma.Web, :view
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Utils

  def render("object.json", %{object: %Object{} = object}) do
    base = Utils.make_json_ld_header(object.data)

    additional = Transmogrifier.prepare_object(object.data)
    Map.merge(base, additional)
  end

  def render("object.json", %{object: %Activity{data: %{"type" => activity_type}} = activity})
      when activity_type in ["Create", "Listen"] do
    base = Utils.make_json_ld_header(activity.data)
    object = Object.normalize(activity, fetch: false)

    additional =
      Transmogrifier.prepare_object(activity.data)
      |> Map.put("object", Transmogrifier.prepare_object(object.data))

    Map.merge(base, additional)
  end

  def render("object.json", %{object: %Activity{} = activity}) do
    base = Utils.make_json_ld_header(activity.data)
    object_id = Object.normalize(activity, id_only: true)

    additional =
      Transmogrifier.prepare_object(activity.data)
      |> Map.put("object", object_id)

    Map.merge(base, additional)
  end

  def render("replies.json", %{object: %Object{} = object, replies: replies}) do
    base = Utils.make_json_ld_header(object.data)

    object_id = Object.normalize(object, id_only: true)

    Map.merge(base, %{
      "id" => object_id <> "/replies",
      "type" => "Collection",
      "first" => %{
        "type" => "CollectionPage",
        "next" => object_id <> "/replies?only_other_accounts=true&page=true",
        "partOf" => object_id <> "/replies",
        "items" => replies |> Enum.map(fn object -> object.data["id"] end)
      }
    })
  end

  def render("replies_collection.json", %{user: user, object: object, iri: iri}) do
    %{
      "id" => iri,
      "type" => "OrderedCollection",
      "first" =>
        render("replies_collection_page.json", %{
          user: user,
          object: object,
          only_other_accounts: false,
          iri: iri
        })
        |> Map.merge(%{"next" => iri <> "?only_other_accounts=true&page=true"})
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("replies_collection_page.json", %{
        user: user,
        object: object,
        only_other_accounts: only_other_accounts,
        iri: iri
      }) do
    replies =
      Pleroma.Web.ActivityPub.ActivityPub.fetch_replies(object, %{
        user: user,
        only_other_accounts: only_other_accounts,
        only_self: !only_other_accounts
      })

    collection =
      Enum.map(replies, fn
        %{local: true} = activity ->
          {:ok, data} = Transmogrifier.prepare_outgoing(activity.data)
          data

        activity ->
          activity.object.data["id"]
      end)

    %{
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "orderedItems" => collection
    }
    |> Map.merge(Utils.make_json_ld_header())
  end
end
