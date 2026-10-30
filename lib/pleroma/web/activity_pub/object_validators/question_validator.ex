# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.QuestionValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations
  alias Pleroma.Web.ActivityPub.ObjectValidators.QuestionOptionsValidator
  alias Pleroma.Web.ActivityPub.Transmogrifier

  import Ecto.Changeset

  @primary_key false
  @derive Jason.Encoder

  # Extends from NoteValidator
  embedded_schema do
    quote do
      unquote do
        import Elixir.Pleroma.Web.ActivityPub.ObjectValidators.CommonFields
        message_fields()
        object_fields()
        status_object_fields()
      end
    end

    field(:source, :map)
    field(:closed, ObjectValidators.DateTime)
    field(:votersCount, :integer)
    field(:voters, {:array, ObjectValidators.ObjectID}, default: [])
    field(:nonAnonymous, :boolean)
    embeds_many(:anyOf, QuestionOptionsValidator)
    embeds_many(:oneOf, QuestionOptionsValidator)
  end

  def cast_and_apply(data) do
    data
    |> cast_data
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

  defp fix_closed(data) do
    cond do
      is_binary(data["closed"]) -> data
      is_binary(data["endTime"]) -> Map.put(data, "closed", data["endTime"])
      true -> Map.drop(data, ["closed"])
    end
  end

  defp fix(data) do
    data
    |> CommonFixes.fix_actor()
    |> CommonFixes.fix_object_defaults()
    |> CommonFixes.fix_quote_url()
    |> CommonFixes.fix_likes()
    |> Transmogrifier.fix_emoji()
    |> fix_closed()
  end

  def changeset(struct, data) do
    data = fix(data)

    struct
    |> cast(data, __schema__(:fields) -- [:anyOf, :oneOf, :attachment, :tag])
    |> cast_embed(:attachment)
    |> cast_embed(:anyOf)
    |> cast_embed(:oneOf)
    |> cast_embed(:tag)
  end

  defp validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Question"])
    |> validate_required([:id, :actor, :attributedTo, :type, :context])
    |> CommonValidations.validate_any_presence([:cc, :to])
    |> CommonValidations.validate_fields_match([:actor, :attributedTo])
    |> CommonValidations.validate_actor_presence()
    |> CommonValidations.validate_any_presence([:oneOf, :anyOf])
    |> CommonValidations.validate_host_match()
  end

  @doc """
  Checks a new local poll: `[:instance, :poll_limits]` hold and nobody has
  voted yet. Remote polls follow the limits of their own server.
  """
  @spec validate_local_poll(map()) :: :ok | {:error, String.t()}
  def validate_local_poll(%{"type" => "Question"} = data) do
    options = List.wrap(data["oneOf"]) ++ List.wrap(data["anyOf"])
    names = Enum.map(options, & &1["name"])

    with :ok <- validate_poll_options(names),
         {_, true} <- {:unique, Enum.uniq(names) == names},
         # The end time was computed a moment before validation.
         :ok <- validate_poll_expiration(seconds_until(data["closed"]), 60),
         {_, true} <- {:no_votes, no_votes?(data, options)} do
      :ok
    else
      {:unique, _} -> {:error, "Poll options must be unique"}
      {:no_votes, _} -> {:error, "New polls can't have votes"}
      error -> error
    end
  end

  @spec validate_poll_options([String.t()]) :: :ok | {:error, String.t()}
  def validate_poll_options(options) do
    %{max_options: max_options, max_option_chars: max_option_chars} = poll_limits()

    cond do
      Enum.count(options) < 2 ->
        {:error, "Poll must contain at least 2 options"}

      Enum.count(options) > max_options ->
        {:error, "Poll can't contain more than #{max_options} options"}

      Enum.any?(options, &(String.length(&1) > max_option_chars)) ->
        {:error, "Poll options cannot be longer than #{max_option_chars} characters each"}

      true ->
        :ok
    end
  end

  @spec validate_poll_expiration(integer() | nil, non_neg_integer()) ::
          :ok | {:error, String.t()}
  def validate_poll_expiration(expires_in, slack \\ 0)

  def validate_poll_expiration(nil, _slack), do: {:error, "Poll must have an end time"}

  def validate_poll_expiration(expires_in, slack) do
    %{min_expiration: min, max_expiration: max} = poll_limits()

    cond do
      expires_in > max -> {:error, "Expiration date is too far in the future"}
      expires_in < min - slack -> {:error, "Expiration date is too soon"}
      true -> :ok
    end
  end

  defp poll_limits, do: Pleroma.Config.get([:instance, :poll_limits])

  defp seconds_until(closed) when is_binary(closed) do
    case DateTime.from_iso8601(closed) do
      {:ok, closed, _} -> DateTime.diff(closed, DateTime.utc_now())
      _ -> nil
    end
  end

  defp seconds_until(_), do: nil

  defp no_votes?(data, options) do
    data["votersCount"] in [nil, 0] and data["voters"] in [nil, []] and
      Enum.all?(options, &(get_in(&1, ["replies", "totalItems"]) in [nil, 0]))
  end
end
