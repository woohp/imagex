defmodule Imagex.Jfif do
  @moduledoc """
  Provides functions for reading JFIF APP0 tags.

  Reference:
  https://metacpan.org/dist/Image-MetaData-JPEG/view/lib/Image/MetaData/JPEG/Structures.pod#Structure-of-a-JFIF-APP0-segment
  """

  @jpeg_start_of_image 0xFFD8
  @jpeg_app1_xmp_identifier "http://ns.adobe.com/xap/1.0/\0"

  def read_metadata_from_jpeg(bytes) when is_binary(bytes) do
    case bytes do
      <<@jpeg_start_of_image::16, rest::binary>> ->
        read_metadata_from_jpeg_impl(rest, %{})

      _ ->
        nil
    end
  end

  defp read_metadata_from_jpeg_impl(<<>>, metadata), do: blank_to_nil(metadata)

  defp read_metadata_from_jpeg_impl(<<0xFFE0::16, len::16-big, rest::binary>>, metadata) do
    payload_length = len - 2

    case rest do
      <<payload::binary-size(payload_length), remaining::binary>> ->
        case parse_jfif(payload) do
          nil -> blank_to_nil(metadata)
          app0_metadata -> read_metadata_from_jpeg_impl(remaining, merge_metadata(metadata, app0_metadata))
        end

      _ ->
        blank_to_nil(metadata)
    end
  end

  defp read_metadata_from_jpeg_impl(<<0xFFE1::16, len::16-big, rest::binary>>, metadata) do
    payload_length = len - 2

    case rest do
      <<payload::binary-size(payload_length), remaining::binary>> ->
        case parse_app1(payload) do
          nil -> blank_to_nil(metadata)
          app1_metadata -> read_metadata_from_jpeg_impl(remaining, merge_metadata(metadata, app1_metadata))
        end

      _ ->
        blank_to_nil(metadata)
    end
  end

  defp read_metadata_from_jpeg_impl(_, metadata), do: blank_to_nil(metadata)

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

  defp blank_to_nil(metadata) when metadata == %{}, do: nil
  defp blank_to_nil(metadata), do: metadata

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

  defp parse_jfif(<<"JFXX\0"::binary, thumbnail_format::8, rest::binary>> = _app0_data) do
    out =
      case thumbnail_format do
        0x10 ->
          # TODO: doesn't seem to be quite working yet...
          # thumbnail_data_size = byte_size(rest) - 4
          %{thumbnail_format: thumbnail_format, thumbnail_data: :not_working_yet}

        0x11 ->
          <<thumbnail_width::8, thumbnail_height::8, thumbnail_palette::binary-size(768), thumbnail_data::binary>> =
            rest

          %{
            thumbnail_format: thumbnail_format,
            thumbnail_width: thumbnail_width,
            thumbnail_height: thumbnail_height,
            thumbnail_palette: thumbnail_palette,
            thumbnail_data: thumbnail_data
          }

        0x12 ->
          <<thumbnail_width::8, thumbnail_height::8, thumbnail_data::binary>> = rest

          %{
            thumbnail_format: thumbnail_format,
            thumbnail_width: thumbnail_width,
            thumbnail_height: thumbnail_height,
            thumbnail_data: thumbnail_data
          }
      end

    %{jfif: out}
  end

  defp parse_jfif(_) do
    nil
  end
end
