defmodule Pleroma.Repo.Migrations.CreateDomains do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:domains) do
      add(:domain, :citext, null: false)
      add(:public, :boolean, null: false, default: false)
      add(:resolves, :boolean, null: false, default: false)
      add(:last_checked_at, :naive_datetime)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists(unique_index(:domains, [:domain]))

    alter table(:users) do
      # Restricting: a user's nickname and ap_id embed their domain, so a
      # domain still in use must not be deleted out from under them.
      add_if_not_exists(:domain_id, references(:domains, on_delete: :nothing))
    end

    create_if_not_exists(index(:users, [:domain_id]))
  end
end
