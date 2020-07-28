defmodule Pleroma.Repo.Migrations.AddAdminDataToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:admin_data, :map, default: %{})
    end
  end
end
