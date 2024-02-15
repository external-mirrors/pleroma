defmodule Pleroma.Workers.SearchIndexingWorker do
  use Pleroma.Workers.WorkerHelper, queue: "search_indexing"

  @impl Oban.Worker

  alias Pleroma.Config.Getting, as: Config

  def perform(%Job{args: %{"op" => "add_to_index", "activity" => activity_id}}) do
    search_module = Config.get([Pleroma.Search, :module])

    search_module.add_to_index(activity_id)
  end

  def perform(%Job{args: %{"op" => "remove_from_index", "object" => object_id}}) do
    search_module = Config.get([Pleroma.Search, :module])

    search_module.remove_from_index(object_id)
  end
end
