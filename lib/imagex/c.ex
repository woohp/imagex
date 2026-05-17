defmodule Imagex.C do
  use Expp, ext: "./priv/imagex"

  # Dialyzer suppressions for NIF stub functions that call exit()
  @dialyzer {:nowarn_function, jpeg_decompress: 1}
  @dialyzer {:nowarn_function, jpeg_compress: 7}
  @dialyzer {:nowarn_function, png_decompress: 1}
  @dialyzer {:nowarn_function, png_compress: 6}
  @dialyzer {:nowarn_function, jxl_decompress: 1}
  @dialyzer {:nowarn_function, jxl_compress: 12}
  @dialyzer {:nowarn_function, jxl_transcode_from_jpeg: 3}
  @dialyzer {:nowarn_function, jxl_transcode_to_jpeg: 1}
  @dialyzer {:nowarn_function, pdf_load_document: 1}
  @dialyzer {:nowarn_function, pdf_render_page: 3}
  @dialyzer {:nowarn_function, tiff_load_document: 1}
  @dialyzer {:nowarn_function, tiff_render_page: 2}

  @type decompress_ret_type ::
          {:ok,
           {binary(), integer(), integer(), integer(), integer(), binary() | nil,
            list({binary(), binary(), binary(), binary()}), list(binary()), list(binary())}}
          | {:error, String.t()}
  @type compress_ret_type :: {:ok, binary()} | {:error, String.t()}

  @spec jpeg_decompress(binary()) :: decompress_ret_type()
  def jpeg_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec jpeg_compress(binary(), integer(), integer(), integer(), integer(), binary() | nil, binary() | nil) ::
          compress_ret_type()
  def jpeg_compress(_pixels, _width, _height, _channels, _quality, _exif_binary, _xmp_binary) do
    exit(:nif_library_not_loaded)
  end

  @spec png_decompress(binary()) :: decompress_ret_type()
  def png_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec png_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          list({binary(), binary(), binary(), binary()}) | nil
        ) ::
          compress_ret_type()
  def png_compress(_pixels, _width, _height, _channels, _bit_depth, _png_texts) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_decompress(binary()) :: decompress_ret_type()
  def jxl_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_compress(
          binary(),
          integer(),
          integer(),
          integer(),
          integer(),
          binary() | nil,
          list({atom(), binary()}) | nil,
          float(),
          boolean(),
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
        _order
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

  @spec pdf_render_page(reference(), integer(), integer()) :: decompress_ret_type()
  def pdf_render_page(_document, _page_idx, _dpi) do
    exit(:nif_library_not_loaded)
  end

  @spec tiff_load_document(binary()) :: {:ok, {reference(), integer()}} | {:error, String.t()}
  def tiff_load_document(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec tiff_render_page(reference(), integer()) :: decompress_ret_type()
  def tiff_render_page(_document, _page_idx) do
    exit(:nif_library_not_loaded)
  end
end
