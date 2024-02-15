defmodule Pleroma.Search.Meilisearch do
  require Logger
  require Pleroma.Constants

  alias Pleroma.Activity
  alias Pleroma.Config.Getting, as: Config
  alias Pleroma.Workers.SearchIndexingWorker

  import Pleroma.Search.DatabaseSearch
  import Ecto.Query

  @behaviour Pleroma.Search.SearchBackend

  defp meili_headers do
    private_key = Config.get([Pleroma.Search.Meilisearch, :private_key])

    [{"Content-Type", "application/json"}] ++
      if is_nil(private_key), do: [], else: [{"Authorization", "Bearer #{private_key}"}]
  end

  def meili_get(path) do
    endpoint = Config.get([Pleroma.Search.Meilisearch, :url])

    result =
      Pleroma.HTTP.get(
        Path.join(endpoint, path),
        meili_headers()
      )

    with {:ok, res} <- result do
      {:ok, Jason.decode!(res.body)}
    end
  end

  def meili_post(path, params) do
    endpoint = Config.get([Pleroma.Search.Meilisearch, :url])

    result =
      Pleroma.HTTP.post(
        Path.join(endpoint, path),
        Jason.encode!(params),
        meili_headers()
      )

    with {:ok, res} <- result do
      {:ok, Jason.decode!(res.body)}
    end
  end

  def meili_put(path, params) do
    endpoint = Config.get([Pleroma.Search.Meilisearch, :url])

    result =
      Pleroma.HTTP.request(
        :put,
        Path.join(endpoint, path),
        Jason.encode!(params),
        meili_headers(),
        []
      )

    with {:ok, res} <- result do
      {:ok, Jason.decode!(res.body)}
    end
  end

  def meili_delete(path) do
    endpoint = Config.get([Pleroma.Search.Meilisearch, :url])

    with {:ok, _} <-
           Pleroma.HTTP.request(
             :delete,
             Path.join(endpoint, path),
             "",
             meili_headers(),
             []
           ) do
      :ok
    else
      _ -> {:error, "Could not remove from index"}
    end
  end

  @impl true
  def search(user, query, options \\ []) do
    limit = Enum.min([Keyword.get(options, :limit), 40])
    offset = Keyword.get(options, :offset, 0)
    author = Keyword.get(options, :author)

    res =
      meili_post(
        "/indexes/objects/search",
        %{q: query, offset: offset, limit: limit}
      )

    with {:ok, result} <- res do
      hits = result["hits"] |> Enum.map(& &1["ap"])

      try do
        hits
        |> Activity.create_by_object_ap_id()
        |> Activity.with_preloaded_object()
        |> Activity.restrict_deactivated_users()
        |> maybe_restrict_local(user)
        |> maybe_restrict_author(author)
        |> maybe_restrict_blocked(user)
        |> maybe_fetch(user, query)
        |> order_by([object: obj], desc: obj.data["published"])
        |> Pleroma.Repo.all()
      rescue
        _ -> maybe_fetch([], user, query)
      end
    end
  end

  def object_to_search_data(object) do
    # Only index public or unlisted Notes
    if not is_nil(object) and object.data["type"] == "Note" and
         not is_nil(object.data["content"]) and
         (Pleroma.Constants.as_public() in object.data["to"] or
            Pleroma.Constants.as_public() in object.data["cc"]) and
         object.data["content"] not in ["", "."] do
      data = object.data

      content_str =
        case data["content"] do
          [nil | rest] -> to_string(rest)
          str -> str
        end

      content =
        with {:ok, scrubbed} <-
               FastSanitize.Sanitizer.scrub(content_str, Pleroma.HTML.Scrubber.SearchIndexing),
             trimmed <- String.trim(scrubbed) do
          trimmed
        end

      # Make sure we have a non-empty string
      if content != "" do
        {:ok, published, _} = DateTime.from_iso8601(data["published"])

        %{
          id: object.id,
          content: content,
          ap: data["id"],
          published: published |> DateTime.to_unix()
        }
      end
    end
  end

  @impl true
  def add_to_index(%Pleroma.Activity{id: activity_id}) do
    SearchIndexingWorker.enqueue("add_to_index", %{"activity" => activity_id})
  end

  def add_to_index(activity_id) when is_binary(activity_id) do
    activity = Pleroma.Activity.get_by_id_with_object(activity_id)

    maybe_search_data = object_to_search_data(activity.object)

    if activity.data["type"] == "Create" and maybe_search_data do
      result =
        meili_put(
          "/indexes/objects/documents",
          [maybe_search_data]
        )

      with {:ok, %{"status" => "enqueued"}} <- result do
        # Added successfully
        :ok
      else
        _ ->
          # There was an error, report it
          Logger.error("Failed to add activity #{activity.id} to index: #{inspect(result)}")
          {:error, result}
      end
    else
      # The post isn't something we can search, that's ok
      :ok
    end
  end

  @impl true
  def remove_from_index(%Pleroma.Object{id: object_id}) do
    SearchIndexingWorker.enqueue("remove_from_index", %{"object" => object_id})
  end

  def remove_from_index(object_id) when is_binary(object_id) do
    meili_delete("/indexes/objects/documents/#{object_id}")
  end
end
