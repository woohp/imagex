defmodule Imagex.C do
  @moduledoc false

  use Expp, path: Application.app_dir(:imagex, "priv/imagex")

  @type decompress_ret_type ::
          {:ok,
           {binary(), integer(), integer(), integer(), integer(), binary() | nil,
            list({binary(), binary(), binary(), binary()}), list(binary()), list(binary())}}
          | {:error, String.t()}
  @type compress_ret_type :: {:ok, binary()} | {:error, String.t()}

  @spec jpeg_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def jpeg_decompress(_bytes, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec jpeg_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          {integer(), integer(), integer()} | nil,
          list(binary())
        ) ::
          compress_ret_type()
  def jpeg_compress(_pixels, _width, _height, _channels, _quality, _jfif_density, _app1_segments) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec png_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def png_decompress(_bytes, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec png_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          binary() | nil,
          list({binary(), binary(), binary(), binary()})
        ) ::
          compress_ret_type()
  def png_compress(_pixels, _width, _height, _channels, _bit_depth, _exif_binary, _png_texts) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec jxl_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def jxl_decompress(_bytes, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec jxl_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          list({binary(), binary()}),
          float(),
          boolean(),
          integer(),
          integer(),
          integer(),
          integer()
        ) ::
          compress_ret_type()
  def jxl_compress(
        _pixels,
        _width,
        _height,
        _channels,
        _bit_depth,
        _jxl_boxes,
        _distance,
        _lossless,
        _effort,
        _progressive,
        _order,
        _orientation
      ) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec jxl_transcode_from_jpeg(binary(), integer(), boolean(), non_neg_integer()) ::
          {:ok, binary()} | {:error, String.t()}
  def jxl_transcode_from_jpeg(_jpeg_bytes, _effort, _store_jpeg_metadata, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec jxl_transcode_to_jpeg(binary(), non_neg_integer()) :: {:ok, binary()} | {:error, String.t()}
  def jxl_transcode_to_jpeg(_jxl_bytes, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec pdf_load_document(binary()) :: {:ok, {reference(), integer()}} | {:error, String.t()}
  def pdf_load_document(_bytes) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec pdf_render_page(reference(), integer(), integer(), non_neg_integer()) :: decompress_ret_type()
  def pdf_render_page(_document, _page_idx, _dpi, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec tiff_load_document(binary()) :: {:ok, {reference(), integer()}} | {:error, String.t()}
  def tiff_load_document(_bytes) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec tiff_render_page(reference(), integer(), non_neg_integer()) :: decompress_ret_type()
  def tiff_render_page(_document, _page_idx, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec webp_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def webp_decompress(_bytes, _max_pixels) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @spec webp_compress(binary(), integer(), integer(), integer(), float(), boolean(), integer()) :: compress_ret_type()
  def webp_compress(_pixels, _width, _height, _channels, _quality, _lossless, _effort) do
    :erlang.nif_error(:nif_library_not_loaded)
  end
end
