defmodule Imagex do
  @moduledoc """
  Documentation for Imagex.
  """

  @on_load :init

  app = Mix.Project.config()[:app]

  alias Imagex.Image

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

  defp to_struct({:ok, {pixels, width, height, channels}}) do
    {:ok, %Image{pixels: pixels, width: width, height: height, channels: channels}}
  end

  defp to_struct({:error, _error_msg} = output) do
    output
  end

  def jpeg_decompress(bytes) do
    to_struct(jpeg_decompress_impl(bytes))
  end

  def jpeg_compress(image = %Image{}, options \\ []) do
    quality = Keyword.get(options, :quality, 75)
    jpeg_compress_impl(image.pixels, image.width, image.height, image.channels, quality)
  end

  def png_decompress(bytes) do
    to_struct(png_decompress_impl(bytes))
  end

  def png_compress(image = %Image{}) do
    png_compress_impl(image.pixels, image.width, image.height, image.channels)
  end

  def jxl_decompress(bytes) do
    to_struct(jxl_decompress_impl(bytes))
  end

  def jxl_compress(image = %Image{}, options \\ []) do
    # + 0.0 to convert any integer to float
    distance =
      case Keyword.get(options, :distance, 1.0) do
        value when 0 <= value and value <= 15 -> value
      end + 0.0

    # the config variable must be boolean, but the impl expects an integer
    lossless = (Keyword.get(options, :lossless, false) && 1) || 0

    effort =
      case Keyword.get(options, :effort, 7) do
        value when value in 3..9 -> value
        :falcon -> 3
        :cheetah -> 4
        :hare -> 5
        :wombat -> 6
        :squirrel -> 7
        :kitten -> 8
        :tortoise -> 9
      end

    jxl_compress_impl(
      image.pixels,
      image.width,
      image.height,
      image.channels,
      distance,
      lossless,
      effort
    )
  end

  def ppm_decode(bytes) do
    Imagex.PPM.decode(bytes)
  end

  def ppm_encode(image) do
    Imagex.PPM.encode(image)
  end

  def decode(bytes) do
    methods = [
      {:jpeg, :jpeg_decompress},
      {:png, :png_decompress},
      {:jxl, :jxl_decompress},
      {:ppm, :ppm_decode}
    ]

    Enum.reduce_while(methods, nil, fn {name, method}, acc ->
      case apply(__MODULE__, method, [bytes]) do
        {:ok, image} -> {:halt, {name, image}}
        {:error, _reason} -> {:cont, acc}
      end
    end)
  end
end
