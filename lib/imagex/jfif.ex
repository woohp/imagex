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
          {%{}, nil}
      end

    if is_nil(rest) do
      metadata
    else
      Map.merge(metadata, read_metadata_from_jpeg_impl(rest))
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
        10 ->
          thumbnail_data_size = byte_size(rest) - 4
          <<0xFFD8::16, thumbnail_data::binary-size(thumbnail_data_size), 0xFFD9::16>> = rest
          %{thumbnail_format: thumbnail_format, thumbnail_data: thumbnail_data}

        11 ->
          <<thumbnail_width::8, thumbnail_height::8, thumbnail_palette::binary-size(768), thumbnail_data::binary>> =
            rest

          %{
            thumbnail_format: thumbnail_format,
            thumbnail_width: thumbnail_width,
            thumbnail_height: thumbnail_height,
            thumbnail_palette: thumbnail_palette,
            thumbnail_data: thumbnail_data
          }

        12 ->
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
end
