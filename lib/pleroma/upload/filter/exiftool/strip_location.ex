# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Upload.Filter.Exiftool.StripLocation do
  @moduledoc """
  Strips GPS related EXIF tags and overwrites the file in place.
  Also strips or replaces filesystem metadata e.g., timestamps.
  """
  @behaviour Pleroma.Upload.Filter

  # Formats not compatible with exiftool at this time
  def filter(%Pleroma.Upload{content_type: "image/heic"}), do: {:ok, :noop}
  def filter(%Pleroma.Upload{content_type: "image/webp"}), do: {:ok, :noop}
  def filter(%Pleroma.Upload{content_type: "image/svg" <> _}), do: {:ok, :noop}

  def filter(%Pleroma.Upload{tempfile: file, content_type: "image" <> _}) do
    case ExifGpsStripper.strip_gps_data(file, file) do
      :ok -> {:ok, :filtered}
      {:error, reason} -> {:error, reason}
    end
  end

  def filter(_), do: {:ok, :noop}
end

defmodule ExifGpsStripper do
  @exif_header <<0xFF, 0xE1>>
  @gps_ifd_tag 0x8825

  def strip_gps_data(input_path, output_path) do
    case File.read(input_path) do
      {:ok, data} ->
        case process_file(data) do
          {:ok, stripped_data} -> File.write(output_path, stripped_data)
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, "Failed to read file: #{reason}"}
    end
  end

  defp process_file(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, rest::binary>>) do
    # PNG file
    {:ok, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> strip_png_gps(rest)}
  end

  defp process_file(<<0xFF, 0xD8, rest::binary>>) do
    # JPEG file
    {:ok, <<0xFF, 0xD8>> <> strip_jpeg_gps(rest)}
  end

  defp process_file(_), do: {:error, "Unsupported file format"}

  defp strip_png_gps(data) do
    strip_png_chunks(data, [])
  end

  defp strip_png_chunks(<<>>, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp strip_png_chunks(
         <<chunk_size::32, chunk_type::binary-size(4), chunk_data::binary-size(chunk_size),
           crc::32, rest::binary>>,
         acc
       ) do
    case chunk_type do
      "GPS " ->
        strip_png_chunks(rest, acc)

      "gps " ->
        strip_png_chunks(rest, acc)

      "eXIf" ->
        strip_png_chunks(rest, acc)

      "tEXt" -> 
        strip_png_chunks(rest, acc)

      _ ->
        chunk =
          <<chunk_size::32, chunk_type::binary-size(4), chunk_data::binary-size(chunk_size),
            crc::32>>

        strip_png_chunks(rest, [chunk | acc])
    end
  end

  defp strip_jpeg_gps(data) do
    case :binary.match(data, @exif_header) do
      :nomatch ->
        data

      {pos, _} ->
        <<before::binary-size(pos), @exif_header, size::16, exif_data::binary-size(size - 2),
          rest::binary>> = data

        stripped_exif = strip_gps_from_exif(exif_data)
        new_size = byte_size(stripped_exif) + 2
        before <> @exif_header <> <<new_size::16>> <> stripped_exif <> rest
    end
  end

  defp strip_gps_from_exif(<<"Exif", 0, 0, tiff_header::binary-size(8), ifd_data::binary>>) do
    {stripped_ifd, _} = strip_gps_from_ifd(ifd_data)
    <<"Exif", 0, 0, tiff_header::binary-size(8), stripped_ifd::binary>>
  end

  defp strip_gps_from_ifd(<<count::16-little, rest::binary>>) do
    {entries, remaining} = strip_gps_from_entries(rest, count, [])
    {<<count::16-little>> <> IO.iodata_to_binary(entries), remaining}
  end

  defp strip_gps_from_entries(data, 0, acc), do: {Enum.reverse(acc), data}

  defp strip_gps_from_entries(
         <<tag::16-little, type::16-little, count::32-little, value::32-little, rest::binary>>,
         entries_left,
         acc
       ) do
    entry = <<tag::16-little, type::16-little, count::32-little, value::32-little>>

    if tag == @gps_ifd_tag do
      strip_gps_from_entries(rest, entries_left - 1, acc)
    else
      strip_gps_from_entries(rest, entries_left - 1, [entry | acc])
    end
  end
end
