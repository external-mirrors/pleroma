# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectView do
  use Pleroma.Web, :view
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.Transmogrifier

  def render("object.json", %{object: %Object{} = object}) do
    base = Pleroma.Web.ActivityPub.Utils.make_json_ld_header()

    additional = Transmogrifier.prepare_object(object.data)
    Map.merge(base, additional)
  end

  def render("object.json", %{object: %Activity{data: %{"type" => activity_type}} = activity})
      when activity_type in ["Create", "Listen"] do
    base = Pleroma.Web.ActivityPub.Utils.make_json_ld_header()
    object = Object.normalize(activity, fetch: false)

    additional =
      Transmogrifier.prepare_object(activity.data)
      |> Map.put("object", Transmogrifier.prepare_object(object.data))

    Map.merge(base, additional)
  end

  def render("object.json", %{object: %Activity{} = activity}) do
    base = Pleroma.Web.ActivityPub.Utils.make_json_ld_header()
    object_id = Object.normalize(activity, id_only: true)

    additional =
      Transmogrifier.prepare_object(activity.data)
      |> Map.put("object", object_id)

    Map.merge(base, additional)
  end

  def render("replies.json", %{object: object, page: page} = opts) do
    query = Object.replies(object)
    query = from(object in query, select: [:ap_id])
    replies = Repo.all(query)

    total = length(replies)

    collection(replies, "#{object.ap_id}/replies", page, true, total)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("replies.json", %{object: object} = opts) do
    query = Object.replies(object)
    query = from(object in query, select: [:ap_id])
    replies = Repo.all(query)

    total = length(replies)

    %{
      "id" => "#{object.ap_id}/replies",
      "type" => "OrderedCollection",
      "totalItems" => total,
      "first" => collection(replies, "#{object.ap_id}/replies", 1, true)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def collection(collection, iri, page, show_items \\ true, total \\ nil) do
    offset = (page - 1) * 10
    items = Enum.slice(collection, offset, 10)
    items = Enum.map(items, fn item -> item.ap_id end)
    total = total || length(collection)

    map = %{
      "id" => "#{iri}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => total,
      "orderedItems" => if(show_items, do: items, else: [])
    }

    if offset < total do
      Map.put(map, "next", "#{iri}?page=#{page + 1}")
    else
      map
    end
  end
end
