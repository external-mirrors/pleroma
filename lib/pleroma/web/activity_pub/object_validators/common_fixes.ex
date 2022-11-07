# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes do
  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Utils

  def cast_and_filter_recipients(message, field, follower_collection, field_fallback \\ []) do
    {:ok, data} = ObjectValidators.Recipients.cast(message[field] || field_fallback)

    data =
      Enum.reject(data, fn x ->
        String.ends_with?(x, "/followers") and x != follower_collection
      end)

    Map.put(message, field, data)
  end

  def dont_apply_when_importing(data, func, meta) do
    if meta[:importing] do
      data
    else
      func.(data)
    end
  end

  def fix_object_defaults(data, meta) do
    context =
      Utils.maybe_create_context(
        data["context"] || data["conversation"] || data["inReplyTo"] || data["id"]
      )

    %User{follower_address: follower_collection} = User.get_cached_by_ap_id(data["attributedTo"])

    data
    |> Map.put("context", context)
    |> cast_and_filter_recipients("to", follower_collection)
    |> cast_and_filter_recipients("cc", follower_collection)
    |> cast_and_filter_recipients("bto", follower_collection)
    |> cast_and_filter_recipients("bcc", follower_collection)
    |> dont_apply_when_importing(
      &Transmogrifier.fix_implicit_addressing(&1, follower_collection),
      meta
    )
  end

  def fix_activity_addressing(activity, meta \\ []) do
    %User{follower_address: follower_collection} = User.get_cached_by_ap_id(activity["actor"])

    activity
    |> cast_and_filter_recipients("to", follower_collection)
    |> cast_and_filter_recipients("cc", follower_collection)
    |> cast_and_filter_recipients("bto", follower_collection)
    |> cast_and_filter_recipients("bcc", follower_collection)
    |> dont_apply_when_importing(
      &Transmogrifier.fix_implicit_addressing(&1, follower_collection),
      meta
    )
  end

  def fix_actor(data) do
    actor =
      data
      |> Map.put_new("actor", data["attributedTo"])
      |> Containment.get_actor()

    data
    |> Map.put("actor", actor)
    |> Map.put("attributedTo", actor)
  end

  def fix_activity_context(data, %Object{data: %{"context" => object_context}}) do
    data
    |> Map.put("context", object_context)
  end

  def fix_object_action_recipients(%{"actor" => actor} = data, %Object{data: %{"actor" => actor}}) do
    to = ((data["to"] || []) -- [actor]) |> Enum.uniq()

    Map.put(data, "to", to)
  end

  def fix_object_action_recipients(data, %Object{data: %{"actor" => actor}}) do
    to = ((data["to"] || []) ++ [actor]) |> Enum.uniq()

    Map.put(data, "to", to)
  end
end
