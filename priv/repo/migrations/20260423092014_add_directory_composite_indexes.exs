defmodule Pleroma.Repo.Migrations.AddDirectoryCompositeIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS users_directory_last_status_at_index
    ON users (last_status_at DESC NULLS LAST, id DESC NULLS LAST)
    WHERE is_discoverable = true AND invisible = false
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS users_directory_id_index
    ON users (id DESC NULLS LAST)
    WHERE is_discoverable = true AND invisible = false
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS users_directory_last_status_at_index")
    execute("DROP INDEX CONCURRENTLY IF EXISTS users_directory_id_index")
  end
end
