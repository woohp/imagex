defmodule Imagex do
  @moduledoc """
  Documentation for Imagex.
  """

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

  def jpeg_compress_impl(_pixels, _width, _height, _channels, _quality) do
    exit(:nif_library_not_loaded)
  end

  def jpeg_compress(pixels, width, height, channels, options \\ []) do
    quality = Keyword.get(options, :quality, 75)
    jpeg_compress_impl(pixels, width, height, channels, quality)
  end

  def png_decompress(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def decode(_bytes) do
    exit(:nif_library_not_loaded)
  end

  def rgb2gray(_pixels) do
    exit(:nif_library_not_loaded)
  end
end
