# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.AddIndexableToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:indexable, :boolean, default: true, null: false)
    end
  end
end
