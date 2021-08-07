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

  def jpeg_decompress_impl(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def jpeg_compress_impl(_pixels, _width, _height, _channels, _quality) do
    exit(:nif_library_not_loaded)
  end

  def png_decompress_impl(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def png_compress_impl(_pixels, _width, _height, _channels) do
    exit(:nif_library_not_loaded)
  end

  def jxl_decompress_impl(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def jxl_compress_impl(_pixels, _width, _height, _channels, _distance, _lossless, _effort) do
    exit(:nif_library_not_loaded)
  end

  def jxl_transcode_jpeg_impl(_jpeg_bytes, _effort) do
    exit(:nif_library_not_loaded)
  end

  def pdf_load_document_impl(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def pdf_render_page_impl(_document, _page_idx, _dpi) do
    exit(:nif_library_not_loaded)
  end

  def tiff_load_document_impl(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def tiff_render_page_impl(_document, _page_idx) do
    exit(:nif_library_not_loaded)
  end
end
