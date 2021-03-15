# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RichMedia.CardSanitizer do
  @moduledoc """
  Sanitizes rich-media parser data and returns a MastoAPI compatible card.
  """
  alias Pleroma.Web.MediaProxy

  @fields [
    :url,
    :title,
    :description,
    :type,
    :author_name,
    :author_url,
    :provider_name,
    :provider_url,
    :html,
    :width,
    :height,
    :image,
    :embed_url,
    :blurhash
  ]

  @oembed_types ["video", "photo", "link"]

  def call(opts) do
    Enum.reduce(@fields, %{}, fn field, card ->
      Map.put(card, field, parse(field, opts))
    end)
  end

  defp parse(:url, %{rich_media: %{"url" => url}, page_url: url}), do: url

  defp parse(:url, %{rich_media: %{"url" => url}, page_url: page_url}) when is_binary(url) do
    page_url
    |> URI.parse()
    |> URI.merge(URI.parse(url))
    |> to_string()
  end

  defp parse(:url, %{page_url: url}), do: url
  defp parse(:url, _), do: ""

  defp parse(:type, %{rich_media: %{"type" => type}}) when type in @oembed_types, do: type
  defp parse(:type, _), do: "link"

  defp parse(:provider_name, %{rich_media: %{"provider_name" => provider_name}})
       when is_binary(provider_name),
       do: provider_name

  defp parse(:provider_name, %{page_url: url}) when is_binary(url) do
    case URI.parse(url) do
      %{host: host} -> host
      _ -> ""
    end
  end

  defp parse(:provider_name, _), do: ""

  defp parse(:provider_url, %{rich_media: %{"provider_url" => provider_url}})
       when is_binary(provider_url),
       do: provider_url

  defp parse(:provider_url, %{page_url: url}) do
    case URI.parse(url) do
      %{scheme: scheme, host: host} -> "#{scheme}://#{host}"
      _ -> ""
    end
  end

  defp parse(:provider_url, _), do: ""

  defp parse(:html, %{rich_media: %{"html" => html}}) when is_binary(html) do
    case FastSanitize.Sanitizer.scrub(html, Pleroma.HTML.Scrubber.OEmbed) do
      {:ok, html} -> html
      _ -> ""
    end
  end

  defp parse(:html, _), do: ""

  defp parse(:width, %{rich_media: %{"width" => width}}) when is_integer(width), do: width
  defp parse(:width, _), do: 0

  defp parse(:height, %{rich_media: %{"height" => height}}) when is_integer(height), do: height
  defp parse(:height, _), do: 0

  defp parse(:image, %{rich_media: %{"image" => image}, page_url: url}) when is_binary(image) do
    url
    |> URI.parse()
    |> URI.merge(URI.parse(image))
    |> to_string()
    |> MediaProxy.url()
  end

  defp parse(:image, %{rich_media: %{"thumbnail_url" => image}, page_url: url})
       when is_binary(image) do
    parse(:image, %{rich_media: %{"image" => image}, page_url: url})
  end

  defp parse(:image, _), do: ""

  # These fields should be taken 1:1 from the map if they exist as strings.
  # Otherwise they'll be an empty string.
  defp parse(field, %{rich_media: rich_media})
       when field in [
              :title,
              :description,
              :author_name,
              :author_url
            ] do
    case rich_media[to_string(field)] do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  # TODO: Unimplemented
  defp parse(:embed_url, _), do: ""

  # Unhandled fields will be null.
  defp parse(_, _), do: nil
end
