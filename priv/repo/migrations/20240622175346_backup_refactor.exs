defmodule Pleroma.Repo.Migrations.BackupRefactor do
  use Ecto.Migration

  def up do
    alter table("backups") do
      remove(:state)
      remove(:processed_number)
      add(:tempfile, :string)
    end
  end

  def down do
    alter table("backups") do
      add(:state, :integer, default: 5)
      add(:processed_number, :integer, default: 0)
      remove(:tempfile)
    end
  end
end
