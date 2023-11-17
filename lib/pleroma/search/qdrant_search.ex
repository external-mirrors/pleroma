defmodule Pleroma.Search.QdrantSearch do
  @behaviour Pleroma.Search.SearchBackend
  use GenServer
  import Ecto.Query
  alias Pleroma.Activity

  # @model "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

  alias __MODULE__.HTTP
  import Pleroma.Search.Meilisearch, only: [object_to_search_data: 1]

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    payload = %{vectors: %{size: 384, distance: "Cosine"}}

    HTTP.put("/collections/posts", payload)

    {:ok, nil, {:continue, :load_model}}
  end

  @impl true
  def handle_continue(:load_model, _state) do
    python_path = Path.join([File.cwd!(), "python"])
    python = Path.join(python_path, "venv/bin/python")

    {:ok, p} =
      :python.start(
        python_path: python_path |> String.to_charlist(),
        python: python |> String.to_charlist()
      )

    {:noreply, p}
  end

  def get_embedding(text, type \\ :get_embedding) do
    GenServer.call(__MODULE__, {:get_embedding, text, type})
  end

  @impl true
  def handle_call({:get_embedding, text, type}, _, p) do
    res = :python.call(p, :qdrant_search, type, [text])
    {:reply, res, p}
  end

  @impl true
  def add_to_index(activity) do
    maybe_search_data = object_to_search_data(activity.object)

    if activity.data["type"] == "Create" and maybe_search_data do
      payload = %{
        points: [
          %{
            id: activity.id |> FlakeId.from_string() |> Ecto.UUID.cast!(),
            vector: get_embedding(maybe_search_data.content, :get_passage_embedding)
          }
        ]
      }

      with {:ok, %{status: 200}} <-
             HTTP.put("/collections/posts/points", payload) do
        :ok
      else
        e -> {:error, e}
      end
    else
      :ok
    end
  end

  @impl true
  def search(_user, query, _options) do
    payload = %{
      vector: get_embedding(query, :get_query_embedding),
      limit: 20
    }

    with {:ok, %{body: %{"result" => result}}} <-
           HTTP.post("/collections/posts/points/search", payload) do
      ids =
        Enum.map(result, fn %{"id" => id} ->
          Ecto.UUID.dump!(id)
        end)

      from(a in Activity, where: a.id in ^ids)
      |> Activity.with_preloaded_object()
      |> Activity.restrict_deactivated_users()
      |> Ecto.Query.order_by([a], fragment("array_position(?, ?)", ^ids, a.id))
      |> Pleroma.Repo.all()
    else
      _ ->
        []
    end
  end

  @impl true
  def remove_from_index(_object) do
    {:ok, nil}
  end
end

defmodule Pleroma.Search.QdrantSearch.HTTP do
  use Tesla

  plug(Tesla.Middleware.BaseUrl, Pleroma.Config.get([Pleroma.Search.QdrantSearch, :url]))
  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Headers, [
    {"api-key", Pleroma.Config.get([Pleroma.Search.QdrantSearch, :api_key])}
  ])
end
