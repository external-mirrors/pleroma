# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.AttachmentRelationship do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Pleroma.Object
  alias Pleroma.Repo

  schema "attachment_relationships" do
    belongs_to(:object, Object)
    belongs_to(:attachment, Object)

    timestamps()
  end

  def changeset(%__MODULE__{} = rel, %{object: object, attachment: attachment}) do
    rel
    |> cast(%{}, [])
    |> put_assoc(:object, object)
    |> put_assoc(:attachment, attachment)
  end

  def create(object, attachment) do
    %__MODULE__{}
    |> changeset(%{object: object, attachment: attachment})
    |> Repo.insert()
  end

  def create_many(object, attachments) when is_list(attachments) do
    attachments
    |> Enum.map(fn attachment -> create(object, attachment) end)
  end

  def exists?(%{id: object_id}, %{id: attachment_id}) do
    __MODULE__
    |> where([rel], rel.object_id == ^object_id)
    |> where([rel], rel.attachment_id == ^attachment_id)
    |> Repo.exists?()
  end

  def attachments_of(%{id: object_id}) do
    __MODULE__
    |> join(:inner, [rel], o in assoc(rel, :attachment))
    |> where([rel], rel.object_id == ^object_id)
    |> select([rel, o], o)
    |> Repo.all()
  end

  def references_of(%{id: attachment_id}) do
    __MODULE__
    |> join(:inner, [rel], o in assoc(rel, :object))
    |> where([rel], rel.attachment_id == ^attachment_id)
    |> select([rel, o], o)
    |> Repo.all()
  end
end
