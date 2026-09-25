# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.HomeTimeline do
  @moduledoc false

  alias Pleroma.Repo

  # Home selection must be exact, but search still benefits from the configured
  # fuzzy GIN limit. A savepoint also restores settings inside caller transactions
  # (including SQL Sandbox), where SET LOCAL alone would leak into later queries.
  # Only read-only selection belongs here, never rendering or job insertion.
  def with_exact_queries(fun) do
    if Repo.in_transaction?() do
      exact_queries(fun)
    else
      {:ok, result} = Repo.transaction(fn -> exact_queries(fun) end)
      result
    end
  end

  defp exact_queries(fun) do
    Repo.query!("SAVEPOINT home_timeline")

    try do
      Repo.query!("SET LOCAL gin_fuzzy_search_limit = 0")
      fun.()
    after
      Repo.query!("ROLLBACK TO SAVEPOINT home_timeline")
      Repo.query!("RELEASE SAVEPOINT home_timeline")
    end
  end
end
