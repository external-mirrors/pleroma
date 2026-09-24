# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Retention.Cursor do
  @moduledoc """
  Where a retention walk over the activities table got to, persisted across
  runs and restarts. Positions are activity (flake) ids, which are ordered by
  creation time.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Pleroma.Repo

  @primary_key {:name, :string, autogenerate: false}

  schema "retention_cursors" do
    field(:position, FlakeId.Ecto.CompatType)

    timestamps()
  end

  @spec get(String.t()) :: String.t() | nil
  def get(name) do
    Repo.one(from(c in __MODULE__, where: c.name == ^name, select: c.position))
  end

  @spec put(String.t(), String.t()) :: :ok
  def put(name, position) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    %__MODULE__{name: name, position: position}
    |> Repo.insert!(
      on_conflict: [set: [position: position, updated_at: now]],
      conflict_target: :name
    )

    :ok
  end

  @doc """
  The activity id a flake would have received at the given time. Ids at or
  below it belong to activities created before then.
  """
  @spec id_at(NaiveDateTime.t()) :: String.t()
  def id_at(%NaiveDateTime{} = time) do
    ms = time |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond) |> max(0)
    FlakeId.to_string(<<ms::integer-size(64), 0::integer-size(64)>>)
  end

  @doc "Whether position `id` lies after `other`; everything lies after no position."
  @spec after?(String.t(), String.t() | nil) :: boolean()
  def after?(_id, nil), do: true
  def after?(id, other), do: FlakeId.from_string(id) > FlakeId.from_string(other)

  @doc "Forgets the position, so the next run starts from the oldest activity."
  @spec reset(String.t()) :: :ok
  def reset(name) do
    Repo.delete_all(from(c in __MODULE__, where: c.name == ^name))
    :ok
  end
end
