# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Importer do
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Pipeline
  alias Pleroma.Web.ActivityPub.Utils

  require Pleroma.Constants

  def import_object(
        %{
          "type" => type,
          "published" => published,
          "context" => context
        } = object,
        %User{} = user
      )
      when type in Pleroma.Constants.status_types() do
    fixed_object =
      object
      |> strip_ap_id()
      |> rewrite_actor(user)
      |> strip_recipients()

    create_data =
      Utils.make_create_data(%{
        actor: user,
        published: published,
        object: fixed_object,
        to: [],
        context: context
      }, %{})
      |> Utils.lazy_put_activity_defaults()

    with {:ok, activity, _meta} <- Pipeline.common_pipeline(create_data, local: true) do
      # This is to meant to be executed in the oban queue, we only care if it succeeds,
      # so don't query for and put in the object here.
      {:ok, activity}
    else
      e -> e
    end
  end

  def import_activity(%{"type" => "Create", "object" => object} = _activity, %User{} = user) do
    import_object(object, user)
  end

  def import_activity(_, _), do: nil

  def import_one(%{"type" => type} = object, %User{} = user) do
    if type in Pleroma.Constants.status_types() do
      import_object(object, user)
    else
      import_activity(object, user)
    end
  end

  defp strip_ap_id(object), do: object |> Map.drop(["id"])

  defp rewrite_actor(object, user) do
    object
    |> Map.put("actor", user.ap_id)
  end

  defp strip_recipients(object) do
    object
    |> Map.put("to", [])
    |> Map.put("cc", [object["actor"]])
    |> Map.put("bto", [])
    |> Map.put("bcc", [])
  end
end
