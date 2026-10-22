defmodule Imagex.Jfif do
  @moduledoc false

  # Reference:
  # https://metacpan.org/dist/Image-MetaData-JPEG/view/lib/Image/MetaData/JPEG/Structures.pod#Structure-of-a-JFIF-APP0-segment

  @jpeg_start_of_image 0xFFD8
  @jpeg_app1_xmp_identifier "http://ns.adobe.com/xap/1.0/\0"

  def read_metadata_from_jpeg(<<@jpeg_start_of_image::16, rest::binary>>) do
    metadata = read_segments(rest, %{})
    if metadata == %{}, do: nil, else: metadata
  end

  def read_metadata_from_jpeg(_bytes), do: nil

  # Walk the marker segments up to the start of scan, skipping ones we don't parse.
  defp read_segments(<<0xFF, 0xFF, rest::binary>>, metadata), do: read_segments(<<0xFF, rest::binary>>, metadata)

  defp read_segments(<<0xFF, marker, len::16, rest::binary>>, metadata) when marker not in [0xD9, 0xDA] do
    payload_length = len - 2

    case rest do
      <<payload::binary-size(^payload_length), remaining::binary>> ->
        read_segments(remaining, merge_metadata(metadata, parse_segment(marker, payload)))

      _ ->
        metadata
    end
  end

  defp read_segments(_bytes, metadata), do: metadata

  defp parse_segment(0xE0, payload), do: parse_jfif(payload)
  defp parse_segment(0xE1, payload), do: parse_app1(payload)
  defp parse_segment(_marker, _payload), do: nil

  defp parse_app1(<<"Exif", 0::16, app1_data::binary>>) do
    Imagex.Exif.read_exif_from_tiff(app1_data)
  end

  defp parse_app1(<<@jpeg_app1_xmp_identifier, xmp::binary>>) do
    %{xmp: xmp}
  end

  defp parse_app1(_), do: nil

  defp merge_metadata(metadata, nil), do: metadata

  defp merge_metadata(metadata, new_metadata) do
    cond do
      Map.has_key?(metadata, :jfif) and Map.has_key?(new_metadata, :jfif) ->
        {jfif1, metadata} = Map.pop(metadata, :jfif)
        {jfif2, new_metadata} = Map.pop(new_metadata, :jfif)
        Map.merge(Map.merge(metadata, new_metadata), %{jfif: Map.merge(jfif1, jfif2)})

      true ->
        Map.merge(metadata, new_metadata)
    end
  end

  defp parse_jfif(
         <<"JFIF\0"::binary, version_major::8, version_minor::8, density_units::8, density_x::16, density_y::16,
           thumbnail_width::8, thumbnail_height::8, thumbnail_data::binary>> = _app0_data
       ) do
    # TODO: should we validate whether the size of thumbnail_data = thumbnail_width * thumbnail_height * 3?

    %{
      jfif: %{
        version_major: version_major,
        version_minor: version_minor,
        density_units: density_units,
        density_x: density_x,
        density_y: density_y,
        thumbnail_width: thumbnail_width,
        thumbnail_height: thumbnail_height,
        thumbnail_data: thumbnail_data
      }
    }
  end

  # JFXX extension thumbnails: 0x10 is a complete JPEG stream, 0x11 is palettized, 0x12 is RGB.
  defp parse_jfif(<<"JFXX\0", 0x10, thumbnail_data::binary>>) do
    %{jfif: %{thumbnail_format: 0x10, thumbnail_data: thumbnail_data}}
  end

  defp parse_jfif(<<"JFXX\0", 0x11, width, height, palette::binary-size(768), thumbnail_data::binary>>) do
    %{
      jfif: %{
        thumbnail_format: 0x11,
        thumbnail_width: width,
        thumbnail_height: height,
        thumbnail_palette: palette,
        thumbnail_data: thumbnail_data
      }
    }
  end

  defp parse_jfif(<<"JFXX\0", 0x12, width, height, thumbnail_data::binary>>) do
    %{jfif: %{thumbnail_format: 0x12, thumbnail_width: width, thumbnail_height: height, thumbnail_data: thumbnail_data}}
  end

  defp parse_jfif(_app0_data), do: nil
end
