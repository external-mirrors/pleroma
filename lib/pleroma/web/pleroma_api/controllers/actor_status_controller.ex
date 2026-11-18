# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.ActorStatusController do
  use Pleroma.Web, :controller

  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(Pleroma.Web.ApiSpec.CastAndValidate)

  plug(OAuthScopesPlug, %{scopes: ["write:accounts"]})

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.PleromaActorStatusOperation

  def create(%{assigns: %{user: user}, body_params: %{content: content} = params} = conn, _) do
    # A create request with empty content is treated as a request to delete the current status.
    # Similar to how MastoAPI account notes work.
    if Pleroma.Config.get([:instance, :actor_statuses]) do
      res =
        case content do
          "" -> CommonAPI.delete_actor_status(user)
          _ -> CommonAPI.actor_status(user, params)
        end

      with {:ok, activity} <- res do
        render(conn, "show.json", activity: activity, for: user)
      else
        {:error, message} ->
          conn
          |> put_status(:bad_request)
          |> json(%{"error" => message})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{"error" => "Unsupported feature"})
    end
  end
end
