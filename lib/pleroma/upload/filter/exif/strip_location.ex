# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exif.StripLocation do
  @moduledoc """
  Strips GPS-related metadata and overwrites the file in place.

  This is a lossless operation (no re-encode) and relies on the `exif_stripper`
  package for container-specific parsing/patching.
  """

  @behaviour Pleroma.Upload.Filter

  def filter(%Pleroma.Upload{tempfile: file, content_type: "image" <> _}),
    do: strip(file)

  def filter(_), do: {:ok, :noop}

  defp strip(file) do
    case ExifStripper.GpsStripper.strip_gps_data(file, file) do
      :ok -> {:ok, :filtered}
      :noop -> {:ok, :noop}
      {:error, reason} -> {:error, reason}
    end
  end
end
