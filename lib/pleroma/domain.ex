# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule Pleroma.Domain do
  @cachex Pleroma.Config.get([:cachex, :provider], Cachex)

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Pleroma.Repo

  @cache_key "domains_list"

  @domain_regex ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/

  schema "domains" do
    field(:domain, :string, default: "")
    field(:public, :boolean, default: false)
    field(:resolves, :boolean, default: false)
    field(:last_checked_at, :naive_datetime)

    has_many(:users, Pleroma.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(%__MODULE__{} = domain, params \\ %{}) do
    domain
    |> cast(params, [:domain, :public])
    |> validate_required([:domain])
    |> update_change(:domain, &String.downcase/1)
    |> validate_length(:domain, max: 255)
    |> validate_format(:domain, @domain_regex)
    |> unique_constraint(:domain)
  end

  def update_changeset(%__MODULE__{} = domain, params \\ %{}) do
    domain
    |> cast(params, [:public])
  end

  def update_state_changeset(%__MODULE__{} = domain, resolves) do
    domain
    |> cast(
      %{
        resolves: resolves,
        last_checked_at: NaiveDateTime.utc_now()
      },
      [:resolves, :last_checked_at]
    )
  end

  @doc "Normalizes an externally supplied domain id."
  @spec normalize_id(term()) :: {:ok, pos_integer() | nil} | :error
  def normalize_id(id) when id in [nil, "", 0], do: {:ok, nil}
  def normalize_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  def normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> normalize_id(parsed)
      _ -> :error
    end
  end

  def normalize_id(_), do: :error

  def list do
    __MODULE__
    |> order_by(asc: :id)
    |> Repo.all()
  end

  def get(id) do
    with {:ok, id} when not is_nil(id) <- normalize_id(id) do
      Repo.get(__MODULE__, id)
    else
      _ -> nil
    end
  end

  def get_by_name(domain) do
    __MODULE__
    |> where(domain: ^domain)
    |> Repo.one()
  end

  def cached_get_by_name(domain) when is_binary(domain) do
    domain = String.downcase(domain)

    Enum.find(cached_list(), &(&1.domain == domain))
  end

  def create(params) do
    with {:ok, domain} <-
           %__MODULE__{}
           |> changeset(params)
           |> Repo.insert() do
      invalidate_cache()

      {:ok, domain}
    end
  end

  def update(params, id) do
    with %__MODULE__{} = domain <- get(id),
         {:ok, domain} <- domain |> update_changeset(params) |> Repo.update() do
      invalidate_cache()

      {:ok, domain}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def delete(id) do
    with %__MODULE__{} = domain <- get(id),
         {:ok, domain} <-
           domain
           |> change()
           |> no_assoc_constraint(:users, message: "is used by existing accounts")
           |> Repo.delete() do
      invalidate_cache()

      {:ok, domain}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def cached_list do
    @cachex.fetch!(:domain_cache, @cache_key, fn _ -> list() end)
  end

  def invalidate_cache do
    @cachex.del(:domain_cache, @cache_key)
  end
end
