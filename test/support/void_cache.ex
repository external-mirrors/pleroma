# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.VoidCache do
  @moduledoc """
  A module simulating a permanently empty cache.
  """
  @behaviour Pleroma.CachingNebulex

  @impl true
  def put(_, _, _ \\ []), do: :ok

  @impl true
  def get(_, _ \\ []), do: nil

  @impl true
  def delete(_, _ \\ []), do: :ok
end
