defmodule Pleroma.Repo.Migrations.SwapObjectIdIndex do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Fix to allow SwitchToAssociatedObjectIdIndex to be run online
    # First, check whether the index with the new name exists
    with %{rows: [[_index]]} <-
           Ecto.Adapters.SQL.query!(
             Pleroma.Repo,
             "SELECT indexname FROM pg_indexes WHERE tablename = 'activities' AND indexname = 'activities_create_objects_new_index'"
           ) do
      # If it exists, it means we are running the new version of SwitchToAssociatedObjectIdIndex.
      # The old index was left.
      # So, we remove the old index now and rename the new index to the old one.
      drop_if_exists(
        index(:activities, ["(coalesce(data->'object'->>'id', data->>'object'))"],
          name: :activities_create_objects_index
        )
      )

      execute(
        "ALTER INDEX activities_create_objects_new_index RENAME TO activities_create_objects_index"
      )
    end
  end

  def down do
    execute(
      "ALTER INDEX IF EXISTS activities_create_objects_index RENAME TO activities_create_objects_new_index"
    )

    create(
      index(:activities, ["(coalesce(data->'object'->>'id', data->>'object'))"],
        name: :activities_create_objects_index,
        concurrently: true
      )
    )
  end
end
