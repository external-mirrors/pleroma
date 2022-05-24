defmodule Pleroma.Repo.Migrations.CreateAttachmentRelationships do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:attachment_relationships) do
      add(:object_id, references(:objects, on_delete: :delete_all))
      add(:attachment_id, references(:objects, on_delete: :delete_all))

      timestamps()
    end

    create_if_not_exists(
      unique_index(:attachment_relationships, [:object_id, :attachment_id])
    )
  end
end
