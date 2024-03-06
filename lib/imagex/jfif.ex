defmodule Imagex.Jfif do
  @moduledoc """
  Provides functions for reading JFIF APP0 tags.

  Reference:
  https://metacpan.org/dist/Image-MetaData-JPEG/view/lib/Image/MetaData/JPEG/Structures.pod#Structure-of-a-JFIF-APP0-segment
  """

  @jpeg_start_of_image 0xFFD8

  def read_metadata_from_jpeg(bytes) when is_binary(bytes) do
    <<@jpeg_start_of_image::16, rest::binary>> = bytes
    read_metadata_from_jpeg_impl(rest)
  end

  defp read_metadata_from_jpeg_impl(bytes) do
    {metadata, rest} =
      case bytes do
        <<0xFFE0::16, len::16-big, rest::binary>> ->
          len = len - 2
          <<app0_data::binary-size(len), rest::binary>> = rest
          {parse_jfif(app0_data), rest}

        <<0xFFE1::16, app1_data_length::16-big, "Exif"::binary, 0::16, app1_data::binary>> ->
          <<app1_data::binary-size(app1_data_length), rest::binary>> = app1_data
          {Imagex.Exif.read_exif_from_tiff(app1_data), rest}

        _ ->
          {nil, nil}
      end

    if is_nil(metadata) do
      nil
    else
      rest_metadata = read_metadata_from_jpeg_impl(rest)

      cond do
        is_nil(rest_metadata) ->
          metadata

        # recursively merge the jfif metadata, if necessary
        Map.has_key?(rest_metadata, :jfif) and Map.has_key?(metadata, :jfif) ->
          {jfif1, metadata} = Map.pop(metadata, :jfif)
          {jfif2, rest_metadata} = Map.pop(rest_metadata, :jfif)
          Map.merge(Map.merge(metadata, rest_metadata), %{jfif: Map.merge(jfif1, jfif2)})

        true ->
          Map.merge(metadata, rest_metadata)
      end
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
