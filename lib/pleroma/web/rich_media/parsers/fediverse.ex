# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RichMedia.Parsers.Fediverse do
  def parse(html, data) do
    case get_authors(html) do
      [] -> data
      authors when is_list(authors) -> Map.put(data, "authors", authors)
      _ -> data
    end
  end

  defp get_authors(html) do
    Floki.find(html, "meta[name^='fediverse:']")
    |> Enum.map(fn {_, x, _} -> List.last(x) |> elem(1) end)
  end
end
