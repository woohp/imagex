defmodule Imagex do
  @moduledoc """
  Documentation for Imagex.
  """

  defguardp is_image(image) when is_struct(image, Nx.Tensor)
  defguardp is_path(path) when is_binary(path) or is_list(path)

  @spec to_tensor(Imagex.C.decompress_ret_type(), boolean()) ::
          {:ok, {Nx.Tensor.t(), map() | nil}} | {:error, String.t()}
  defp to_tensor({:ok, {pixels, width, height, channels, bit_depth, exif_binary}}, parse_metadata) do
    exif_data =
      if is_binary(exif_binary) and parse_metadata do
        Imagex.Exif.read_exif_from_tiff(exif_binary)
      else
        exif_binary
      end

    shape = if channels == 1, do: {height, width}, else: {height, width, channels}

    type =
      case bit_depth do
        8 -> {:u, 8}
        16 -> {:u, 16}
        32 -> {:f, 32}
      end

    {:ok, {Nx.from_binary(pixels, type) |> Nx.reshape(shape), exif_data}}
  end

  defp to_tensor({:error, _error_msg} = output, _parse_metadata) do
    output
  end

  defp standardize_shape({h, w}), do: {h, w, 1}
  defp standardize_shape({_h, _w, _c} = shape), do: shape

  defp get_bit_depth(%Nx.Tensor{type: {:u, bit_depth}}), do: bit_depth

  @spec encode(Nx.Tensor.t(), :jpeg | :png | :jxl | :ppm | :bmp, keyword()) :: Imagex.C.compress_ret_type()
  @spec encode(Nx.Tensor.t(), :jpeg | :png | :jxl | :ppm | :bmp) :: Imagex.C.compress_ret_type()
  def encode(image, format, options \\ [])

  def encode(image, :jpeg, options) when is_image(image) do
    with {:ok, options} <- Keyword.validate(options, quality: 75) do
      quality = Keyword.get(options, :quality)
      pixels = Nx.to_binary(image)
      {h, w, c} = standardize_shape(image.shape)
      Imagex.C.jpeg_compress(pixels, w, h, c, quality)
    else
      error -> error
    end
  end

  def encode(image, :png, []) when is_image(image) do
    pixels = Nx.to_binary(image)
    {h, w, c} = standardize_shape(image.shape)
    bit_depth = get_bit_depth(image)
    Imagex.C.png_compress(pixels, w, h, c, bit_depth)
  end

  def encode(image, :jxl, options) when is_image(image) do
    with {:ok, options} <- Keyword.validate(options, distance: 1.0, lossless: false, effort: 7),
         bit_depth <- get_bit_depth(image) do
      # + 0.0 to convert any integer to float
      distance =
        case Keyword.get(options, :distance) do
          value when 0 <= value and value <= 15 -> value
        end + 0.0

      # the config variable must be boolean, but the impl expects an integer
      lossless = Keyword.get(options, :lossless)

      effort =
        case Keyword.get(options, :effort) do
          value when value in 1..9 -> value
          :lightning -> 1
          :thunder -> 2
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

      Imagex.C.jxl_compress(pixels, w, h, c, bit_depth, distance, lossless, effort)
    else
      error -> error
    end
  end

  def encode(image, :ppm, []) when is_image(image) do
    Imagex.PPM.encode(image)
  end

  def encode(image, :bmp, []) when is_image(image) do
    Imagex.BMP.encode(image)
  end

  @spec decode(binary(), keyword()) :: {:ok, {Nx.Tensor.t(), map() | nil}} | {:error, String.t()}
  @spec decode(binary()) :: {:ok, {Nx.Tensor.t(), map() | nil}} | {:error, String.t()}
  def decode(bytes, options \\ []) do
    parse_metadata = Keyword.get(options, :parse_metadata, true)

    case Keyword.get_lazy(options, :format, fn -> Imagex.Detect.detect(bytes) end) do
      :jpeg ->
        case to_tensor(Imagex.C.jpeg_decompress(bytes), parse_metadata) do
          {:ok, {image, nil}} ->
            if parse_metadata do
              {:ok, {image, Imagex.Exif.read_exif_from_jpeg(bytes)}}
            else
              {:ok, {image, :not_implmented_yet}}
            end

          {:error, _error_msg} = error ->
            error
        end

      :png ->
        to_tensor(Imagex.C.png_decompress(bytes), parse_metadata)

      :jxl ->
        to_tensor(Imagex.C.jxl_decompress(bytes), parse_metadata)

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

      nil ->
        {:error, "failed to decode"}
    end
  end

  @spec open(String.t(), keyword()) :: {:ok, {Nx.Tensor.t(), map() | nil}} | {:error, String.t()}
  def open(path, options \\ []) when is_path(path) do
    with {:ok, file_content} <- File.read(path),
         {:ok, _result} = out <- decode(file_content, options) do
      out
    else
      error -> error
    end
  end

  @spec save(Nx.Tensor.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  @spec save(Nx.Tensor.t(), String.t()) :: :ok | {:error, String.t()}
  def save(image, path, options \\ []) when is_path(path) and is_image(image) do
    format = ext_to_format(String.downcase(Path.extname(path)))

    case encode(image, format, options) do
      {:ok, compressed} ->
        File.write(path, compressed)

      {:error, _error_msg} = error ->
        error
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
end
