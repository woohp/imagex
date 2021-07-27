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

  defp to_struct({:ok, {pixels, width, height, channels, auxiliary}}) do
    {:ok, %Image{pixels: pixels, width: width, height: height, channels: channels}, auxiliary}
  end

  defp to_struct({:error, _error_msg} = output) do
    output
  end

  def jpeg_decompress(bytes) do
    with {:ok, image, auxiliary} <- to_struct(jpeg_decompress_impl(bytes)) do
      {saw_JFIF_marker, jfif_version, jfif_unit, jfif_density} = auxiliary

      info =
        if saw_JFIF_marker == 1 do
          %{
            jfif_version: jfif_version,
            jfif_unit: jfif_unit,
            jfif_density: jfif_density
          }
        else
          nil
        end

      {:ok, %Image{image | info: info}}
    else
      {:error, _} = output -> output
    end
  end

  def jpeg_compress(image = %Image{}, options \\ []) do
    quality = Keyword.get(options, :quality, 75)
    jpeg_compress_impl(image.pixels, image.width, image.height, image.channels, quality)
  end

  def png_decompress(bytes) do
    with {:ok, image, auxiliary} <- to_struct(png_decompress_impl(bytes)) do
      {dpi} = auxiliary

      info = %{dpi: dpi}
      {:ok, %Image{image | info: info}}
    else
      {:error, _} = output -> output
    end
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

    result =
      Enum.reduce_while(methods, nil, fn {type, method}, acc ->
        case apply(__MODULE__, method, [bytes]) do
          {:ok, image} -> {:halt, {:ok, {type, image}}}
          {:error, _reason} -> {:cont, acc}
        end
      end)

    case result do
      {:ok, _} = out -> out
      nil -> {:error, "failed to decode"}
    end
  end

  def open(path) do
    with {:ok, file_content} <- File.read(path),
         {:ok, _result} = out <- decode(file_content) do
      out
    else
      error -> error
    end
  end

  def to_nx_tensor(%Image{pixels: pixels, height: h, width: w, channels: c}) do
    Nx.from_binary(pixels, {:u, 8})
    |> Nx.reshape({h, w, c})
  end

  def from_nx_tensor(%Nx.Tensor{} = tensor) do
    {h, w, c} =
      case tensor.shape do
        {h, w} -> {h, w, 1}
        {_h, _w, _c} = shape -> shape
      end

    %Image{
      pixels: Nx.to_binary(tensor),
      width: w,
      height: h,
      channels: c
    }
  end
end
