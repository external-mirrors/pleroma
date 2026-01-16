# Pleroma: A lightweight social networking server
# Copyright © Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exif.ReadDescription do
  @moduledoc """
  Reads a valid description from common metadata fields and sets it on the upload
  when no description is provided yet.

  The maximum description length is determined by `[:instance, :description_limit]`.
  """

  @behaviour Pleroma.Upload.Filter

  def filter(%Pleroma.Upload{description: description}) when is_binary(description),
    do: {:ok, :noop}

  def filter(%Pleroma.Upload{tempfile: file, content_type: "image" <> _} = upload) do
    description_limit = Pleroma.Config.get([:instance, :description_limit])

    description =
      ExifStripper.Description.read_file(file, max_length: description_limit)

    if is_binary(description) do
      {:ok, :filtered, %{upload | description: description}}
    else
      {:ok, :noop}
    end
  end

  def filter(_), do: {:ok, :noop}
end
