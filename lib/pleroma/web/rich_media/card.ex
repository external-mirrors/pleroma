defmodule Pleroma.Web.RichMedia.Card do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  use Nebulex.Caching

  alias Pleroma.Activity
  alias Pleroma.Cache
  alias Pleroma.HTML
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Web.RichMedia.Parser
  alias Pleroma.Workers.RichMediaWorker

  @config_impl Application.compile_env(:pleroma, [__MODULE__, :config_impl], Pleroma.Config)
  @nebulex Pleroma.Config.get([:nebulex, :provider], Cache)

  @type t :: %__MODULE__{}

  schema "rich_media_card" do
    field(:url_hash, :binary)
    field(:fields, :map)

    timestamps()
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [:url_hash, :fields])
    |> validate_required([:url_hash, :fields])
    |> unique_constraint(:url_hash)
  end

  @spec create(String.t(), map()) :: {:ok, t()}
  def create(url, fields) do
    url_hash = url_to_hash(url)

    fields = Map.put_new(fields, "url", url)

    %__MODULE__{}
    |> changeset(%{url_hash: url_hash, fields: fields})
    |> Repo.insert(on_conflict: {:replace, [:fields]}, conflict_target: :url_hash)
  end

  @spec delete(String.t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()} | :ok
  @decorate cache_evict(cache: @nebulex, key: {Card, url_to_hash(url)})
  def delete(url) do
    case get_by_url(url) do
      %__MODULE__{} = card -> Repo.delete(card)
      nil -> :ok
    end
  end

  @spec get_by_url(String.t() | nil) :: t() | nil | :error
  @decorate cacheable(
              cache: @nebulex,
              key: {Card, url_to_hash(url)},
              opts: [ttl: :timer.hours(12)]
            )
  def get_by_url(url) when is_binary(url) do
    host = URI.parse(url).host

    with true <- @config_impl.get([:rich_media, :enabled]),
         true <- host not in @config_impl.get([:rich_media, :ignore_hosts], []) do
      url_hash = url_to_hash(url)

      __MODULE__
      |> where(url_hash: ^url_hash)
      |> Repo.one()
    else
      false -> :error
    end
  end

  @spec get_or_backfill_by_url(String.t(), keyword()) :: t() | nil
  def get_or_backfill_by_url(url, opts \\ []) do
    host = URI.parse(url).host

    with true <- @config_impl.get([:rich_media, :enabled]),
         true <- host not in @config_impl.get([:rich_media, :ignore_hosts], []) do
      case get_by_url(url) do
        %__MODULE__{} = card ->
          card

        nil ->
          activity_id = Keyword.get(opts, :activity_id, nil)

          RichMediaWorker.new(%{"op" => "backfill", "url" => url, "activity_id" => activity_id})
          |> Oban.insert()

          nil

        :error ->
          nil
      end
    else
      false -> nil
    end
  end

  @spec get_by_object(Object.t()) :: t() | nil | :error
  def get_by_object(object) do
    case HTML.extract_first_external_url_from_object(object) do
      nil -> nil
      url -> get_or_backfill_by_url(url)
    end
  end

  @spec get_by_activity(Activity.t()) :: t() | nil | :error
  # Fake/Draft activity
  def get_by_activity(%Activity{id: "pleroma:fakeid"} = activity) do
    with {_, true} <- {:config, @config_impl.get([:rich_media, :enabled])},
         %Object{} = object <- Object.normalize(activity, fetch: false),
         url when not is_nil(url) <- HTML.extract_first_external_url_from_object(object) do
      case get_by_url(url) do
        # Cache hit
        %__MODULE__{} = card ->
          card

        # Cache miss, but fetch for rendering the Draft
        _ ->
          with {:ok, fields} <- Parser.parse(url),
               {:ok, card} <- create(url, fields) do
            card
          else
            _ -> nil
          end
      end
    else
      _ ->
        nil
    end
  end

  def get_by_activity(activity) do
    with %Object{} = object <- Object.normalize(activity, fetch: false),
         url when is_binary(url) <- HTML.extract_first_external_url_from_object(object) do
      get_or_backfill_by_url(url, activity_id: activity.id)
    else
      _ ->
        :error
    end
  end

  @spec url_to_hash(String.t()) :: String.t()
  def url_to_hash(url) do
    :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)
  end
end
