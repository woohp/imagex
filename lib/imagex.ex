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

  def jxl_compress_impl(_pixels, _width, _height, _channels, _distance, _lossless, _effort) do
    exit(:nif_library_not_loaded)
  end

  defp to_tensor({:ok, {pixels, width, height, channels}}) do
    shape = if channels == 1, do: {height, width}, else: {height, width, channels}
    {:ok, Nx.from_binary(pixels, {:u, 8}) |> Nx.reshape(shape)}
  end

  defp to_tensor({:ok, {pixels, width, height, channels, _auxiliary}}) do
    {:ok, tensor} = to_tensor({:ok, {pixels, width, height, channels}})
    {:ok, tensor}
  end

  defp to_tensor({:error, _error_msg} = output) do
    output
  end

  defp standardize_shape({h, w}), do: {h, w, 1}
  defp standardize_shape({_h, _w, _c} = shape), do: shape

  def jpeg_compress(image = %Nx.Tensor{}, options \\ []) do
    quality = Keyword.get(options, :quality, 75)
    pixels = Nx.to_binary(image)
    {h, w, c} = standardize_shape(image.shape)
    jpeg_compress_impl(pixels, w, h, c, quality)
  end

  def png_compress(image = %Nx.Tensor{}, _options \\ []) do
    pixels = Nx.to_binary(image)
    {h, w, c} = standardize_shape(image.shape)
    png_compress_impl(pixels, w, h, c)
  end

  def jxl_compress(image = %Nx.Tensor{}, options \\ []) do
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

    pixels = Nx.to_binary(image)
    {h, w, c} = standardize_shape(image.shape)

    jxl_compress_impl(
      pixels,
      w,
      h,
      c,
      distance,
      lossless,
      effort
    )
  end

  def ppm_encode(image) do
    Imagex.PPM.encode(image)
  end

  defp decode_impl(_bytes, []), do: {:error, "failed to decode"}

  defp decode_impl(bytes, [format | rest]) do
    case decode(bytes, format) do
      {:ok, image} -> {:ok, image}
      {:error, _error_msg} -> decode_impl(bytes, rest)
    end
  end

  def decode(bytes, [format: :jpeg]), do: to_tensor(jpeg_decompress_impl(bytes))
  def decode(bytes, [format: :png]), do: to_tensor(png_decompress_impl(bytes))
  def decode(bytes, [format: :jxl]), do: to_tensor(jxl_decompress_impl(bytes))
  def decode(bytes, [format: :ppm]), do: Imagex.PPM.decode(bytes)

  def decode(bytes, options \\ []) do
    methods = Keyword.get(options, :formats, [:jpeg, :png, :jxl, :ppm])
    decode_impl(bytes, methods)
  end

  def open(path) do
    with {:ok, file_content} <- File.read(path),
         {:ok, _result} = out <- decode(file_content) do
      out
    else
      error -> error
    end
  end
end
