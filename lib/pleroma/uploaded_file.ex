# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.UploadedFile do
  use Ecto.Schema

  import Ecto.Changeset

  alias Pleroma.Object
  alias Pleroma.Repo

  schema "uploaded_files" do
    belongs_to(:object, Object)
    field(:path, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = rel, %{object: object} = params) do
    rel
    |> cast(params, [:path])
    |> put_assoc(:object, object)
  end

  def create(%{object: _, path: _} = params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def get_by_object(%Object{} = object) do
    get_by_object_id(object.id)
  end

  def get_by_object_id(object_id) do
    __MODULE__
    |> Repo.get_by(object_id: object_id)
  end
end
