# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.CheckDomainResolveWorker do
  use Oban.Worker, queue: :background

  alias Pleroma.Domain
  alias Pleroma.HTTP
  alias Pleroma.Repo
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.WebFinger

  @impl Oban.Worker
  def perform(%Job{args: %{"id" => domain_id}}) do
    case Domain.get(domain_id) do
      %Domain{} = domain ->
        domain
        |> Domain.update_state_changeset(resolves?(domain))
        |> Repo.update()

      nil ->
        :ok
    end
  end

  defp resolves?(%Domain{domain: domain}) do
    with {:ok, %Tesla.Env{status: status, body: hostmeta_body}} when status in 200..299 <-
           HTTP.get("https://" <> domain <> "/.well-known/host-meta"),
         {:ok, template} <- WebFinger.get_template_from_xml(hostmeta_body),
         base_url <- Endpoint.url(),
         true <- template == "#{base_url}/.well-known/webfinger?resource={uri}" do
      true
    else
      _ -> false
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(15)
end
