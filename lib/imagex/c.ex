defmodule Imagex.C do
  @on_load :init

  app = Mix.Project.config()[:app]

  @type decompress_ret_type ::
          {:ok, {binary(), integer(), integer(), integer(), integer(), binary() | nil}} | {:error, String.t()}
  @type compress_ret_type :: {:ok, binary()} | {:error, String.t()}

  @spec init() :: :ok
  def init do
    base_path =
      case :code.priv_dir(unquote(app)) do
        {:error, :bad_name} -> ~c"priv"
        dir -> dir
      end

    path = :filename.join(base_path, ~c"imagex")
    :ok = :erlang.load_nif(path, 0)
  end

  @spec jpeg_decompress(binary()) :: decompress_ret_type()
  def jpeg_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec jpeg_compress(binary(), integer(), integer(), integer(), integer()) :: compress_ret_type()
  def jpeg_compress(_pixels, _width, _height, _channels, _quality) do
    exit(:nif_library_not_loaded)
  end

  @spec png_decompress(binary()) :: decompress_ret_type()
  def png_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec png_compress(binary(), integer(), integer(), integer(), integer()) :: compress_ret_type()
  def png_compress(_pixels, _width, _height, _channels, _bit_depth) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_decompress(binary()) :: decompress_ret_type()
  def jxl_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_read_exif(binary()) :: binary() | nil
  def jxl_read_exif(_bytes) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_compress(binary(), integer(), integer(), integer(), integer(), integer(), boolean(), integer()) ::
          compress_ret_type()
  def jxl_compress(_pixels, _width, _height, _channels, _bit_depth, _distance, _lossless, _effort) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_transcode_from_jpeg(binary(), integer(), boolean()) :: binary()
  def jxl_transcode_from_jpeg(_jpeg_bytes, _effort, _store_jpeg_metadata) do
    exit(:nif_library_not_loaded)
  end

  @spec jxl_transcode_to_jpeg(binary()) :: binary()
  def jxl_transcode_to_jpeg(_jxl_bytes) do
    exit(:nif_library_not_loaded)
  end

  def pdf_load_document(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def pdf_render_page(_document, _page_idx, _dpi) do
    exit(:nif_library_not_loaded)
  end

  def tiff_load_document(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def tiff_render_page(_document, _page_idx) do
    exit(:nif_library_not_loaded)
  end
end
