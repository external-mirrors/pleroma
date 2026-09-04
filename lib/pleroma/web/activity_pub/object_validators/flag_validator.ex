# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.FlagValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators

  import Ecto.Changeset
  import Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations

  @primary_key false

  embedded_schema do
    quote do
      unquote do
        import Elixir.Pleroma.Web.ActivityPub.ObjectValidators.CommonFields
        message_fields()
      end
    end

    field(:actor, ObjectValidators.ObjectID)
    # The reported account, followed by the reported statuses, which are
    # either ids or Pleroma's snapshot of the status
    field(:object, {:array, :any})
    field(:content, :string)
    field(:context, :string)
    field(:published, ObjectValidators.DateTime)
    field(:state, :string)
    field(:rules, {:array, :any})
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
    |> cast(data, __schema__(:fields), empty_values: [])
  end

  defp validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Flag"])
    |> validate_required([:id, :type, :actor, :object, :state])
    |> validate_actor_presence()
    |> validate_reported()
  end

  defp validate_reported(cng) do
    validate_change(cng, :object, fn :object, objects ->
      valid? =
        Enum.all?(objects, fn
          id when is_binary(id) -> true
          %{"id" => id} when is_binary(id) -> true
          _ -> false
        end)

      if objects != [] and valid?, do: [], else: [{:object, "must be a list of ids or objects"}]
    end)
  end
end
