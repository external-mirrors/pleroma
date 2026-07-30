# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.AttachmentClassifier do
  alias Pleroma.Config
  alias Pleroma.HTTP.SafeStream
  alias Pleroma.MediaType

  @sniff_bytes 8 * 1024
  @timeout 5_000
  @max_candidates 4
  @headers [
    {"range", "bytes=0-#{@sniff_bytes - 1}"},
    {"accept-encoding", "identity"}
  ]

  def enabled?, do: Config.get([:media_proxy, :ingestion_content_type_sniffing], false)

  def fix(%{"attachment" => attachments} = object) when is_list(attachments) do
    deadline = System.monotonic_time(:millisecond) + @timeout

    {attachments, _state} =
      Enum.map_reduce(attachments, {0, %{}}, fn attachment, {count, cache} = state ->
        case candidate_href(attachment) do
          href when is_binary(href) ->
            classify_candidate(attachment, href, deadline, state)

          _ ->
            {attachment, {count, cache}}
        end
      end)

    Map.put(object, "attachment", attachments)
  end

  def fix(object), do: object

  defp candidate_href(
         %{
           "type" => "Document",
           "url" => [%{"href" => href} = url | _]
         } = attachment
       )
       when is_binary(href) do
    if generic?(url["mediaType"] || attachment["mediaType"]), do: href
  end

  defp candidate_href(_), do: nil

  defp classify_candidate(attachment, href, deadline, {count, cache} = state) do
    case Map.fetch(cache, href) do
      {:ok, media_type} ->
        {put_media_type(attachment, media_type), state}

      :error when count < @max_candidates ->
        {attachment, media_type} = classify(attachment, deadline)
        {attachment, {count + 1, Map.put(cache, href, media_type)}}

      :error ->
        {attachment, state}
    end
  end

  defp classify(%{"url" => [%{"href" => href} | _]} = attachment, deadline) do
    opts =
      Config.get([:media_proxy, :proxy_opts], [])
      |> Keyword.get(:http, [])
      |> Keyword.merge(
        pool: :media,
        timeout: @timeout,
        deadline: deadline,
        headers: @headers
      )

    with {:ok, prefix} <- safe_stream().fetch_prefix(href, @sniff_bytes, opts),
         {:ok, media_type} <- MediaType.sniff_image(prefix) do
      {put_media_type(attachment, media_type), media_type}
    else
      _ -> {attachment, nil}
    end
  end

  defp put_media_type(attachment, nil), do: attachment

  defp put_media_type(
         %{"url" => [%{} = url | remaining_urls]} = attachment,
         media_type
       ) do
    attachment
    |> Map.put("mediaType", media_type)
    |> Map.put("url", [Map.put(url, "mediaType", media_type) | remaining_urls])
  end

  defp generic?(media_type), do: MediaType.generic?(media_type)

  defp safe_stream do
    Config.get([__MODULE__, :safe_stream], SafeStream)
  end
end
