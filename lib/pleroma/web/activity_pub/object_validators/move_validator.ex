# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.MoveValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.User

  import Ecto.Changeset
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

    field(:target, ObjectValidators.ObjectID)
    field(:published, ObjectValidators.DateTime)
  end

  def cast_and_validate(data) do
    data
    |> cast_data()
    |> validate_data()
  end

  def cast_data(data) do
    %__MODULE__{}
    |> changeset(data)
  end

  def changeset(struct, data) do
    struct
    |> cast(data, __schema__(:fields))
  end

  defp validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Move"])
    |> validate_required([:id, :type, :actor, :object, :target, :to])
    |> validate_fields_match([:actor, :object])
    |> validate_actor_presence()
    |> validate_target()
  end

  # The target account has to list the moved account in its `alsoKnownAs`.
  defp validate_target(cng) do
    actor = get_field(cng, :actor)

    validate_change(cng, :target, fn :target, target ->
      case User.get_cached_by_ap_id(target) do
        %User{also_known_as: also_known_as} when is_list(also_known_as) ->
          if actor in also_known_as do
            []
          else
            [{:target, "Target account must have the origin in `alsoKnownAs`"}]
          end

        _ ->
          [{:target, "can't find user"}]
      end
    end)
  end
end
