# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.CreateRetentionCursors do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:retention_cursors, primary_key: false) do
      add(:name, :string, primary_key: true)
      add(:position, :uuid, null: false)

      timestamps()
    end
  end
end
