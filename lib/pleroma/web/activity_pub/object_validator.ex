# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidator do
  @moduledoc """
  This module is responsible for validating an object (which can be an activity)
  and checking if it is both well formed and also compatible with our view of
  the system.
  """

  @behaviour Pleroma.Web.ActivityPub.ObjectValidator.Validating

  import Pleroma.Constants, only: [activity_types: 0, actor_types: 0, object_types: 0]

  alias Pleroma.Activity
  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Maps
  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.Object.Updater
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectValidators.AcceptRejectValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.AddRemoveValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.AnnounceValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.AnswerValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.ArticleNotePageValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.AudioImageVideoValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.BlockValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.ChatMessageValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes
  alias Pleroma.Web.ActivityPub.ObjectValidators.CreateChatMessageValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.CreateGenericValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.DeleteValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.EmojiReactValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.EventValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.FlagValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.FollowValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.LikeValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.LocalObjectValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.MoveValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.QuestionValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.UndoValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.UpdateValidator
  alias Pleroma.Web.ActivityPub.ObjectValidators.UserValidator
  alias Pleroma.Web.ActivityPub.Utils

  @impl true
  def validate(object, meta)

  # This overload works together with the InboxGuardPlug
  # and ensures that we are not accepting any activity type
  # that cannot pass InboxGuardPlug.
  # If we want to support any more activity types, make sure to
  # add it in Pleroma.Constants's activity_types or object_types,
  # and, if applicable, allowed_activity_types_from_strangers.
  def validate(%{"type" => type}, _meta)
      when type not in activity_types() and type not in object_types(),
      do: {:error, :not_allowed_object_type}

  def validate(%{"type" => "Block"} = block_activity, meta) do
    with {:ok, block_activity} <-
           block_activity
           |> BlockValidator.cast_and_validate()
           |> Ecto.Changeset.apply_action(:insert) do
      block_activity = stringify_keys(block_activity)
      outgoing_blocks = Pleroma.Config.get([:activitypub, :outgoing_blocks])

      meta =
        if !outgoing_blocks do
          Keyword.put(meta, :do_not_federate, true)
        else
          meta
        end

      {:ok, block_activity, meta}
    end
  end

  def validate(%{"type" => "Undo"} = object, meta) do
    with {:ok, object} <-
           object
           |> UndoValidator.cast_and_validate()
           |> Ecto.Changeset.apply_action(:insert) do
      object = stringify_keys(object)
      undone_object = Activity.get_by_ap_id(object["object"])

      meta =
        meta
        |> Keyword.put(:object_data, undone_object.data)

      {:ok, object, meta}
    end
  end

  def validate(%{"type" => "Move"} = object, meta) do
    with {:ok, object} <-
           object
           |> MoveValidator.cast_and_validate()
           |> Ecto.Changeset.apply_action(:insert) do
      object = stringify_keys(object)
      {:ok, object, meta}
    end
  end

  def validate(%{"type" => "Flag", "object" => reported} = object, meta) do
    with {:ok, flag} <-
           object
           |> FlagValidator.cast_and_validate()
           |> Ecto.Changeset.apply_action(:insert) do
      # The reported statuses are stored as given, they are part of the report.
      flag = flag |> stringify_keys() |> Map.put("object", reported)
      {:ok, flag, meta}
    end
  end

  def validate(%{"type" => "Delete"} = object, meta) do
    with cng <- DeleteValidator.cast_and_validate(object),
         do_not_federate <- DeleteValidator.do_not_federate?(cng),
         {:ok, object} <- Ecto.Changeset.apply_action(cng, :insert) do
      object = stringify_keys(object)
      meta = Keyword.put(meta, :do_not_federate, do_not_federate)
      {:ok, object, meta}
    end
  end

  def validate(
        %{"type" => "Create", "object" => %{"type" => "ChatMessage"} = object} = create_activity,
        meta
      ) do
    with {:ok, object_data} <- cast_and_apply(object),
         meta = Keyword.put(meta, :object_data, object_data |> stringify_keys),
         {:ok, create_activity} <-
           create_activity
           |> CreateChatMessageValidator.cast_and_validate(meta)
           |> Ecto.Changeset.apply_action(:insert) do
      create_activity = stringify_keys(create_activity)
      {:ok, create_activity, meta}
    end
  end

  def validate(
        %{"type" => "Create", "object" => %{"type" => objtype} = object} = create_activity,
        meta
      )
      when objtype in ~w[Question Answer Audio Video Image Event Article Note Page] do
    with :ok <- validate_remote_limit(create_activity),
         {:ok, object_data} <-
           object
           |> CommonFixes.maybe_set_attributed_to_from_activity(create_activity)
           |> CommonFixes.maybe_add_language_from_activity(create_activity)
           |> cast_and_apply_and_stringify_with_history(),
         :ok <- validate_new_object(object_data, meta),
         meta = Keyword.put(meta, :object_data, object_data),
         {:ok, create_activity} <-
           create_activity
           |> CreateGenericValidator.cast_and_validate(meta)
           |> Ecto.Changeset.apply_action(:insert) do
      create_activity = stringify_keys(create_activity)
      {:ok, create_activity, meta}
    end
  end

  def validate(
        %{"type" => "Listen", "object" => %{"type" => "Audio"} = object} = listen_activity,
        meta
      ) do
    with :ok <- validate_remote_limit(listen_activity),
         {:ok, object_data} <-
           object
           |> CommonFixes.maybe_set_attributed_to_from_activity(listen_activity)
           |> cast_and_apply_and_stringify_with_history(),
         meta = Keyword.put(meta, :object_data, object_data),
         {:ok, listen_activity} <-
           listen_activity
           |> CreateGenericValidator.cast_and_validate(meta)
           |> Ecto.Changeset.apply_action(:insert) do
      listen_activity = stringify_keys(listen_activity)
      {:ok, listen_activity, meta}
    end
  end

  def validate(%{"type" => type} = object, meta)
      when type in ~w[Event Question Audio Video Image Article Note Page] do
    validator =
      case type do
        "Event" -> EventValidator
        "Question" -> QuestionValidator
        "Audio" -> AudioImageVideoValidator
        "Video" -> AudioImageVideoValidator
        "Image" -> AudioImageVideoValidator
        "Article" -> ArticleNotePageValidator
        "Note" -> ArticleNotePageValidator
        "Page" -> ArticleNotePageValidator
      end

    with {:ok, object} <-
           do_separate_with_history(object, fn object ->
             with {:ok, object} <-
                    object
                    |> validator.cast_and_validate()
                    |> Ecto.Changeset.apply_action(:insert) do
               object = stringify_keys(object)

               # Insert copy of hashtags as strings for the non-hashtag table indexing
               tag = (object["tag"] || []) ++ Object.hashtags(%Object{data: object})
               object = Map.put(object, "tag", tag)

               {:ok, object}
             end
           end) do
      {:ok, object, meta}
    end
  end

  def validate(
        %{"type" => "Update", "object" => %{"type" => objtype} = object} = update_activity,
        meta
      )
      when objtype in ~w[Question Answer Audio Video Event Article Note Page] do
    object = maybe_rebuild_local_update_object(object, meta)
    update_activity = Map.put(update_activity, "object", object)

    with {_, {:ok, object_data, _}} <-
           {:object_validation,
            object
            |> CommonFixes.maybe_set_attributed_to_from_activity(update_activity)
            |> CommonFixes.maybe_add_language_from_activity(update_activity)
            |> validate(meta)},
         :ok <- validate_local_update(object_data, meta),
         meta = maybe_put_update_object_data(meta, object_data),
         {:ok, update_activity} <-
           update_activity
           |> UpdateValidator.cast_and_validate(meta)
           |> Ecto.Changeset.apply_action(:insert) do
      update_activity = stringify_keys(update_activity)
      {:ok, update_activity, meta}
    else
      {:object_validation, e} -> e
      {:error, _} = error -> error
    end
  end

  def validate(%{"type" => type} = object, meta)
      when type in ~w[Accept Reject Follow Like EmojiReact Announce
      ChatMessage Answer] do
    validator =
      case type do
        "Accept" -> AcceptRejectValidator
        "Reject" -> AcceptRejectValidator
        "Follow" -> FollowValidator
        "Like" -> LikeValidator
        "EmojiReact" -> EmojiReactValidator
        "Announce" -> AnnounceValidator
        "ChatMessage" -> ChatMessageValidator
        "Answer" -> AnswerValidator
      end

    with {:ok, object} <-
           object
           |> validator.cast_and_validate()
           |> Ecto.Changeset.apply_action(:insert) do
      object = stringify_keys(object)
      {:ok, object, meta}
    end
  end

  def validate(%{"type" => type} = object, meta) when type == "Update" do
    with :ok <- validate_updated_actor(object, meta),
         {:ok, object} <-
           object
           |> UpdateValidator.cast_and_validate(meta)
           |> Ecto.Changeset.apply_action(:insert) do
      object = stringify_keys(object)
      {:ok, object, meta}
    end
  end

  def validate(%{"type" => type} = object, meta) when type in ~w(Add Remove) do
    with {:ok, object} <-
           object
           |> AddRemoveValidator.cast_and_validate(meta)
           |> Ecto.Changeset.apply_action(:insert) do
      object = stringify_keys(object)
      {:ok, object, meta}
    end
  end

  def validate(o, m), do: {:error, {:validator_not_set, {o, m}}}

  # Shared with legacy insertion so previews and pipeline posts enforce the same limit.
  def validate_remote_limit(%{"object" => %{"content" => content}}) when is_binary(content) do
    if String.length(content) <= Pleroma.Config.get([:instance, :remote_limit]) do
      :ok
    else
      {:error, :remote_limit}
    end
  end

  def validate_remote_limit(_), do: :ok

  # Rules for new objects that depend on other objects or on the creator.
  defp validate_new_object(%{"type" => "Answer"} = answer, _meta),
    do: AnswerValidator.validate_vote(answer)

  defp validate_new_object(object, meta) do
    if Keyword.get(meta, :local, false) do
      LocalObjectValidator.validate(object)
    else
      :ok
    end
  end

  # The server owns the edit history, the edit time and the poll results of
  # local objects. Only the editable fields come from the new version.
  defp maybe_rebuild_local_update_object(%{"id" => id} = object, meta) when is_binary(id) do
    with true <- Keyword.get(meta, :local, false),
         %Object{data: orig_data} <- Object.get_by_ap_id(id) do
      object =
        object
        |> Map.delete("updated")
        |> Maps.put_if_present("updated", orig_data["updated"])

      Updater.make_update_object_data(orig_data, object, Utils.make_date())
    else
      _ -> object
    end
  end

  defp maybe_rebuild_local_update_object(object, _meta), do: object

  defp validate_local_update(%{"id" => id} = object_data, meta) do
    with true <- Keyword.get(meta, :local, false),
         %Object{} = orig_object <- Object.get_by_ap_id(id) do
      LocalObjectValidator.validate_update(object_data, orig_object)
    else
      _ -> :ok
    end
  end

  # Local Updates keep the embedded object, so MRF filters what gets stored
  # and federated. Remote Updates store the validated object.
  defp maybe_put_update_object_data(meta, object_data) do
    if Keyword.get(meta, :local, false) do
      meta
    else
      Keyword.put(meta, :object_data, object_data)
    end
  end

  defp validate_updated_actor(%{"object" => %{"type" => type} = actor}, meta)
       when type in actor_types() do
    with {_, false} <- {:local, Access.get(meta, :local, false)},
         {:ok, _, _} <- UserValidator.validate(actor, meta) do
      :ok
    else
      {:local, true} -> :ok
      error -> error
    end
  end

  defp validate_updated_actor(_, _), do: :ok

  def cast_and_apply_and_stringify_with_history(object) do
    do_separate_with_history(object, fn object ->
      with {:ok, object_data} <- cast_and_apply(object),
           object_data <- object_data |> stringify_keys() do
        {:ok, object_data}
      end
    end)
  end

  def cast_and_apply(%{"type" => "ChatMessage"} = object) do
    ChatMessageValidator.cast_and_apply(object)
  end

  def cast_and_apply(%{"type" => "Question"} = object) do
    QuestionValidator.cast_and_apply(object)
  end

  def cast_and_apply(%{"type" => "Answer"} = object) do
    AnswerValidator.cast_and_apply(object)
  end

  def cast_and_apply(%{"type" => type} = object) when type in ~w[Audio Image Video] do
    AudioImageVideoValidator.cast_and_apply(object)
  end

  def cast_and_apply(%{"type" => "Event"} = object) do
    EventValidator.cast_and_apply(object)
  end

  def cast_and_apply(%{"type" => type} = object) when type in ~w[Article Note Page] do
    ArticleNotePageValidator.cast_and_apply(object)
  end

  def cast_and_apply(o), do: {:error, {:validator_not_set, o}}

  def stringify_keys(object) when is_struct(object) do
    object
    |> Map.from_struct()
    |> stringify_keys
  end

  def stringify_keys(object) when is_map(object) do
    object
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Map.new(fn {key, val} -> {to_string(key), stringify_keys(val)} end)
  end

  def stringify_keys(object) when is_list(object) do
    object
    |> Enum.map(&stringify_keys/1)
  end

  def stringify_keys(object), do: object

  def fetch_actor(object) do
    with actor <- Containment.get_actor(object),
         {:ok, actor} <- ObjectValidators.ObjectID.cast(actor) do
      User.get_or_fetch_by_ap_id(actor)
    end
  end

  def fetch_actor_and_object(object) do
    fetch_actor(object)
    Object.normalize(object["object"], fetch: true)
    :ok
  end

  defp for_each_history_item(
         %{"type" => "OrderedCollection", "orderedItems" => items} = history,
         object,
         fun
       ) do
    processed_items =
      Enum.map(items, fn item ->
        with item <- Map.put(item, "id", object["id"]),
             {:ok, item} <- fun.(item) do
          item
        else
          _ -> nil
        end
      end)

    if Enum.all?(processed_items, &(not is_nil(&1))) do
      {:ok, Map.put(history, "orderedItems", processed_items)}
    else
      {:error, :invalid_history}
    end
  end

  defp for_each_history_item(nil, _object, _fun) do
    {:ok, nil}
  end

  defp for_each_history_item(_, _object, _fun) do
    {:error, :invalid_history}
  end

  # fun is (object -> {:ok, validated_object_with_string_keys})
  defp do_separate_with_history(object, fun) do
    with history <- object["formerRepresentations"],
         object <- Map.drop(object, ["formerRepresentations"]),
         {_, {:ok, object}} <- {:main_body, fun.(object)},
         {_, {:ok, history}} <- {:history_items, for_each_history_item(history, object, fun)} do
      object =
        if history do
          Map.put(object, "formerRepresentations", history)
        else
          object
        end

      {:ok, object}
    else
      {:main_body, e} -> e
      {:history_items, e} -> e
    end
  end
end
