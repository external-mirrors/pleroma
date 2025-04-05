# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.CachingNebulex do
  @callback put(key :: any(), value :: any(), opts :: Keyword.t()) :: :ok
  @callback put(key :: any(), value :: any()) :: :ok
  @callback get(key :: any(), opts :: Keyword.t()) :: any()
  @callback get(key :: any()) :: any()
  @callback delete(key :: any(), opts :: Keyword.t()) :: :ok
  @callback delete(key :: any()) :: :ok
end
