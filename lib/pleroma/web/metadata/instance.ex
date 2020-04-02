# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Metadata.Providers.Instance do
  alias Pleroma.Web.Metadata.Providers.Provider
  alias Pleroma.Web.MastodonAPI.InstanceView
  alias Pleroma.Web.Nodeinfo.Nodeinfo

  @behaviour Provider

  @impl Provider
  def build_tags(_params) do
    []
    |> build_info_tag()
    |> build_panel_tag()
    |> build_nodeinfo_tag()
  end

  def build_panel_tag(acc \\ []) do
    instance_path =
      Path.join(:code.priv_dir(:pleroma), "static/instance/panel.html")
      |> IO.inspect()

    if File.exists?(instance_path) do
      instance_path
      |> File.read!()
      |> case do
        "" ->
          acc

        safe_data ->
          [make_tag("instance:panel", safe_data) | acc]
      end
    else
      acc
    end
  end

  def build_info_tag(acc \\ []) do
    "show.json"
    |> InstanceView.render(%{})
    |> Jason.encode!()
    |> check_for_empty()
    |> case do
      "" ->
        acc

      safe_data ->
        [make_tag("instance:info", safe_data) | acc]
    end
  end

  def build_nodeinfo_tag(acc \\ []) do
    case Nodeinfo.get_nodeinfo("2.0") do
      {:error, _} ->
        acc

      nodeinfo_data ->
        [make_tag("instance:nodeinfo", Jason.encode!(nodeinfo_data)) | acc]
    end
  end

  defp check_for_empty(data) do
    if data != "" and data != "\u200B" do
      data
    else
      ""
    end
  end

  defp make_tag(key, data) do
    {:meta, [property: key, content: data], []}
  end
end
