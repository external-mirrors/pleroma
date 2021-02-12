# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.HeifToJpeg do
  @behaviour Pleroma.Upload.Filter
  alias Pleroma.Upload
  alias Vix.Vips.Image

  @spec filter(Pleroma.Upload.t()) :: {:ok, :atom} | {:error, String.t()}
  def filter(
        %Pleroma.Upload{name: name, path: path, tempfile: tempfile, content_type: "image/heic"} =
          upload
      ) do
    try do
      name = name |> String.replace_suffix(".heic", ".jpg")
      path = path |> String.replace_suffix(".heic", ".jpg")
      convert(tempfile)

      {:ok, :filtered, %Upload{upload | name: name, path: path, content_type: "image/jpeg"}}
    rescue
      e in ErlangError ->
        {:error, "#{__MODULE__}: #{inspect(e)}"}
    end
  end

  def filter(_), do: {:ok, :noop}

  defp convert(tempfile) do
    new_file = "#{tempfile}.heic"

    with {:ok, image} <- Image.new_from_file(tempfile) do
      Image.write_to_stream(image, ".jpg")
      |> Stream.into(File.stream!(new_file))
      |> Stream.run()

      File.rename(new_file, tempfile)
    else
      _ -> raise("Error converting to JPEG with Vix")
    end
  end
end
