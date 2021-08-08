defmodule Imagex do
  @moduledoc """
  Documentation for Imagex.
  """

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

  def encode(image, format, options \\ [])

  def encode(image = %Nx.Tensor{}, :jpeg, options) do
    quality = Keyword.get(options, :quality, 75)
    pixels = Nx.to_binary(image)
    {h, w, c} = standardize_shape(image.shape)
    Imagex.C.jpeg_compress(pixels, w, h, c, quality)
  end

  def encode(image = %Nx.Tensor{}, :png, _options) do
    pixels = Nx.to_binary(image)
    {h, w, c} = standardize_shape(image.shape)
    Imagex.C.png_compress(pixels, w, h, c)
  end

  def encode(image = %Nx.Tensor{}, :jxl, options) do
    # + 0.0 to convert any integer to float
    distance =
      case Keyword.get(options, :distance, 1.0) do
        value when 0 <= value and value <= 15 -> value
      end + 0.0

    # the config variable must be boolean, but the impl expects an integer
    lossless = Keyword.get(options, :lossless, false)

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

    Imagex.C.jxl_compress(
      pixels,
      w,
      h,
      c,
      distance,
      lossless,
      effort
    )
  end

  def encode(image = %Nx.Tensor{}, :ppm, _options) do
    Imagex.PPM.encode(image)
  end

  def encode(image = %Nx.Tensor{}, :bmp, _options) do
    Imagex.BMP.encode(image)
  end

  defp decode_multi(_bytes, []), do: {:error, "failed to decode"}

  defp decode_multi(bytes, [format | rest]) do
    case decode(bytes, format: format) do
      {:ok, image} -> {:ok, image}
      {:error, _error_msg} -> decode_multi(bytes, rest)
    end
  end

  def decode(bytes, options \\ []) do
    case Keyword.get(options, :format, [:jpeg, :png, :jxl, :ppm, :bmp, :pdf, :tiff]) do
      :jpeg ->
        to_tensor(Imagex.C.jpeg_decompress(bytes))

      :png ->
        to_tensor(Imagex.C.png_decompress(bytes))

      :jxl ->
        to_tensor(Imagex.C.jxl_decompress(bytes))

      :ppm ->
        Imagex.PPM.decode(bytes)

      :bmp ->
        Imagex.BMP.decode(bytes)

      :pdf ->
        case Imagex.C.pdf_load_document(bytes) do
          {:ok, {ref, num_pages}} -> {:ok, %Imagex.Pdf{ref: ref, num_pages: num_pages}}
          error -> error
        end

      :tiff ->
        case Imagex.C.tiff_load_document(bytes) do
          {:ok, {ref, num_pages}} -> {:ok, %Imagex.Tiff{ref: ref, num_pages: num_pages}}
          error -> error
        end

      formats when is_list(formats) ->
        decode_multi(bytes, formats)
    end
  end

  def open(path, options \\ []) do
    with {:ok, file_content} <- File.read(path),
         {:ok, _result} = out <- decode(file_content, options) do
      out
    else
      error -> error
    end
  end

  defp ext_to_format(".jpeg"), do: :jpeg
  defp ext_to_format(".jpg"), do: :jpeg
  defp ext_to_format(".png"), do: :png
  defp ext_to_format(".jxl"), do: :jxl
  defp ext_to_format(".pgm"), do: :ppm
  defp ext_to_format(".ppm"), do: :ppm
  defp ext_to_format(".bmp"), do: :bmp
  defp ext_to_format(".pdf"), do: :pdf
  defp ext_to_format(".tiff"), do: :tiff
  defp ext_to_format(".tif"), do: :tiff

  def save(%Nx.Tensor{} = image, path, options \\ []) when is_binary(path) do
    format = ext_to_format(String.downcase(Path.extname(path)))
    {:ok, compressed} = encode(image, format, options)
    File.write(path, compressed)
  end
end
