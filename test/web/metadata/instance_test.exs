# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Metadata.Providers.InstanceTest do
  use Pleroma.DataCase
  alias Pleroma.Web.Metadata.Providers.Instance

  setup do: clear_config([Pleroma.Web.Metadata, :unfurl_nsfw])

  test "it renders the info" do
    result = Instance.build_tags(%{})

    %{
      "description" => description,
      "email" => "admin@example.com",
      "registrations" => true
    } =
      case Enum.find(result, nil, &find_tag(&1, "instance:info")) do
        nil ->
          %{}

        {:meta, properties, []} ->
          properties
          |> Keyword.get(:content, "")
          |> Jason.decode!()
      end

    assert String.equivalent?(description, "A Pleroma instance, an alternative fediverse server")
  end

  test "it renders the panel" do
    result = Instance.build_tags(%{})

    html_panel =
      case Enum.find(result, nil, &find_tag(&1, "instance:panel")) do
        nil ->
          %{}

        {:meta, properties, []} ->
          properties
          |> Keyword.get(:content, "")
      end

    assert String.contains?(
             html_panel,
             "<p>Welcome to <a href=\"https://pleroma.social\" target=\"_blank\">Pleroma!</a></p>"
           )
  end

  test "it renders the node_info" do
    result = Instance.build_tags(%{})

    %{
      "metadata" => metadata,
      "version" => "2.0"
    } =
      case Enum.find(result, nil, &find_tag(&1, "instance:nodeinfo")) do
        nil ->
          %{}

        {:meta, properties, []} ->
          properties
          |> Keyword.get(:content, "")
          |> Jason.decode!()
      end

    assert metadata["private"] == false
    assert metadata["suggestions"] == %{"enabled" => false}
  end

  def find_tag(tag, property) do
    with {:meta, properties, []} <- tag,
         prop_name <- Keyword.get(properties, :property, false) do
      String.equivalent?(prop_name, property)
    else
      _ ->
        false
    end
  end
end
