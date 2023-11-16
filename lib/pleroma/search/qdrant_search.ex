defmodule Pleroma.Search.QdrantSearch do
  @behaviour Pleroma.Search.SearchBackend
  use GenServer
  import Ecto.Query
  alias Pleroma.Activity

  alias __MODULE__.HTTP
  import Pleroma.Search.Meilisearch, only: [object_to_search_data: 1]

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    payload = %{vectors: %{size: 384, distance: "Cosine"}}

    IO.inspect(payload)

    HTTP.put("/collections/posts", payload) |> IO.inspect()
    {:ok, nil, {:continue, :load_model}}
  end

  @impl true
  def handle_continue(:load_model, _state) do
    {:ok, model_info} =
      Bumblebee.load_model({:hf, "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"})

    {:ok, tokenizer} =
      Bumblebee.load_tokenizer(
        {:hf, "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"}
      )

    text_serving = Bumblebee.Text.text_embedding(model_info, tokenizer)

    {:noreply, text_serving}
  end

  def get_embedding(text) do
    %{embedding: embedding} = GenServer.call(__MODULE__, {:get_embedding, text})
    embedding |> Nx.to_list()
  end

  @impl true
  def handle_call({:get_embedding, text}, _, serving) do
    {:reply, Nx.Serving.run(serving, text), serving}
  end

  @impl true
  def add_to_index(activity) do
    maybe_search_data = object_to_search_data(activity.object)

    if activity.data["type"] == "Create" and maybe_search_data do
      payload = %{
        points: [
          %{
            id: activity.id |> FlakeId.from_string() |> Ecto.UUID.cast!() |> IO.inspect(),
            vector: get_embedding(maybe_search_data.content)
          }
        ]
      }

      with {:ok, %{status: 200}} <- HTTP.put("/collections/posts/points", payload) |> IO.inspect() do
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
      vector: get_embedding(query),
      limit: 20
    }

    with {:ok, %{body: %{"result" => result}}} <-
           HTTP.post("/collections/posts/points/search", payload) do
      ids =
        Enum.map(result, fn %{"id" => id} ->
          Ecto.UUID.dump!(id)
          |> FlakeId.to_string()
        end)

      from(a in Activity, where: a.id in ^ids)
      |> Activity.with_preloaded_object()
      |> Activity.restrict_deactivated_users()
      |> order_by([object: obj], desc: obj.data["published"])
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
end
