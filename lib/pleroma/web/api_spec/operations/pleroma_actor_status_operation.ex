# Pleroma: A lightweight social networking server
# Copyright © 2017-2026 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.PleromaActorStatusOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema
  alias Pleroma.Web.ApiSpec.Schemas.Account
  alias Pleroma.Web.ApiSpec.Schemas.ApiError

  import Pleroma.Web.ApiSpec.Helpers

  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  def create_operation do
    %Operation{
      tags: ["Actor Statuses"],
      summary: "Creates a new Create activity with an Actor Status for an account",
      security: [%{"oAuth" => ["write:accounts"]}],
      operationId: "PleromaAPI.ActorStatusController.create",
      deprecated: false,
      requestBody: request_body("Parameters", create_request(), required: true),
      responses: %{
        200 => Operation.response("Scrobble", "application/json", actor_status()),
        400 => Operation.response("Error", "application/json", ApiError)
      }
    }
  end

  defp create_request do
    %Schema{
      type: :object,
      required: [:content],
      properties: %{
        content: %Schema{type: :string, description: "Text content of the Actor Status"}
      },
      example: %{
        "content" => "No matter where you are, everybody's connected."
      }
    }
  end

  defp actor_status do
    %Schema{
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        account: Account,
        created_at: %Schema{type: :string, format: :"date-time"},
        actor_status: %Schema{
          type: :object,
          properties: %{
            content: %Schema{type: :string}
          }
        }
      },
      example: %{
        "id" => "1234",
        "account" => Account.schema().example,
        "created_at" => "1998-07-06T12:40:45.000Z",
        "actor_status" => %{
          "content" => "No matter where you are, everybody's connected.",
          "raw_content" => "No matter where you are, everybody's connected.",
          "emojis" => []
        }
      }
    }
  end
end
