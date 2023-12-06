# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.ReceiverWorker do
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.Federator

  use Pleroma.Workers.WorkerHelper, queue: "federator_incoming"

  @impl Oban.Worker
  def perform(%Job{
        args: %{"op" => "incoming_ap_doc", "conn" => conn = %{params: %{"nickname" => nickname}}}
      }) do
    with {:signature, true} <- {:signature, HTTPSignatures.validate_conn(conn)},
         {:nickname, %User{} = recipient} <- {:nickname, User.get_cached_by_nickname(nickname)},
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(conn.params["actor"]),
         {:in_message, true} <-
           {:in_message, Utils.recipient_in_message(recipient, actor, conn.params)},
         split_params <- Utils.maybe_splice_recipient(recipient.ap_id, conn.params),
         {:ok, res} <- Federator.perform(:incoming_ap_doc, split_params) do
      {:ok, res}
    else
      e -> process_errors(e)
    end
  end

  def perform(%Job{args: %{"op" => "incoming_ap_doc", "conn" => conn}}) do
    with {:signature, true} <- {:signature, HTTPSignatures.validate_conn(conn)},
         {:ok, res} <- Federator.perform(:incoming_ap_doc, conn.params) do
      {:ok, res}
    else
      e -> process_errors(e)
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)

  defp process_errors(errors) do
    case errors do
      {:error, :origin_containment_failed} -> {:cancel, :origin_containment_failed}
      {:error, :already_present} -> {:cancel, :already_present}
      {:error, {:validate_object, reason}} -> {:cancel, reason}
      {:error, {:error, {:validate, reason}}} -> {:cancel, reason}
      {:error, {:reject, reason}} -> {:cancel, reason}
      {:signature, false} -> {:cancel, :invalid_signature}
      {:nickname, {:error, reason}} -> {:cancel, reason}
      {:in_message, false} -> {:cancel, "Recipient not in message"}
      e -> e
    end
  end
end
