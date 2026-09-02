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

  @doc "Forgets the position, so the next run starts from the oldest activity."
  @spec reset(String.t()) :: :ok
  def reset(name) do
    Repo.delete_all(from(c in __MODULE__, where: c.name == ^name))
    :ok
  end
end
