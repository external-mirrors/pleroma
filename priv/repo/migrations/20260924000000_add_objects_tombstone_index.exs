# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.AddObjectsTombstoneIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Lets the retention worker walk tombstones in deletion order without
  # scanning objects.
  def change do
    create_if_not_exists(
      index(:objects, [:updated_at, :id],
        name: :objects_tombstone_updated_at_index,
        where: "data->>'type' = 'Tombstone'",
        concurrently: true
      )
    )
  end
end
