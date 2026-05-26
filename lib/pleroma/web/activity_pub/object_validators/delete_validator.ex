# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.DeleteValidator do
  use Ecto.Schema

  alias Pleroma.Activity
  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  import Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations

  @primary_key false

  embedded_schema do
    quote do
      unquote do
        import Elixir.Pleroma.Web.ActivityPub.ObjectValidators.CommonFields
        message_fields()
        activity_fields()
      end
    end

    field(:deleted_activity_id, ObjectValidators.ObjectID)
  end

  def cast_data(data) do
    %__MODULE__{}
    |> cast(data, __schema__(:fields))
  end

  def add_deleted_activity_id(cng) do
    object =
      cng
      |> get_field(:object)

    with %Activity{id: id} <- Activity.get_create_by_object_ap_id(object) do
      cng
      |> put_change(:deleted_activity_id, id)
    else
      _ -> cng
    end
  end

  @deletable_types ~w{
    Answer
    Article
    Audio
    ChatMessage
    Event
    Note
    Page
    Question
    Tombstone
    Video
  }
  defp validate_data(cng, meta) do
    cng
    |> validate_required([:id, :type, :actor, :to, :cc, :object])
    |> validate_inclusion(:type, ["Delete"])
    |> validate_delete_actor(:actor)
    |> validate_modification_rights(:messages_delete)
    |> validate_delete_target(meta)
    |> add_deleted_activity_id()
  end

  def do_not_federate?(cng) do
    !same_domain?(cng)
  end

  def cast_and_validate(data, meta \\ []) do
    data
    |> cast_data
    |> validate_data(meta)
  end

  defp validate_delete_target(cng, meta) do
    validate_change(cng, :object, fn field_name, object_id ->
      case User.get_cached_by_ap_id(object_id) do
        %User{is_active: false} ->
          [{field_name, "user is deactivated"}]

        %User{} ->
          []

        _ ->
          validate_deleted_object(field_name, object_id, meta)
      end
    end)
  end

  defp validate_deleted_object(field_name, object_id, meta) do
    case get_object_for_update(object_id) || Activity.get_by_ap_id(object_id) do
      nil ->
        [{field_name, "can't find object"}]

      %Object{data: %{"type" => "Tombstone"}} ->
        if Keyword.get(meta, :allow_tombstone_delete) do
          []
        else
          [{field_name, "has already been deleted"}]
        end

      %{data: %{"type" => type}} when type not in @deletable_types ->
        [{field_name, "object not in allowed types"}]

      _ ->
        []
    end
  end

  defp get_object_for_update(object_id) do
    Repo.one(
      from(object in Object,
        where: fragment("(?)->>'id' = ?", object.data, ^object_id),
        lock: "FOR UPDATE"
      )
    )
  end

  defp validate_delete_actor(cng, field_name) do
    validate_change(cng, field_name, fn field_name, actor ->
      case User.get_cached_by_ap_id(actor) do
        %User{} -> []
        _ -> [{field_name, "can't find user"}]
      end
    end)
  end
end
