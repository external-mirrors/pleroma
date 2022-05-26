defmodule Pleroma.Repo.Migrations.CreateUploadedFiles do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:uploaded_files) do
      add(:object_id, references(:objects, on_delete: :delete_all))
      add(:path, :string)
    end

    create_if_not_exists(index(:uploaded_files, [:path]))
  end
end
