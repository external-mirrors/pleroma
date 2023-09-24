defmodule Pleroma.Workers.Cron.PruneDatabaseWorker do
  @moduledoc """
  The worker to prune old data from the database.
  """
  require Logger
  use Oban.Worker, queue: "prune_database"

  alias Pleroma.Activity.Pruner, as: ActivityPruner

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Pruning old data from the database")

    Logger.info("Pruning old deletes")
    ActivityPruner.prune_deletes()

    Logger.info("Pruning old undos")
    ActivityPruner.prune_undos()

    Logger.info("Pruning old removes")
    ActivityPruner.prune_removes()

    :ok
  end
end
