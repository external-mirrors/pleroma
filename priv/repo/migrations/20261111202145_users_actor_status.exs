defmodule Pleroma.Repo.Migrations.UsersActorStatus do
  use Ecto.Migration

  def change do
    alter table("users") do
      add(:actor_status_id, references(:objects, type: :bigint, on_delete: :nilify_all))
    end
  end
end
