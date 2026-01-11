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
    if Pleroma.Utils.command_available?("exiftool") do
      strip_with_exiftool(file)
    else
      strip_with_elixir(file)
    end
  end

  def filter(_), do: {:ok, :noop}

  defp strip_with_exiftool(file) do
    try do
      case System.cmd("exiftool", ["-m", "-overwrite_original", "-gps:all=", "-png:all=", file],
             stderr_to_stdout: true,
             parallelism: true
           ) do
        {_response, 0} -> {:ok, :filtered}
        {error, _} -> {:error, error}
      end
    rescue
      e in ErlangError ->
        {:error, "#{__MODULE__}: #{inspect(e)}"}
    end
  end

  defp strip_with_elixir(file) do
    case ExifGpsStripper.strip_gps_data(file, file) do
      :ok -> {:ok, :filtered}
      :noop -> {:ok, :noop}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule ExifGpsStripper do
  @moduledoc false

  @gps_ifd_tag 0x8825

  @png_signature <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>
  @jpg_soi_marker <<0xFF, 0xD8>>

  @jpg_app1_marker 0xE1
  @jpg_sos_marker 0xDA
  @jpg_tem_marker 0x01

  @type result :: :ok | :noop | {:error, term()}

  @spec strip_gps_data(Path.t(), Path.t()) :: result()
  def strip_gps_data(input_path, output_path) do
    with {:ok, data} <- File.read(input_path),
         {:ok, stripped_data} <- process_file(data),
         :ok <- File.write(output_path, stripped_data) do
      :ok
    else
      :noop -> :noop
      {:error, _} = error -> error
    end
  rescue
    e ->
      {:error, "#{__MODULE__}: #{inspect(e)}"}
  end

  defp process_file(<<@png_signature, rest::binary>>) do
    case strip_png_chunks(rest, [], false) do
      {:ok, new_rest, true} -> {:ok, @png_signature <> new_rest}
      {:ok, _new_rest, false} -> :noop
      {:error, _} = error -> error
    end
  end

  defp process_file(<<@jpg_soi_marker, rest::binary>>) do
    case strip_jpeg_segments(rest, [], false) do
      {:ok, iodata, true} -> {:ok, @jpg_soi_marker <> IO.iodata_to_binary(iodata)}
      {:ok, _iodata, false} -> :noop
      {:error, _} = error -> error
    end
  end

  defp process_file(_), do: :noop

  defp strip_png_chunks(<<>>, acc, stripped?),
    do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), stripped?}

  defp strip_png_chunks(
         <<chunk_size::32, chunk_type::binary-size(4), chunk_data::binary-size(chunk_size),
           crc::32, rest::binary>>,
         acc,
         stripped?
       ) do
    if chunk_type in ["eXIf", "tEXt", "zTXt", "iTXt"] do
      strip_png_chunks(rest, acc, true)
    else
      chunk =
        <<chunk_size::32, chunk_type::binary-size(4), chunk_data::binary-size(chunk_size),
          crc::32>>

      strip_png_chunks(rest, [chunk | acc], stripped?)
    end
  end

  defp strip_png_chunks(_data, _acc, _stripped?), do: {:error, :invalid_png}

  defp strip_jpeg_segments(<<0xFF, @jpg_sos_marker, _::binary>> = data, acc, changed?) do
    {:ok, Enum.reverse([data | acc]), changed?}
  end

  defp strip_jpeg_segments(<<0xFF, 0xFF, rest::binary>>, acc, changed?) do
    strip_jpeg_segments(<<0xFF, rest::binary>>, acc, changed?)
  end

  defp strip_jpeg_segments(<<0xFF, @jpg_tem_marker, rest::binary>>, acc, changed?) do
    strip_jpeg_segments(rest, [<<0xFF, @jpg_tem_marker>> | acc], changed?)
  end

  defp strip_jpeg_segments(<<0xFF, marker, rest::binary>>, acc, changed?)
       when marker in 0xD0..0xD9 do
    strip_jpeg_segments(rest, [<<0xFF, marker>> | acc], changed?)
  end

  defp strip_jpeg_segments(<<0xFF, marker, segment_length::16, rest::binary>>, acc, changed?) do
    segment_data_len = segment_length - 2

    if segment_length >= 2 and byte_size(rest) >= segment_data_len do
      <<segment_data::binary-size(segment_data_len), remaining::binary>> = rest

      {segment_data, patched?} =
        if marker == @jpg_app1_marker do
          strip_gps_from_app1_segment(segment_data)
        else
          {segment_data, false}
        end

      segment = <<0xFF, marker, segment_length::16>> <> segment_data
      strip_jpeg_segments(remaining, [segment | acc], changed? or patched?)
    else
      {:error, :invalid_jpeg}
    end
  end

  defp strip_jpeg_segments(<<>>, acc, changed?), do: {:ok, Enum.reverse(acc), changed?}
  defp strip_jpeg_segments(_data, _acc, _changed?), do: {:error, :invalid_jpeg}

  defp strip_gps_from_app1_segment(<<"Exif", 0, 0, tiff::binary>> = segment_data) do
    case strip_gps_from_tiff(tiff) do
      {:ok, _tiff, false} -> {segment_data, false}
      {:ok, new_tiff, true} -> {<<"Exif", 0, 0>> <> new_tiff, true}
      {:error, _reason} -> {segment_data, false}
    end
  end

  defp strip_gps_from_app1_segment(segment_data), do: {segment_data, false}

  defp strip_gps_from_tiff(<<"II", 0x002A::16-little, ifd0_offset::32-little, _::binary>> = tiff) do
    strip_gps_from_ifd0(tiff, ifd0_offset, :little)
  end

  defp strip_gps_from_tiff(<<"MM", 0x002A::16-big, ifd0_offset::32-big, _::binary>> = tiff) do
    strip_gps_from_ifd0(tiff, ifd0_offset, :big)
  end

  defp strip_gps_from_tiff(_), do: {:error, :unsupported_tiff}

  defp strip_gps_from_ifd0(tiff, ifd0_offset, endian) do
    if byte_size(tiff) < ifd0_offset + 2 do
      {:error, :invalid_ifd0_offset}
    else
      <<before_ifd0::binary-size(ifd0_offset), ifd0::binary>> = tiff

      {entry_count, entry_count_bytes, ifd0_entries_and_rest} =
        case endian do
          :little ->
            <<count::16-little, rest::binary>> = ifd0
            {count, <<count::16-little>>, rest}

          :big ->
            <<count::16-big, rest::binary>> = ifd0
            {count, <<count::16-big>>, rest}
        end

      entries_len = entry_count * 12

      if byte_size(ifd0_entries_and_rest) < entries_len do
        {:error, :invalid_ifd0}
      else
        <<entries::binary-size(entries_len), rest_after_entries::binary>> = ifd0_entries_and_rest

        {patched_entries, patched?} = patch_ifd_entries(entries, endian, false, [])

        new_tiff = before_ifd0 <> entry_count_bytes <> patched_entries <> rest_after_entries
        {:ok, new_tiff, patched?}
      end
    end
  end

  defp patch_ifd_entries(<<>>, _endian, patched?, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), patched?}

  defp patch_ifd_entries(<<entry::binary-size(12), rest::binary>>, endian, patched?, acc) do
    tag =
      case endian do
        :little ->
          <<tag::16-little, _::binary-size(10)>> = entry
          tag

        :big ->
          <<tag::16-big, _::binary-size(10)>> = entry
          tag
      end

    if tag == @gps_ifd_tag do
      patch_ifd_entries(rest, endian, true, [<<0::size(12)-unit(8)>> | acc])
    else
      patch_ifd_entries(rest, endian, patched?, [entry | acc])
    end
  end
end
