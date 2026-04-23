# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# Copyright © 2025 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.CollectionViewHelper do
  alias Pleroma.Web.ActivityPub.Utils

  def collection_page_offset(collection, iri, page, show_items \\ true, total \\ nil) do
    {items, total} =
      if is_nil(total) do
        offset = (page - 1) * 10
        {Enum.slice(collection, offset, 10), length(collection)}
      else
        {collection, total}
      end

    items = Enum.map(items, fn user -> user.ap_id end)

    map = %{
      "id" => "#{iri}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => total,
      "orderedItems" => if(show_items, do: items, else: [])
    }

    if page * 10 < total do
      Map.put(map, "next", "#{iri}?page=#{page + 1}")
    else
      map
    end
  end

  defp maybe_omit_next(pagination, _items, nil), do: pagination

  defp maybe_omit_next(pagination, items, limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {limit, ""} -> maybe_omit_next(pagination, items, limit)
      _ -> maybe_omit_next(pagination, items, nil)
    end
  end

  defp maybe_omit_next(pagination, items, limit) when is_number(limit) do
    if Enum.count(items) < limit, do: Map.delete(pagination, "next"), else: pagination
  end

  def collection_page_keyset(
        display_items,
        pagination,
        limit \\ nil,
        skip_ap_context \\ false
      ) do
    %{
      "type" => "OrderedCollectionPage",
      "orderedItems" => display_items
    }
    |> Map.merge(pagination)
    |> maybe_omit_next(display_items, limit)
    |> then(fn m ->
      if skip_ap_context, do: m, else: Map.merge(m, Utils.make_json_ld_header())
    end)
  end
end
