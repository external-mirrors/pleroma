# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.FrontendController do
  use Pleroma.Web, :controller

  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(Pleroma.Web.ApiSpec.CastAndValidate)
  plug(OAuthScopesPlug, %{scopes: ["admin:write"]} when action == :install)
  plug(OAuthScopesPlug, %{scopes: ["admin:read"]} when action == :index)
  action_fallback(Pleroma.Web.AdminAPI.FallbackController)

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.Admin.FrontendOperation

  def index(conn, _params) do
    frontends = Pleroma.Frontend.list()

    render(conn, "index.json", frontends: frontends)
  end

  def install(%{body_params: params} = conn, _params) do
    with :ok <- Pleroma.Frontend.install(params.name, Map.delete(params, :name)) do
      index(conn, %{})
    end
  end
end
