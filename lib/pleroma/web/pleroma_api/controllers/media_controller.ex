# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.MediaController do
  use Pleroma.Web, :controller

  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ControllerHelper
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(Pleroma.Web.ApiSpec.CastAndValidate)

  plug(
    OAuthScopesPlug,
    %{scopes: ["read:media"]} when action == :index
  )

  plug(
    OAuthScopesPlug,
    %{scopes: ["write:media"]} when action == :delete
  )

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.PleromaMediaOperation

  @doc "GET /api/v1/pleroma/media"
  def index(%{assigns: %{user: %User{} = user}} = conn, params) do
    media =
      user
      |> Object.uploads_by_user_query()
      |> Pleroma.Pagination.fetch_paginated(params)

    conn
    |> ControllerHelper.add_link_headers(media)
    |> render("index.json", %{media: media, for: user})
  end

  @doc "DELETE /api/v1/pleroma/media/:id"
  def delete(%{assigns: %{user: _user}} = conn, _) do
    conn
  end
end
