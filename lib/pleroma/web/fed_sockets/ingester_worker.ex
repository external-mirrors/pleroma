# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.FedSockets.IngesterWorker do
  use Pleroma.Workers.WorkerHelper, queue: "ingestion_queue"
  require Logger

  alias Pleroma.Object.Fetcher
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.Federator

  @impl Oban.Worker
  def perform(%{"op" => "ingest", "object" => ingestee}, _job) do
    try do
      ingestee
      |> Jason.decode!()
      |> do_ingestion()
    rescue
      e ->
        Logger.error("IngesterWorker error - #{inspect(e)}")
        e
    end
  end

  defp do_ingestion(%{"nickname" => nickname} = params) do
    with %User{} = recipient <- User.get_cached_by_nickname(nickname),
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(params["actor"]),
         true <- Utils.recipient_in_message(recipient, actor, params),
         params <- Utils.maybe_splice_recipient(recipient.ap_id, params) do
      case Federator.incoming_ap_doc(params) do
        {:error, reason} ->
          {:error, reason}

        {:ok, object} ->
          {:ok, object}
      end
    end
  end

  defp do_ingestion(%{"type" => "Create", "object" => %{"id" => object_id}}) do
    case Fetcher.fetch_object_from_id(object_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, object} ->
        {:ok, object}
    end
  end

  defp do_ingestion(params) do
    case Federator.incoming_ap_doc(params) do
      {:error, reason} ->
        {:error, reason}

      {:ok, object} ->
        {:ok, object}
    end
  end
end
