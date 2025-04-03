defmodule Pleroma.Repo.Migrations.AddIsCatToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add_if_not_exists(:is_cat, :boolean, default: false)
      add_if_not_exists(:speak_as_cat, :boolean, default: false)
    end
  end
end
