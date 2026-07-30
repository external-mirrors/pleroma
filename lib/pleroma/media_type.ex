# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.MediaType do
  @sniff_bytes 8 * 1024

  @spec generic?(term()) :: boolean()
  def generic?(nil), do: true

  def generic?(media_type) when is_binary(media_type) do
    media_type
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in ["", "application/octet-stream"]))
  end

  def generic?(_), do: false

  @spec sniff_image(binary()) :: {:ok, String.t()} | :unknown
  def sniff_image(data) when is_binary(data) and data != "" do
    prefix = binary_part(data, 0, min(byte_size(data), @sniff_bytes)) |> :binary.copy()

    case Majic.perform({:bytes, prefix}, pool: Pleroma.MajicPool) do
      {:ok, %{mime_type: "image/" <> _ = mime_type}} -> {:ok, mime_type}
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  catch
    _, _ -> :unknown
  end

  def sniff_image(_), do: :unknown
end
