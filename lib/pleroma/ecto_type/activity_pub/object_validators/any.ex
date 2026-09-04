# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.EctoType.ActivityPub.ObjectValidators.Any do
  @moduledoc "Accepts any term, for fields that are stored but not interpreted."
  use Ecto.Type

  def type, do: :map

  def cast(data), do: {:ok, data}

  def dump(data), do: {:ok, data}

  def load(data), do: {:ok, data}
end
