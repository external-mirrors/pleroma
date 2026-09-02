# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.Cron.RetentionWorker do
  @moduledoc """
  Evicts one batch of old remote threads per run, see `Pleroma.Retention`.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  alias Pleroma.Config
  alias Pleroma.Retention

  require Logger

  @impl true
  def perform(_job) do
    config = Config.get(:retention, [])

    if config[:enabled] do
      stats = Retention.run(config)

      if stats.contexts > 0 do
        Logger.info(
          "Retention: evicted #{stats.contexts} threads " <>
            "(#{stats.objects} objects, #{stats.activities} activities)"
        )
      end
    end

    :ok
  end

  @impl true
  def timeout(_job), do: :timer.minutes(30)
end
