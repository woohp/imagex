defmodule Imagex.C do
  @moduledoc false

  use Expp, path: Application.app_dir(:imagex, "priv/imagex")

  # Dialyzer suppressions for NIF stub functions that call exit()
  @dialyzer {:nowarn_function, jpeg_decompress: 2}
  @dialyzer {:nowarn_function, jpeg_compress: 8}
  @dialyzer {:nowarn_function, png_decompress: 2}
  @dialyzer {:nowarn_function, png_compress: 7}
  @dialyzer {:nowarn_function, jxl_decompress: 2}
  @dialyzer {:nowarn_function, jxl_compress: 13}
  @dialyzer {:nowarn_function, jxl_transcode_from_jpeg: 3}
  @dialyzer {:nowarn_function, jxl_transcode_to_jpeg: 1}
  @dialyzer {:nowarn_function, pdf_load_document: 1}
  @dialyzer {:nowarn_function, pdf_render_page: 4}
  @dialyzer {:nowarn_function, tiff_load_document: 1}
  @dialyzer {:nowarn_function, tiff_render_page: 3}
  @dialyzer {:nowarn_function, webp_decompress: 2}
  @dialyzer {:nowarn_function, webp_compress: 7}

  @type decompress_ret_type ::
          {:ok,
           {binary(), integer(), integer(), integer(), integer(), binary() | nil,
            list({binary(), binary(), binary(), binary()}), list(binary()), list(binary())}}
          | {:error, String.t()}
  @type compress_ret_type :: {:ok, binary()} | {:error, String.t()}

  @spec jpeg_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def jpeg_decompress(_bytes, _max_pixels) do
    exit(:nif_library_not_loaded)
  end

  @spec jpeg_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          {integer(), integer(), integer()} | nil,
          binary() | nil,
          binary() | nil
        ) ::
          compress_ret_type()
  def jpeg_compress(_pixels, _width, _height, _channels, _quality, _jfif_density, _exif_binary, _xmp_binary) do
    exit(:nif_library_not_loaded)
  end

  @spec png_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def png_decompress(_bytes, _max_pixels) do
    exit(:nif_library_not_loaded)
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
    exit(:nif_library_not_loaded)
  end

  @spec jxl_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def jxl_decompress(_bytes, _max_pixels) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          binary() | nil,
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
        _exif_binary,
        _jxl_boxes,
        _distance,
        _lossless,
        _effort,
        _progressive,
        _order,
        _orientation
      ) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_transcode_from_jpeg(binary(), integer(), boolean()) :: {:ok, binary()} | {:error, String.t()}
  def jxl_transcode_from_jpeg(_jpeg_bytes, _effort, _store_jpeg_metadata) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_transcode_to_jpeg(binary()) :: {:ok, binary()} | {:error, String.t()}
  def jxl_transcode_to_jpeg(_jxl_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec pdf_load_document(binary()) :: {:ok, {reference(), integer()}} | {:error, String.t()}
  def pdf_load_document(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec pdf_render_page(reference(), integer(), integer(), non_neg_integer()) :: decompress_ret_type()
  def pdf_render_page(_document, _page_idx, _dpi, _max_pixels) do
    exit(:nif_library_not_loaded)
  end

  @spec tiff_load_document(binary()) :: {:ok, {reference(), integer()}} | {:error, String.t()}
  def tiff_load_document(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec tiff_render_page(reference(), integer(), non_neg_integer()) :: decompress_ret_type()
  def tiff_render_page(_document, _page_idx, _max_pixels) do
    exit(:nif_library_not_loaded)
  end

  @spec webp_decompress(binary(), non_neg_integer()) :: decompress_ret_type()
  def webp_decompress(_bytes, _max_pixels) do
    exit(:nif_library_not_loaded)
  end

  @spec webp_compress(binary(), integer(), integer(), integer(), float(), boolean(), integer()) :: compress_ret_type()
  def webp_compress(_pixels, _width, _height, _channels, _quality, _lossless, _effort) do
    exit(:nif_library_not_loaded)
  end
end
