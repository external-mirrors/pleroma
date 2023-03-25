# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.MediaController do
  use Pleroma.Web, :controller

  require Pleroma.Constants

  alias Pleroma.Object
  alias Pleroma.UploadedFile
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
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
  def delete(%{assigns: %{user: user}} = conn, %{id: id} = _params) do
    with {_, %Object{data: %{"actor" => _actor}} = object} <- {:object, Object.get_by_id(id)},
         {_, true} <- {:object, object.data["type"] in Pleroma.Constants.upload_object_types()},
         {_, :ok} <- {:object, Object.authorize_access(object, user)},
         {_, %UploadedFile{} = uploaded_file} <-
           {:uploaded_file, UploadedFile.get_by_object(object)},
         {:delete, :ok} <- {:delete, ActivityPub.delete_upload(uploaded_file)} do
      conn
      |> ControllerHelper.json_response(200, %{})
    else
      {:object, _} ->
        render_error(conn, :not_found, "Attachment does not exist")

      {:uploaded_file, _} ->
        render_error(conn, :internal_server_error, "Unable to delete")

      {:delete, _} ->
        render_error(conn, :internal_server_error, "Unable to delete")
    end
  end
end
