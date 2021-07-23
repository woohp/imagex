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

  def jxl_compress_impl(_pixels, _width, _height, _channels, _lossless) do
    exit(:nif_library_not_loaded)
  end

  defp to_struct({:ok, {pixels, width, height, channels}}) do
    {:ok, %Imagex.Image{pixels: pixels, width: width, height: height, channels: channels}}
  end

  defp to_struct({:error, _error_msg} = output) do
    output
  end

  def jpeg_decompress(bytes) do
    to_struct(jpeg_decompress_impl(bytes))
  end

  def jpeg_compress(pixels, width, height, channels, options \\ []) do
    quality = Keyword.get(options, :quality, 75)
    jpeg_compress_impl(pixels, width, height, channels, quality)
  end

  def png_decompress(bytes) do
    to_struct(png_decompress_impl(bytes))
  end

  def png_compress(pixels, width, height, channels) do
    png_compress_impl(pixels, width, height, channels)
  end

  def jxl_decompress(bytes) do
    to_struct(jxl_decompress_impl(bytes))
  end

  def jxl_compress(pixels, width, height, channels, options \\ []) do
    lossless =
      case Keyword.get(options, :lossless, 0) do
        1 -> 1
        0 -> 0
        false -> 0
        true -> 1
      end

    jxl_compress_impl(pixels, width, height, channels, lossless)
  end

  def decode(bytes) do
    methods = [{:jpeg, :jpeg_decompress}, {:png, :png_decompress}, {:jxl, :jxl_decompress}]

    Enum.reduce_while(methods, nil, fn {name, method}, acc ->
      case apply(__MODULE__, method, [bytes]) do
        {:ok, image} -> {:halt, {name, image}}
        {:error, _reason} -> {:cont, acc}
      end
    end)
  end
end
