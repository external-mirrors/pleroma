# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.LocalObjectValidator do
  @moduledoc """
  Rules for new objects of local users. CommonAPI builds objects that follow
  them; C2S clients send their own objects, so the pipeline checks them.
  Remote objects follow the rules of their own server.
  """

  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectValidators.QuestionValidator
  alias Pleroma.Web.ActivityPub.Visibility

  @spec validate(map()) :: :ok | {:error, String.t()}
  def validate(%{"actor" => actor} = object) do
    user = User.get_cached_by_ap_id(actor)

    with :ok <- validate_in_reply_to(object, user),
         :ok <- validate_quote(object, user) do
      validate_type(object)
    end
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
end
