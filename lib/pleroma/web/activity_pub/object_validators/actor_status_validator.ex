# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.ActorStatusValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations

  import Ecto.Changeset

  @primary_key false
  @derive Jason.Encoder

  embedded_schema do
    quote do
      unquote do
        field(:type, :string)
        field(:id, ObjectValidators.ObjectID, primary_key: true)
        # Internal to Pleroma, not used by FEP-82f6
        field(:actor, ObjectValidators.ObjectID)
        # ActorStatus does not support audience scoping
        field(:to, ObjectValidators.Recipients,
          default: ["https://www.w3.org/ns/activitystreams#Public"]
        )

        field(:content, :string)
        field(:published, ObjectValidators.DateTime)
        field(:attributedTo, ObjectValidators.ObjectID)
        field(:emoji, ObjectValidators.Emoji, default: %{})
      end
    end
  end

  def cast_and_apply(data) do
    data
    |> cast_data()
    |> apply_action(:insert)
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

  defp fix(data) do
    data
    |> CommonFixes.fix_actor()
    |> CommonFixes.fix_object_defaults()
  end

  def changeset(struct, data) do
    data = fix(data)

    struct
    |> cast(data, __schema__(:fields))
  end

  defp validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["ActorStatus"])
    |> validate_required([:id, :attributedTo, :to, :type, :content, :published])
    |> CommonValidations.validate_fields_match([:actor, :attributedTo])
    |> CommonValidations.validate_actor_presence()
    |> CommonValidations.validate_host_match()
  end
end
