# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.MediaController do
  use Pleroma.Web, :controller

  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  action_fallback(Pleroma.Web.MastodonAPI.FallbackController)
  plug(Majic.Plug, [pool: Pleroma.MajicPool] when action in [:create, :create2])
  plug(Pleroma.Web.ApiSpec.CastAndValidate, replace_params: false)

  plug(OAuthScopesPlug, %{scopes: ["read:media"]} when action == :show)
  plug(OAuthScopesPlug, %{scopes: ["write:media"]} when action != :show)

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.MediaOperation

  @doc "POST /api/v1/media"
  def create(
        %{assigns: %{user: user}, private: %{open_api_spex: %{body_params: %{file: file} = data}}} =
          conn,
        _
      ) do
    with {:ok, object} <-
           ActivityPub.upload(
             file,
             actor: User.ap_id(user),
             description: Map.get(data, :description)
           ) do
      attachment_data = Map.put(object.data, "id", object.id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  def create(_conn, _data), do: {:error, :bad_request}

  @doc "POST /api/v2/media"
  def create2(
        %{assigns: %{user: user}, private: %{open_api_spex: %{body_params: %{file: file} = data}}} =
          conn,
        _
      ) do
    with {:ok, object} <-
           ActivityPub.upload(
             file,
             actor: User.ap_id(user),
             description: Map.get(data, :description)
           ) do
      attachment_data = Map.put(object.data, "id", object.id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  def create2(_conn, _data), do: {:error, :bad_request}

  @doc "PUT /api/v1/media/:id"
  def update(
        %{
          assigns: %{user: user},
          private: %{
            open_api_spex: %{body_params: %{description: description}, params: %{id: id}}
          }
        } = conn,
        _
      ) do
    with %Object{} = object <- Object.get_by_id(id),
         :ok <- Object.authorize_access(object, user),
         {:ok, %Object{data: data}} <- Object.update_data(object, %{"name" => description}) do
      attachment_data = Map.put(data, "id", object.id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  @doc "DELETE /api/v1/media/:id"
  def delete(
        %{
          assigns: %{user: user},
          private: %{open_api_spex: %{params: %{id: id}}}
        } = conn,
        _
      ) do
    with {:is_attachment, %Object{data: %{"type" => "Document", "mediaType" => _}} = object} <-
           {:is_attachment, Object.get_by_id(id)},
         {:auth, :ok} <- {:auth, Object.authorize_access(object, user)},
         href <- object.data["url"] |> List.first() |> Map.get("href"),
         {:used, []} <- {:used, Pleroma.Upload.list_objects_with_attachment(href)},
         {:ok, _, _} <- Object.delete(object) do
      conn
      |> put_resp_header("content-type", "text/plain")
      |> send_resp(200, "")
    else
      {:used, list} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Refusing to delete attachment that is still used by #{Enum.count(list)} objects"
        })

      {:is_attachment, _} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Refusing to delete an object that is not an attachment"})

      {:auth, _} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to delete the attachment"})

      e ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: e})
    end
  end

  def update(conn, data), do: show(conn, data)

  @doc "GET /api/v1/media/:id"
  def show(%{assigns: %{user: user}, private: %{open_api_spex: %{params: %{id: id}}}} = conn, _) do
    with %Object{data: data, id: object_id} = object <- Object.get_by_id(id),
         :ok <- Object.authorize_access(object, user) do
      attachment_data = Map.put(data, "id", object_id)

      render(conn, "attachment.json", %{attachment: attachment_data})
    end
  end

  def show(_conn, _data), do: {:error, :bad_request}
end
