# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.DomainController do
  use Pleroma.Web, :controller

  alias Pleroma.Domain
  alias Pleroma.Web.AdminAPI
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(Pleroma.Web.ApiSpec.CastAndValidate)

  plug(
    OAuthScopesPlug,
    %{scopes: ["admin:write"]}
    when action in [:create, :update, :delete]
  )

  plug(OAuthScopesPlug, %{scopes: ["admin:read"]} when action == :index)

  action_fallback(AdminAPI.FallbackController)

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.Admin.DomainOperation

  def index(conn, _) do
    domains = Domain.list()

    render(conn, "index.json", domains: domains, admin: true)
  end

  def create(%{body_params: params} = conn, _) do
    with {:domain_not_used, true} <- {:domain_not_used, not_restricted_domain?(params[:domain])},
         {:ok, domain} <- Domain.create(params) do
      Pleroma.Workers.CheckDomainResolveWorker.new(%{
        "op" => "check_domain_resolve",
        "id" => domain.id
      })
      |> Oban.insert()

      render(conn, "show.json", domain: domain, admin: true)
    else
      {:domain_not_used, false} ->
        {:error, :invalid_domain}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:errors, changeset_errors(changeset)}
    end
  end

  def update(%{body_params: params} = conn, %{id: id}) do
    with {:ok, domain} <- Domain.update(params, id) do
      render(conn, "show.json", domain: domain, admin: true)
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:errors, changeset_errors(changeset)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def delete(conn, %{id: id}) do
    with {:ok, _} <- Domain.delete(id) do
      json(conn, %{})
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:errors, changeset_errors(changeset)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp not_restricted_domain?(nil), do: false

  defp not_restricted_domain?(domain) do
    String.downcase(domain) not in [
      String.downcase(Pleroma.Web.WebFinger.host()),
      String.downcase(Pleroma.Web.Endpoint.host())
    ]
  end

  defp changeset_errors(%Ecto.Changeset{errors: errors}) do
    Map.new(errors, fn {key, {message, _opts}} -> {key, message} end)
  end
end
