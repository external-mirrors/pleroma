# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Stats do
  use GenServer

  import Ecto.Query

  alias Pleroma.CounterCache
  alias Pleroma.Repo
  alias Pleroma.User

  require Logger

  @interval :timer.seconds(60)

  def start_link(_) do
    GenServer.start_link(
      __MODULE__,
      nil,
      name: __MODULE__
    )
  end

  @impl true
  def init(_args) do
    if Pleroma.Config.get(:env) != :test do
      {:ok, nil, {:continue, :calculate_stats}}
    else
      {:ok, calculate_stat_data()}
    end
  end

  @doc "Performs update stats"
  def force_update do
    GenServer.call(__MODULE__, :force_update)
  end

  @doc "Returns stats data"
  @spec get_stats() :: %{
          domain_count: non_neg_integer(),
          status_count: non_neg_integer(),
          user_count: non_neg_integer()
        }
  def get_stats do
    %{stats: stats} = GenServer.call(__MODULE__, :get_state)

    stats
  end

  @doc "Returns list peers"
  @spec get_peers() :: list(String.t())
  def get_peers do
    %{peers: peers} = GenServer.call(__MODULE__, :get_state)

    peers
  end

  @doc "Returns Oban queue counts for available, executing, and retryable states"
  @spec get_oban() :: map()
  def get_oban do
    %{oban: oban_counts} = GenServer.call(__MODULE__, :get_state)

    oban_counts
  end

  @spec calculate_stat_data() :: %{
          peers: list(),
          stats: %{
            domain_count: non_neg_integer(),
            status_count: non_neg_integer(),
            user_count: non_neg_integer()
          }
        }
  @doc """
  Calculates stat data and exports some metrics through telemetry.

  Executes automatically on a 60 second interval by default.
  """
  def calculate_stat_data do
    peers =
      from(
        u in User,
        select: fragment("distinct split_part(?, '@', 2)", u.nickname),
        where: u.local != ^true
      )
      |> Repo.all()
      |> Enum.filter(& &1)

    domain_count = Enum.count(peers)

    status_count = Repo.aggregate(User.Query.build(%{local: true}), :sum, :note_count)

    users_query =
      from(u in User,
        where: u.is_active == true,
        where: u.local == true,
        where: not is_nil(u.nickname),
        where: not u.invisible
      )

    user_count = Repo.aggregate(users_query, :count, :id)

    # Logs Oban counts
    get_oban_counts()

    # Logs / Telemetry for local visibility counts
    get_status_visibility_count()

    # Telemetry for local stats
    %{domains: domain_count, notes: status_count, users: user_count}
    |> Enum.each(fn {k, v} ->
      :telemetry.execute(
        [:pleroma, :stats, :local, k],
        %{count: v}
      )
    end)

    %{
      peers: peers,
      stats: %{
        domain_count: domain_count,
        status_count: status_count || 0,
        user_count: user_count
      }
    }
  end

  @spec get_status_visibility_count :: map()
  def get_status_visibility_count do
    result = CounterCache.get_sum()

    Enum.each(result, fn {k, v} ->
      :telemetry.execute(
        [:pleroma, :stats, :global, :activities],
        %{count: v},
        %{visibility: k}
      )
    end)

    result
  end

  @impl true
  def handle_continue(:calculate_stats, _) do
    stats = calculate_stat_data()

    unless Pleroma.Config.get(:env) == :test do
      Process.send_after(self(), :run_update, @interval)
    end

    {:noreply, stats}
  end

  @impl true
  def handle_call(:force_update, _from, _state) do
    new_stats = calculate_stat_data()
    {:reply, new_stats, new_stats}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:run_update, _) do
    new_stats = calculate_stat_data()
    Process.send_after(self(), :run_update, @interval)
    {:noreply, new_stats}
  end

  def get_oban_counts do
    result =
      from(j in Oban.Job,
        where: j.state in ^["executing", "available", "retryable"],
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )
      |> Pleroma.Repo.all()
      |> Enum.group_by(fn {key, _, _} -> key end)
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        queues = Map.new(v, fn {_, state, count} -> {state, count} end)

        Map.put(acc, k, queues)
      end)

    for {queue, states} <- result do
      queue_text =
        for {state, count} <- states do
          "#{state}: #{count}"
        end
        |> Enum.join(" || ")

      Logger.info("Oban Queue Stats for :#{queue} || #{queue_text}")
    end

    result
  end
end
