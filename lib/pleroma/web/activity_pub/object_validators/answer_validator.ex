# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.AnswerValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.ActivityPub.Visibility

  import Ecto.Changeset

  @primary_key false
  @derive Jason.Encoder

  embedded_schema do
    quote do
      unquote do
        import Elixir.Pleroma.Web.ActivityPub.ObjectValidators.CommonFields
        message_fields()
      end
    end

    field(:name, :string)
    field(:inReplyTo, ObjectValidators.ObjectID)
    field(:attributedTo, ObjectValidators.ObjectID)
    field(:context, :string)

    # TODO: Remove actor on objects
    field(:actor, ObjectValidators.ObjectID)
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

  def changeset(struct, data) do
    data =
      data
      |> CommonFixes.fix_actor()
      |> CommonFixes.fix_object_defaults()

    struct
    |> cast(data, __schema__(:fields))
  end

  defp validate_data(data_cng) do
    data_cng
    |> validate_inclusion(:type, ["Answer"])
    |> validate_required([:id, :inReplyTo, :name, :attributedTo, :actor])
    |> CommonValidations.validate_any_presence([:cc, :to])
    |> CommonValidations.validate_fields_match([:actor, :attributedTo])
    |> CommonValidations.validate_actor_presence()
    |> CommonValidations.validate_host_match()
  end

  @doc """
  Checks that a new Answer is a valid vote: the poll is open and visible to
  the voter, the voter is not its author, the option exists and the voter has
  not voted for it before (or at all, for single-choice polls).

  The rules apply when the voter or the poll is local. Votes between two remote
  parties are not ours to judge.
  """
  @spec validate_vote(map()) :: :ok | {:error, Ecto.Changeset.t()}
  def validate_vote(answer) do
    voter = User.get_cached_by_ap_id(answer["actor"])
    poll = Object.normalize(answer["inReplyTo"], fetch: false)

    if local?(voter, poll) do
      case vote_error(answer, voter, poll) do
        nil -> :ok
        message -> {:error, answer |> cast_data() |> add_error(:inReplyTo, message)}
      end
    else
      :ok
    end
  end

  defp local?(%User{local: true}, _poll), do: true
  defp local?(_voter, %Object{} = poll), do: Object.local?(poll)
  defp local?(_voter, _poll), do: false

  defp vote_error(answer, voter, %Object{data: %{"type" => "Question"}} = poll) do
    cond do
      poll.data["actor"] == answer["actor"] -> "poll's author can't vote"
      !Visibility.visible_for_user?(poll, voter) -> "is not visible to the voter"
      closed?(poll) -> "poll has already ended"
      answer["name"] not in option_names(poll) -> "is not a poll option"
      voted?(answer, poll) -> "already voted"
      true -> nil
    end
  end

  defp vote_error(_answer, _voter, _poll), do: "is not a poll"

  defp option_names(%Object{data: data}) do
    (List.wrap(data["oneOf"]) ++ List.wrap(data["anyOf"]))
    |> Enum.map(& &1["name"])
  end

  defp closed?(%Object{data: %{"closed" => closed}}) when is_binary(closed) do
    case DateTime.from_iso8601(closed) do
      {:ok, closed, _} -> DateTime.compare(closed, DateTime.utc_now()) != :gt
      _ -> false
    end
  end

  defp closed?(_poll), do: false

  # Multiple-choice votes arrive as one Answer per option.
  defp voted?(%{"actor" => actor, "name" => name}, %Object{data: data} = poll) do
    votes = Utils.get_existing_votes(actor, poll)

    if match?([_ | _], data["anyOf"]) do
      Enum.any?(votes, &(&1.object.data["name"] == name))
    else
      votes != []
    end
  end
end
