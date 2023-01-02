defmodule Imagex.C do
  @on_load :init

  app = Mix.Project.config()[:app]

  def init do
    base_path =
      case :code.priv_dir(unquote(app)) do
        {:error, :bad_name} -> 'priv'
        dir -> dir
      end

    path = :filename.join(base_path, 'imagex')
    :ok = :erlang.load_nif(path, 0)
  end

  def jpeg_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def jpeg_compress(_pixels, _width, _height, _channels, _quality) do
    exit(:nif_library_not_loaded)
  end

  def png_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def png_compress(_pixels, _width, _height, _channels, _bit_depth) do
    exit(:nif_library_not_loaded)
  end

  def jxl_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def jxl_compress(_pixels, _width, _height, _channels, _bit_depth, _distance, _lossless, _effort) do
    exit(:nif_library_not_loaded)
  end

  def jxl_transcode_from_jpeg(_jpeg_bytes, _effort, _store_jpeg_metadata) do
    exit(:nif_library_not_loaded)
  end

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
