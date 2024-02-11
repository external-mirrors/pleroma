defmodule Pleroma.Repo.Migrations.CreateRichMediaCard do
  use Ecto.Migration

  def change do
    create table(:rich_media_card) do
      add(:url_hash, :string)
      add(:fields, :map)

      timestamps()
    end

    create(unique_index(:rich_media_card, [:url_hash]))
  end
end
