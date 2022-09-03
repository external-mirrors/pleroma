# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Streamer.Worker do
  use GenServer

  @pubsub Pleroma.PubSub
  @streamer_topic "streamer"

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, @streamer_topic)
    {:ok, []}
  end

  @impl true
  def handle_info({:stream, topics, items}, state) do
    Pleroma.Web.Streamer.exec_stream(topics, items)
    {:noreply, state}
  end

  @impl true
  def handle_call({:request_stream, topics, items}, _from, state) do
    Phoenix.PubSub.broadcast!(@pubsub, @streamer_topic, {:stream, topics, items})
    {:reply, :ok, state}
  end

  def request_stream(topics, items) do
    GenServer.call(__MODULE__, {:request_stream, topics, items})
  end
end
