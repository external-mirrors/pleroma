# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.ChangeRelayActorType do
  use Ecto.Migration

  alias Pleroma.Repo
  alias Pleroma.User

  def change do
    relay = Repo.get_by(User, nickname: "relay")

    if relay != nil and User.invisible?(relay) do
      relay
      |> Ecto.Changeset.change(actor_type: "Application")
      |> Repo.update()
    end
  end
end
