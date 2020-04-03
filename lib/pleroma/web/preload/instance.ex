# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Preload.Providers.Instance do
<<<<<<< HEAD
  alias Pleroma.Web.MastodonAPI.InstanceView
  alias Pleroma.Web.Nodeinfo.Nodeinfo
  alias Pleroma.Web.Preload.Providers.Provider
=======
  alias Pleroma.Web.Preload.Providers.Provider
  alias Pleroma.Web.MastodonAPI.InstanceView
  alias Pleroma.Web.Nodeinfo.Nodeinfo
>>>>>>> 8025e21a4... adapt dat structures

  @behaviour Provider

  @impl Provider
  def generate_terms(_params \\ %{}) do
    %{}
    |> build_info_tag()
    |> build_panel_tag()
    |> build_nodeinfo_tag()
  end

  def build_info_tag(acc \\ %{}) do
    info_data = InstanceView.render("show.json", %{})

    Map.put(acc, :"/api/v1/instance", info_data)
  end

  def build_panel_tag(acc \\ %{}) do
    instance_path = Path.join(:code.priv_dir(:pleroma), "static/instance/panel.html")

    if File.exists?(instance_path) do
      panel_data = File.read!(instance_path)
      Map.put(acc, :"/instance/panel.html", panel_data)
    else
      acc
    end
  end

  def build_nodeinfo_tag(acc \\ %{}) do
    case Nodeinfo.get_nodeinfo("2.0") do
      {:error, _} ->
        acc

      nodeinfo_data ->
        Map.put(acc, :"/nodeinfo/2.0", nodeinfo_data)
    end
  end
end
