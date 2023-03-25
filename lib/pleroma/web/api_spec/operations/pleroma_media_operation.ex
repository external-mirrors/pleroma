# Pleroma: A lightweight social networking server
# Copyright © 2017-2023 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.PleromaMediaOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema
  alias Pleroma.Web.ApiSpec.Schemas.ApiError
  alias Pleroma.Web.ApiSpec.Schemas.Attachment

  import Pleroma.Web.ApiSpec.Helpers

  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  @spec index_operation() :: Operation.t()
  def index_operation do
    %Operation{
      tags: ["Media attachments"],
      summary: "List media attachments",
      description: "List media attachments uploaded by the current user",
      operationId: "PleromaAPI.MediaController.index",
      parameters: pagination_params(),
      responses: %{
        200 => Operation.response("Array of media", "application/json", array_of_attachments()),
        403 => Operation.response("Forbidden", "application/json", ApiError)
      }
    }
  end

  def delete_operation do
    %Operation{
      tags: ["Media attachments"],
      summary: "Delete attachment",
      description: "Delete attachment",
      operationId: "PleromaAPI.MediaController.delete",
      parameters: [Operation.parameter(:id, :path, :integer, "Attachment id")],
      responses: %{
        200 =>
          Operation.response("Empty", "application/json", %Schema{type: :object, example: %{}}),
        404 => Operation.response("Not Found", "application/json", ApiError),
        500 => Operation.response("Internal Server Error", "application/json", ApiError)
      }
    }
  end

  defp array_of_attachments do
    %Schema{
      title: "ArrayOfAttachments",
      type: :array,
      items: Attachment,
      example: [Attachment.schema().example]
    }
  end
end
