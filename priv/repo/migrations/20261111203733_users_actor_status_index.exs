defmodule Pleroma.Repo.Migrations.UsersActorStatusIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create(index(:users, [:actor_status_id], concurrently: true))
  end
end
