# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.LocalObjectValidator do
  @moduledoc """
  Rules for new objects of local users. CommonAPI builds objects that follow
  them; C2S clients send their own objects, so the pipeline checks them.
  Remote objects follow the rules of their own server.
  """

  alias Pleroma.Config
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectValidators.QuestionValidator
  alias Pleroma.Web.ActivityPub.Visibility

  require Pleroma.Constants

  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(%{"actor" => actor} = object) do
    user = User.get_cached_by_ap_id(actor)

    with :ok <- validate_in_reply_to(object, user),
         :ok <- validate_quote(object, user),
         :ok <- validate_attachments(object, user, []) do
      validate_type(object)
    end
  end

  @doc "Checks the new version of an edited local object."
  @spec validate_update(map(), Object.t()) :: :ok | {:error, String.t()}
  def validate_update(%{"actor" => actor} = object, %Object{data: orig_data}) do
    known_hrefs = Enum.flat_map(List.wrap(orig_data["attachment"]), &hrefs/1)

    validate_attachments(object, User.get_cached_by_ap_id(actor), known_hrefs)
  end

  defp validate_type(%{"type" => "Question"} = question),
    do: QuestionValidator.validate_local_poll(question)

  defp validate_type(_object), do: :ok

  # Unknown objects can't leak anything, so only known ones are checked.
  defp validate_in_reply_to(%{"inReplyTo" => id}, user) when is_binary(id) do
    case Object.normalize(id, fetch: false) do
      %Object{} = object ->
        if Visibility.visible_for_user?(object, user),
          do: :ok,
          else: {:error, "Can't reply to an invisible object"}

      nil ->
        :ok
    end
  end

  defp validate_in_reply_to(_object, _user), do: :ok

  defp validate_quote(%{"quoteUrl" => id}, %User{} = user) when is_binary(id) do
    case Object.normalize(id, fetch: false) do
      %Object{} = object ->
        if Visibility.visible_for_user?(object, user) and Visibility.quotable?(object, user.ap_id),
          do: :ok,
          else: {:error, "Can't quote this object"}

      nil ->
        :ok
    end
  end

  defp validate_quote(_object, _user), do: :ok

  # Attachments must be the author's uploads (through the upload endpoints),
  # or already be attached to the edited object.
  defp validate_attachments(object, user, known_hrefs) do
    attachments = List.wrap(object["attachment"])
    description_limit = Config.get([:instance, :description_limit])

    cond do
      length(attachments) > Config.get([:instance, :max_media_attachments]) ->
        {:error, "Too many attachments"}

      Enum.any?(attachments, &(String.length(&1["name"] || "") > description_limit)) ->
        {:error, "Attachment description is too long"}

      Enum.all?(attachments, &(known?(&1, known_hrefs) or own_upload?(&1, user))) ->
        :ok

      true ->
        {:error, "Attachments must be own uploads"}
    end
  end

  defp hrefs(%{"url" => urls}), do: for(%{"href" => href} <- List.wrap(urls), do: href)
  defp hrefs(_attachment), do: []

  defp known?(attachment, known_hrefs) do
    case hrefs(attachment) do
      [] -> false
      hrefs -> Enum.all?(hrefs, &(&1 in known_hrefs))
    end
  end

  defp own_upload?(%{"id" => id} = attachment, %User{} = user) when is_binary(id) do
    with %Object{data: %{"type" => type}} = upload <- Object.get_cached_by_ap_id(id),
         true <- type in Pleroma.Constants.upload_object_types(),
         :ok <- Object.authorize_access(upload, user) do
      known?(attachment, hrefs(upload.data))
    else
      _ -> false
    end
  end

  defp own_upload?(_attachment, _user), do: false
end
