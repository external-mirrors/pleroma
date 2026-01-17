# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.NormalizeMarkup do
  @moduledoc "Scrub configured hypertext markup"
  alias Pleroma.HTML

  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  @impl true
  def history_awareness, do: :auto

  @impl true
  def filter(%{"type" => type, "object" => object} = activity)
      when type in ["Create", "Update"] do
    scrub_policy = Pleroma.Config.get([:mrf_normalize_markup, :scrub_policy])

    activity =
      with %{} = content_map <- object["contentMap"] do
        fixed_content_map =
          Enum.reduce(content_map, %{}, fn {lang, content}, acc ->
            Map.put(acc, lang, HTML.filter_tags(content, scrub_policy))
          end)

        activity
        |> put_in(["object", "contentMap"], fixed_content_map)
        |> put_in(
          ["object", "content"],
          Pleroma.MultiLanguage.map_to_str(fixed_content_map, multiline: true)
        )
      else
        _ ->
          content =
            object["content"]
            |> HTML.filter_tags(scrub_policy)

          put_in(activity, ["object", "content"], content)
      end

    {:ok, activity}
  end

  def filter(activity), do: {:ok, activity}

  @impl true
  def describe, do: {:ok, %{}}

  @impl true
  def config_description do
    %{
      key: :mrf_normalize_markup,
      related_policy: "Pleroma.Web.ActivityPub.MRF.NormalizeMarkup",
      label: "MRF Normalize Markup",
      description: "MRF NormalizeMarkup settings. Scrub configured hypertext markup.",
      children: [
        %{
          key: :scrub_policy,
          type: :module,
          suggestions: [Pleroma.HTML.Scrubber.Default]
        }
      ]
    }
  end
end
