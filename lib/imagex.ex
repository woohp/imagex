defmodule Imagex do
  @moduledoc """
  Decodes and encodes images as `Nx` tensors.

  | Format | Decode | Encode | Metadata |
  | --- | --- | --- | --- |
  | `:jpeg` | yes | yes | EXIF, XMP, JFIF |
  | `:png` | yes | yes | EXIF, XMP, text chunks |
  | `:jxl` | yes | yes | EXIF, XMP, XML/JUMBF boxes |
  | `:webp` | static images | yes | EXIF, XMP |
  | `:ppm` | yes | yes | none |
  | `:bmp` | yes | yes | none |
  | `:tiff` | one page | no | none |
  | `:pdf` | via `Imagex.Pdf` | no | none |

  Functions that take an image accept either an `Imagex.Image` or an `Nx.Tensor` of shape
  `{height, width}` or `{height, width, channels}`.

  Invalid arguments, such as an unknown format, an unknown option or an out-of-range option value,
  raise `ArgumentError`. Failures that depend on the data, such as corrupt input, pixels or metadata
  a codec cannot encode, or I/O errors, return `{:error, reason}` with a string reason.
  """

  alias Imagex.Image

  @type image :: Image.t() | Nx.Tensor.t()
  @type format :: :jpeg | :png | :jxl | :webp | :ppm | :bmp | :tiff | :pdf
  @type colorspace :: :L | :LA | :RGB | :RGBA

  @doc """
  Reads and decodes an image file. Accepts the same options as `decode/2`.
  """
  @spec open(Path.t(), keyword()) :: {:ok, Image.t()} | {:error, String.t()}
  def open(path, options \\ []) do
    case File.read(path) do
      {:ok, bytes} -> decode(bytes, options)
      {:error, reason} -> {:error, file_error(path, reason)}
    end
  end

  @doc """
  Decodes an image from its bytes.

  Options:

    * `:format` - the format of `bytes`; detected from its signature by default.
    * `:parse_metadata` - whether to read metadata into `Imagex.Image.metadata` (default `true`).
    * `:page` - the zero-indexed page to decode from a TIFF (default `0`).
    * `:max_pixels` - the largest width × height to decode (default 178,956,970), or `:infinity`. Larger
      images return an error before any pixel memory is allocated, so a small file cannot claim a huge image.
    * `:orient` - whether to rotate and flip JPEG, PNG and WebP pixels as their EXIF orientation says,
      then set that orientation to 1 (default `false`). JXL and TIFF pixels are always returned upright,
      and a decoded JXL's EXIF orientation is set to 1 to match.

  PDF documents are not decoded here, since rendering requires choosing a resolution; use `Imagex.Pdf`.
  """
  @spec decode(binary(), keyword()) :: {:ok, Image.t()} | {:error, String.t()}
  def decode(bytes, options \\ []) when is_binary(bytes) do
    options =
      Keyword.validate!(options, [
        :format,
        parse_metadata: true,
        page: 0,
        orient: false,
        max_pixels: Image.default_max_pixels()
      ])

    options = Keyword.put(options, :native_max_pixels, Image.native_max_pixels(options[:max_pixels]))
    validate_option!(options, :parse_metadata, &is_boolean/1, "a boolean")
    validate_option!(options, :orient, &is_boolean/1, "a boolean")
    validate_option!(options, :page, &(is_integer(&1) and &1 >= 0), "a non-negative integer")
    format = options[:format] || Imagex.Detect.detect(bytes)
    parse_metadata = options[:parse_metadata] or options[:orient]

    with {:ok, image} <- decode_format(format, bytes, Keyword.put(options, :parse_metadata, parse_metadata)) do
      image = if options[:orient] and format in [:jpeg, :png, :webp], do: orient(image), else: image
      {:ok, if(options[:parse_metadata], do: image, else: %{image | metadata: nil})}
    end
  end

  defp decode_format(:jpeg, bytes, options) do
    with {:ok, image} <- Image.from_native(Imagex.C.jpeg_decompress(bytes, options[:native_max_pixels]), false) do
      metadata = if options[:parse_metadata], do: Imagex.Jfif.read_metadata_from_jpeg(bytes)
      {:ok, %{image | metadata: metadata}}
    end
  end

  defp decode_format(:png, bytes, options),
    do: Image.from_native(Imagex.C.png_decompress(bytes, options[:native_max_pixels]), options[:parse_metadata])

  # libjxl applies the codestream orientation, so the pixels are already upright.
  defp decode_format(:jxl, bytes, options) do
    with {:ok, image} <-
           Image.from_native(Imagex.C.jxl_decompress(bytes, options[:native_max_pixels]), options[:parse_metadata]) do
      {:ok, upright(image)}
    end
  end

  defp decode_format(:webp, bytes, options) do
    with {:ok, image} <- Image.from_native(Imagex.C.webp_decompress(bytes, options[:native_max_pixels]), false),
         {:ok, metadata} <- Imagex.Webp.read_metadata(bytes, options[:parse_metadata]) do
      {:ok, %{image | metadata: metadata}}
    end
  end

  # These decode in Elixir, so their memory is bounded by the input; max_pixels is checked for consistency.
  defp decode_format(:ppm, bytes, options),
    do: bytes |> Imagex.PPM.decode() |> check_max_pixels(options[:native_max_pixels])

  defp decode_format(:bmp, bytes, options),
    do: bytes |> Imagex.BMP.decode() |> check_max_pixels(options[:native_max_pixels])

  defp decode_format(:tiff, bytes, options) do
    with {:ok, document} <- Imagex.Tiff.load(bytes) do
      Imagex.Tiff.render_page(document, options[:page], max_pixels: options[:max_pixels])
    end
  end

  defp decode_format(:pdf, _bytes, _options), do: {:error, "PDF documents must be loaded with Imagex.Pdf.load/1"}
  defp decode_format(nil, _bytes, _options), do: {:error, "unrecognized image format"}
  defp decode_format(format, _bytes, _options), do: raise(ArgumentError, "unsupported format: #{inspect(format)}")

  defp check_max_pixels({:ok, %Image{tensor: tensor}} = result, max_pixels) do
    {h, w, _c} = dimensions(tensor)

    if max_pixels != 0 and h * w > max_pixels,
      do: {:error, "image has more pixels than max_pixels allows"},
      else: result
  end

  defp check_max_pixels(error, _max_pixels), do: error

  defp orient(%Image{metadata: %{exif: %{ifd0: %{orientation: orientation}}}} = image) do
    transposed = if tuple_size(image.tensor.shape) == 2, do: [1, 0], else: [1, 0, 2]

    tensor =
      case orientation do
        2 -> Nx.reverse(image.tensor, axes: [1])
        3 -> Nx.reverse(image.tensor, axes: [0, 1])
        4 -> Nx.reverse(image.tensor, axes: [0])
        5 -> Nx.transpose(image.tensor, axes: transposed)
        6 -> image.tensor |> Nx.transpose(axes: transposed) |> Nx.reverse(axes: [1])
        7 -> image.tensor |> Nx.transpose(axes: transposed) |> Nx.reverse(axes: [0, 1])
        8 -> image.tensor |> Nx.transpose(axes: transposed) |> Nx.reverse(axes: [0])
        _ -> image.tensor
      end

    upright(%{image | tensor: tensor})
  end

  defp orient(image), do: image

  defp upright(%Image{metadata: %{exif: %{ifd0: %{orientation: _}}}} = image),
    do: put_in(image.metadata.exif.ifd0.orientation, 1)

  defp upright(image), do: image

  @doc """
  Encodes an image and writes it to `path`.

  The format comes from the `:format` option, or else from the file extension. Other options are
  passed to `encode/3`.
  """
  @spec save(image(), Path.t(), keyword()) :: :ok | {:error, String.t()}
  def save(image, path, options \\ []) do
    {format, options} = Keyword.pop_lazy(options, :format, fn -> format_from_extension!(path) end)

    with {:ok, bytes} <- encode(image, format, options) do
      case File.write(path, bytes) do
        :ok -> :ok
        {:error, reason} -> {:error, file_error(path, reason)}
      end
    end
  end

  defp format_from_extension!(path) do
    case String.downcase(Path.extname(path)) do
      ext when ext in [".jpg", ".jpeg"] -> :jpeg
      ".png" -> :png
      ".jxl" -> :jxl
      ".webp" -> :webp
      ext when ext in [".ppm", ".pgm"] -> :ppm
      ".bmp" -> :bmp
      ext -> raise ArgumentError, "cannot infer an image format from extension #{inspect(ext)}; pass :format"
    end
  end

  @doc """
  Encodes an image.

  An `Imagex.Image`'s metadata is written unless a `:metadata` option is given, which replaces it;
  `metadata: nil` writes none. Metadata that `format` cannot store is dropped.

  Options by format:

    * `:jpeg` - `:quality` (0-100, default 75). Accepts u8 grayscale or RGB.
    * `:png` - accepts u8 or u16 with 1-4 channels.
    * `:jxl` - `:distance` (0-15, default 1.0; 0 requires lossless), `:lossless` (default `false`),
      `:effort` (1-9, default 7), `:progressive` (0-2, default 1), `:order` (`:center` or `:scanline`,
      default `:center`). Accepts u8 or u16 with 1-4 channels.
    * `:webp` - `:quality` (0-100, default 75), `:lossless` (default `false`), `:effort` (0-6, default 4).
      Accepts u8 with 1-4 channels; grayscale is expanded to RGB(A). In lossless mode, `:quality` sets
      compression effort rather than fidelity.
    * `:ppm` - accepts u8 grayscale (written as PGM) or RGB.
    * `:bmp` - accepts u8 RGB or RGBA.
  """
  @spec encode(image(), format(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def encode(image, format, options \\ [])

  def encode(%Image{tensor: tensor, metadata: metadata}, format, options) do
    encode(tensor, format, Keyword.put_new(options, :metadata, metadata))
  end

  def encode(%Nx.Tensor{} = tensor, :jpeg, options) do
    options = Keyword.validate!(options, quality: 75, metadata: nil)
    validate_option!(options, :quality, &(is_integer(&1) and &1 in 0..100), "an integer between 0 and 100")

    with :ok <- check_pixels(tensor, "JPEG", [8], [1, 3]),
         {:ok, metadata} <- encode_metadata(options[:metadata]),
         {:ok, density} <- jfif_density(metadata[:jfif]) do
      {h, w, c} = dimensions(tensor)
      app1_segments = app1_segments([{"Exif\0\0", metadata.exif}, {"http://ns.adobe.com/xap/1.0/\0", metadata[:xmp]}])
      Imagex.C.jpeg_compress(Nx.to_binary(tensor), w, h, c, options[:quality], density, app1_segments)
    end
  end

  def encode(%Nx.Tensor{} = tensor, :png, options) do
    options = Keyword.validate!(options, metadata: nil)

    with :ok <- check_pixels(tensor, "PNG", [8, 16], 1..4),
         {:ok, metadata} <- encode_metadata(options[:metadata]),
         {:ok, png_texts} <- Imagex.Png.texts_from_metadata(metadata[:png_chunks], metadata[:xmp]) do
      {h, w, c} = dimensions(tensor)
      {:u, bit_depth} = tensor.type
      Imagex.C.png_compress(Nx.to_binary(tensor), w, h, c, bit_depth, metadata.exif, png_texts)
    end
  end

  def encode(%Nx.Tensor{} = tensor, :jxl, options) do
    options =
      Keyword.validate!(options,
        distance: 1.0,
        lossless: false,
        effort: 7,
        progressive: 1,
        order: :center,
        metadata: nil
      )

    validate_option!(options, :lossless, &is_boolean/1, "a boolean")
    validate_option!(options, :distance, &(is_number(&1) and &1 >= 0 and &1 <= 15), "a number between 0 and 15")
    validate_option!(options, :effort, &(is_integer(&1) and &1 in 1..9), "an integer between 1 and 9")
    validate_option!(options, :progressive, &(is_integer(&1) and &1 in 0..2), "an integer between 0 and 2")
    validate_option!(options, :order, &(&1 in [:center, :scanline]), ":center or :scanline")

    if options[:distance] == 0 and not options[:lossless] do
      raise ArgumentError, "JXL distance 0 requires lossless: true"
    end

    with :ok <- check_pixels(tensor, "JXL", [8, 16], 1..4),
         {:ok, metadata} <- encode_metadata(options[:metadata]),
         {:ok, jxl_boxes} <- Imagex.Jxl.boxes_from_metadata(metadata[:jxl_boxes], metadata[:xmp]) do
      {h, w, c} = dimensions(tensor)
      {:u, bit_depth} = tensor.type
      # A JXL Exif box starts with the offset of the TIFF header within it.
      jxl_boxes = if metadata.exif, do: [{"Exif", <<0::32, metadata.exif::binary>>} | jxl_boxes], else: jxl_boxes

      Imagex.C.jxl_compress(
        Nx.to_binary(tensor),
        w,
        h,
        c,
        bit_depth,
        jxl_boxes,
        options[:distance] / 1,
        options[:lossless],
        options[:effort],
        options[:progressive],
        if(options[:order] == :center, do: 1, else: 0),
        exif_orientation(options[:metadata])
      )
    end
  end

  def encode(%Nx.Tensor{} = tensor, :webp, options) do
    options = Keyword.validate!(options, quality: 75, lossless: false, effort: 4, metadata: nil)
    validate_option!(options, :quality, &(is_number(&1) and &1 >= 0 and &1 <= 100), "a number between 0 and 100")
    validate_option!(options, :lossless, &is_boolean/1, "a boolean")
    validate_option!(options, :effort, &(is_integer(&1) and &1 in 0..6), "an integer between 0 and 6")

    with :ok <- check_pixels(tensor, "WebP", [8], 1..4),
         {:ok, metadata} <- encode_metadata(options[:metadata]),
         tensor = expand_grayscale(tensor),
         {h, w, c} = dimensions(tensor),
         {:ok, bytes} <-
           Imagex.C.webp_compress(
             Nx.to_binary(tensor),
             w,
             h,
             c,
             options[:quality] / 1,
             options[:lossless],
             options[:effort]
           ) do
      Imagex.Webp.put_metadata(bytes, w, h, c == 4, metadata.exif, metadata[:xmp])
    end
  end

  def encode(%Nx.Tensor{} = tensor, :ppm, options) do
    Keyword.validate!(options, metadata: nil)
    Imagex.PPM.encode(tensor)
  end

  def encode(%Nx.Tensor{} = tensor, :bmp, options) do
    Keyword.validate!(options, metadata: nil)
    Imagex.BMP.encode(tensor)
  end

  def encode(%Nx.Tensor{}, format, _options) do
    raise ArgumentError,
          "cannot encode to #{inspect(format)}; supported formats are :jpeg, :png, :jxl, :webp, :ppm and :bmp"
  end

  # WebP stores only RGB(A).
  defp expand_grayscale(tensor) do
    case dimensions(tensor) do
      {_h, _w, 1} -> Imagex.Color.convert(tensor, :L, :RGB)
      {_h, _w, 2} -> Imagex.Color.convert(tensor, :LA, :RGBA)
      _ -> tensor
    end
  end

  @doc """
  Converts an image to another colorspace, returning the same kind of value it was given.

  The source colorspace is inferred from the channel count. Removing alpha composites onto black, and
  grayscale results have shape `{height, width}`.
  """
  @spec convert(image(), colorspace()) :: image()
  def convert(%Image{tensor: tensor} = image, colorspace), do: %{image | tensor: convert(tensor, colorspace)}

  def convert(%Nx.Tensor{} = tensor, colorspace) when colorspace in [:L, :LA, :RGB, :RGBA] do
    from_colorspace =
      case dimensions(tensor) do
        {_h, _w, 1} -> :L
        {_h, _w, 2} -> :LA
        {_h, _w, 3} -> :RGB
        {_h, _w, 4} -> :RGBA
        {_h, _w, c} -> raise ArgumentError, "cannot infer a colorspace for #{c} channels"
      end

    Imagex.Color.convert(tensor, from_colorspace, colorspace)
  end

  def convert(%Nx.Tensor{}, colorspace), do: raise(ArgumentError, "unsupported colorspace: #{inspect(colorspace)}")

  defp validate_option!(options, key, valid?, expected) do
    value = options[key]

    unless valid?.(value) do
      raise ArgumentError, "expected #{inspect(key)} to be #{expected}, got: #{inspect(value)}"
    end
  end

  defp check_pixels(tensor, codec, bit_depths, channel_counts) do
    {_h, _w, channels} = dimensions(tensor)

    if tensor.type in Enum.map(bit_depths, &{:u, &1}) and channels in channel_counts do
      :ok
    else
      {:error, "#{codec} cannot encode #{channels}-channel #{Nx.Type.to_string(tensor.type)} pixels"}
    end
  end

  defp dimensions(%Nx.Tensor{shape: {h, w}}), do: {h, w, 1}
  defp dimensions(%Nx.Tensor{shape: {_h, _w, _c} = shape}), do: shape

  defp dimensions(%Nx.Tensor{shape: shape}) do
    raise ArgumentError,
          "expected an image tensor of shape {height, width} or {height, width, channels}, got: #{inspect(shape)}"
  end

  # Validates the metadata shared by all formats, encoding EXIF to its binary form.
  defp encode_metadata(nil), do: {:ok, %{exif: nil}}

  defp encode_metadata(metadata) when is_map(metadata) do
    xmp = Map.get(metadata, :xmp)

    with {:ok, exif} <- encode_exif(Map.get(metadata, :exif)),
         true <- (is_nil(xmp) or is_binary(xmp)) || {:error, "XMP metadata must be a binary, got: #{inspect(xmp)}"} do
      {:ok, Map.put(metadata, :exif, exif)}
    end
  end

  defp encode_metadata(metadata),
    do: {:error, "image metadata must be a map or nil, got: #{inspect(metadata)}"}

  defp encode_exif(nil), do: {:ok, nil}
  defp encode_exif(exif) when is_map(exif), do: Imagex.Exif.encode_exif(exif)
  defp encode_exif(exif), do: {:error, "EXIF metadata must be a map, got: #{inspect(exif)}"}

  # JXL viewers follow the codestream orientation rather than EXIF, so it is carried over.
  defp exif_orientation(%{exif: %{ifd0: %{orientation: orientation}}}) when orientation in 1..8, do: orientation
  defp exif_orientation(_metadata), do: 1

  # A JPEG APP1 segment holds at most 65,533 bytes; larger metadata cannot be stored, so it is dropped.
  defp app1_segments(payloads) do
    for {identifier, payload} <- payloads,
        is_binary(payload) and byte_size(identifier) + byte_size(payload) <= 65_533,
        do: identifier <> payload
  end

  defp jfif_density(%{density_units: units, density_x: x, density_y: y} = jfif) do
    if units in 0..2 and x in 1..65535//1 and y in 1..65535//1 do
      {:ok, {units, x, y}}
    else
      {:error, "invalid JFIF density in metadata: #{inspect(jfif)}"}
    end
  end

  defp jfif_density(_jfif), do: {:ok, nil}

  defp file_error(path, reason), do: "#{path}: #{:file.format_error(reason)}"
end
