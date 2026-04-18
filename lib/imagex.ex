defmodule Imagex do
  @moduledoc """
  Documentation for Imagex.
  """

  @dialyzer {:nowarn_function, to_tensor: 2}

  alias Imagex.Image

  defguardp is_image(image) when is_struct(image, Imagex.Image)
  defguardp is_tensor(image) when is_struct(image, Nx.Tensor)
  defguardp is_path(path) when is_binary(path) or is_list(path)

  @spec convert(Image.t(), Imagex.Color.colorspace()) :: Image.t()
  def convert(%Image{tensor: tensor} = image, to_colorspace) do
    from_colorspace = infer_colorspace(tensor)
    new_tensor = Imagex.Color.convert(tensor, from_colorspace, to_colorspace)
    %{image | tensor: new_tensor}
  end

  defp infer_colorspace(tensor) do
    case tensor.shape do
      {_h, _w} -> :L
      {_h, _w, 1} -> :L
      {_h, _w, 2} -> :LA
      {_h, _w, 3} -> :RGB
      {_h, _w, 4} -> :RGBA
    end
  end

  @spec encode(Nx.Tensor.t(), :jpeg | :png | :jxl | :ppm | :bmp, keyword()) :: Imagex.C.compress_ret_type()
  @spec encode(Nx.Tensor.t(), :jpeg | :png | :jxl | :ppm | :bmp) :: Imagex.C.compress_ret_type()
  @spec encode(Image.t(), :jpeg | :png | :jxl | :ppm | :bmp, keyword()) :: Imagex.C.compress_ret_type()
  @spec encode(Image.t(), :jpeg | :png | :jxl | :ppm | :bmp) :: Imagex.C.compress_ret_type()
  def encode(image, format, options \\ [])

  def encode(image, :jpeg, options) when is_tensor(image) do
    with {:ok, options} <- Keyword.validate(options, quality: 75, metadata: nil),
         {:ok, exif_binary} <- exif_binary_from_metadata(Keyword.get(options, :metadata)) do
      quality = Keyword.get(options, :quality)
      pixels = Nx.to_binary(image)
      {h, w, c} = standardize_shape(image.shape)
      Imagex.C.jpeg_compress(pixels, w, h, c, quality, exif_binary)
    else
      error -> error
    end
  end

  def encode(%Image{tensor: tensor, metadata: metadata}, :jpeg, options) do
    encode(tensor, :jpeg, Keyword.put(options, :metadata, metadata))
  end

  def encode(image, :png, options) when is_tensor(image) do
    with {:ok, options} <- Keyword.validate(options, metadata: nil),
         {:ok, png_texts} <- Imagex.Png.texts_from_metadata(Keyword.get(options, :metadata)) do
      pixels = Nx.to_binary(image)
      {h, w, c} = standardize_shape(image.shape)
      bit_depth = get_bit_depth(image)
      Imagex.C.png_compress(pixels, w, h, c, bit_depth, png_texts)
    else
      error -> error
    end
  end

  def encode(%Image{tensor: tensor, metadata: metadata}, :png, options) do
    encode(tensor, :png, Keyword.put(options, :metadata, metadata))
  end

  def encode(image, :jxl, options) when is_tensor(image) do
    with {:ok, options} <-
           Keyword.validate(options,
             distance: 1.0,
             lossless: false,
             effort: 7,
             progressive: true,
             order: :center
           ),
         bit_depth <- get_bit_depth(image) do
      # + 0.0 to convert any integer to float
      distance =
        case Keyword.get(options, :distance) do
          value when 0 <= value and value <= 15 -> value
        end + 0.0

      # the config variable must be boolean, but the impl expects an integer
      lossless = Keyword.get(options, :lossless)

      effort = Imagex.Jxl.parse_effort(Keyword.get(options, :effort))

      progressive =
        case Keyword.get(options, :progressive) do
          true -> 1
          false -> 0
          level when is_integer(level) and level in 0..2 -> level
        end

      order =
        case Keyword.get(options, :order) do
          :center -> 1
          :scanline -> 0
          level when is_integer(level) and level in 0..1 -> level
        end

      pixels = Nx.to_binary(image)
      {h, w, c} = standardize_shape(image.shape)

      Imagex.C.jxl_compress(pixels, w, h, c, bit_depth, distance, lossless, effort, progressive, order)
    else
      error -> error
    end
  end

  def encode(image, :ppm, []) when is_tensor(image) do
    Imagex.PPM.encode(image)
  end

  def encode(image, :bmp, []) when is_tensor(image) do
    Imagex.BMP.encode(image)
  end

  def encode(image, format, options) when is_image(image) do
    encode(image.tensor, format, options)
  end

  @spec decode(binary(), keyword()) :: {:ok, Imagex.Image.t()} | {:error, String.t()}
  @spec decode(binary()) :: {:ok, Imagex.Image.t()} | {:error, String.t()}
  def decode(bytes, options \\ []) do
    parse_metadata = Keyword.get(options, :parse_metadata, true)

    case Keyword.get_lazy(options, :format, fn -> Imagex.Detect.detect(bytes) end) do
      :jpeg ->
        case to_tensor(Imagex.C.jpeg_decompress(bytes), parse_metadata) do
          {:ok, %Image{tensor: tensor, metadata: nil} = image} ->
            if parse_metadata do
              {:ok, %Image{tensor: tensor, metadata: Imagex.Exif.read_exif_from_jpeg(bytes)}}
            else
              {:ok, image}
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

  @dialyzer {:nowarn_function, open: 2}

  @spec open(String.t(), keyword()) :: {:ok, Imagex.Image.t()} | {:error, String.t()}
  def open(path, options \\ []) when is_path(path) do
    with {:ok, file_content} <- File.read(path),
         {:ok, result} <- decode(file_content, options) do
      {:ok, result}
    else
      error -> error
    end
  end

  @spec save(Nx.Tensor.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  @spec save(Nx.Tensor.t(), String.t()) :: :ok | {:error, String.t()}
  def save(image, path, options \\ []) when is_path(path) and is_image(image) do
    format = ext_to_format(String.downcase(Path.extname(path)))

    with {:ok, compressed} <- encode(image, format, options),
         :ok <- File.write(path, compressed) do
      :ok
    else
      error -> error
    end
  end

  defp to_tensor({:ok, {pixels, width, height, channels, bit_depth, exif_binary, png_texts}}, parse_metadata) do
    metadata =
      if parse_metadata do
        exif_data =
          if is_binary(exif_binary) do
            Imagex.Exif.read_exif_from_tiff(exif_binary)
          else
            %{}
          end

        png_data = Imagex.Png.metadata_from_texts(png_texts)

        metadata = Map.merge(exif_data, png_data)
        if metadata == %{}, do: nil, else: metadata
      else
        nil
      end

    shape = if channels == 1, do: {height, width}, else: {height, width, channels}

    type =
      case bit_depth do
        8 -> {:u, 8}
        16 -> {:u, 16}
        32 -> {:f, 32}
      end

    tensor = Nx.from_binary(pixels, type) |> Nx.reshape(shape)
    image = %Imagex.Image{tensor: tensor, metadata: metadata}
    {:ok, image}
  end

  defp to_tensor({:error, _error_msg} = output, _parse_metadata) do
    output
  end

  defp exif_binary_from_metadata(nil), do: {:ok, nil}

  defp exif_binary_from_metadata(metadata) when is_map(metadata) do
    case Map.get(metadata, :exif) do
      nil -> {:ok, nil}
      exif when is_map(exif) -> Imagex.Exif.encode_exif(exif)
      exif -> {:error, "EXIF metadata must be a map, got: #{inspect(exif)}"}
    end
  end

  defp exif_binary_from_metadata(metadata),
    do: {:error, "image metadata must be a map or nil, got: #{inspect(metadata)}"}

  defp standardize_shape({h, w}), do: {h, w, 1}
  defp standardize_shape({_h, _w, _c} = shape), do: shape

  defp get_bit_depth(%Nx.Tensor{type: {:u, bit_depth}}), do: bit_depth

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
