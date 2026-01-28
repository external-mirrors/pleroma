# Adapted from Akkoma
# https://akkoma.dev/AkkomaGang/akkoma/src/branch/develop/priv/repo/migrations/20220108213213_add_mastofe_settings.exs

defmodule Pleroma.Repo.Migrations.AddMastofeSettings do
  alias Pleroma.Repo

  use Ecto.Migration

  def up, do: :ok

  def down do
    if mastofe_settings_column_exists?() do
      """
      UPDATE users SET pleroma_settings_store = jsonb_set(
        pleroma_settings_store,
        '{glitch-lily}',
        mastofe_settings
      )
      WHERE mastofe_settings IS NOT NULL;
      """
      |> execute()
    end

    alter table(:users) do
      remove_if_exists(:mastofe_settings, :map)
    end
  end

  defp mastofe_settings_column_exists?() do
    Repo.query!(
      "SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name='mastofe_settings';"
    ).num_rows > 0
  end
end
