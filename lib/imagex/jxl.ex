defmodule Imagex.Jxl do
  @moduledoc """
  Lossless transcoding between JPEG and JPEG XL.

  A JPEG transcoded to JXL is typically about 20% smaller and can be reconstructed bit-for-bit.
  """

  @doc """
  Transcodes JPEG bytes to JXL without decoding the pixels.

  Options:

    * `:effort` - encoder effort, 1-9 (default 7).
    * `:store_jpeg_metadata` - whether to keep the data needed to reconstruct the original JPEG file
      (default `true`).
    * `:max_pixels` - as for `Imagex.decode/2`.
  """
  @spec transcode_from_jpeg(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def transcode_from_jpeg(jpeg_bytes, options \\ []) when is_binary(jpeg_bytes) do
    options =
      Keyword.validate!(options, effort: 7, store_jpeg_metadata: true, max_pixels: Imagex.Image.default_max_pixels())

    max_pixels = Imagex.Image.native_max_pixels(options[:max_pixels])

    unless is_integer(options[:effort]) and options[:effort] in 1..9 do
      raise ArgumentError, "expected :effort to be an integer between 1 and 9, got: #{inspect(options[:effort])}"
    end

    unless is_boolean(options[:store_jpeg_metadata]) do
      raise ArgumentError,
            "expected :store_jpeg_metadata to be a boolean, got: #{inspect(options[:store_jpeg_metadata])}"
    end

    Imagex.C.jxl_transcode_from_jpeg(jpeg_bytes, options[:effort], options[:store_jpeg_metadata], max_pixels)
  end

  @doc """
  Reconstructs the original JPEG from a JXL produced by `transcode_from_jpeg/2`.

  Options:

    * `:max_pixels` - as for `Imagex.decode/2`.
  """
  @spec transcode_to_jpeg(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def transcode_to_jpeg(jxl_bytes, options \\ []) when is_binary(jxl_bytes) do
    options = Keyword.validate!(options, max_pixels: Imagex.Image.default_max_pixels())
    Imagex.C.jxl_transcode_to_jpeg(jxl_bytes, Imagex.Image.native_max_pixels(options[:max_pixels]))
  end

  # A single xml box is surfaced as metadata.xmp instead of a jxl_boxes entry, so it is stored once.
  @doc false
  def metadata_from_boxes(xml_boxes, jumb_boxes) do
    {xmp, xml_boxes} =
      case xml_boxes do
        [xmp] -> {xmp, []}
        _ -> {nil, xml_boxes}
      end

    jxl_boxes =
      Enum.map(xml_boxes, &%{type: :xml, contents: &1}) ++ Enum.map(jumb_boxes, &%{type: :jumb, contents: &1})

    Map.reject(%{xmp: xmp, jxl_boxes: jxl_boxes}, fn {_key, value} -> value in [nil, []] end)
  end

  @doc false
  def boxes_from_metadata(nil, xmp), do: boxes_from_metadata([], xmp)

  def boxes_from_metadata(jxl_boxes, xmp) when is_list(jxl_boxes) do
    with :ok <- Enum.find_value(jxl_boxes, :ok, &box_error/1) do
      boxes = Enum.map(jxl_boxes, fn %{type: type, contents: contents} -> {native_box_type(type), contents} end)

      cond do
        is_nil(xmp) ->
          {:ok, boxes}

        Enum.any?(jxl_boxes, &(&1.type == :xml)) ->
          {:error, "metadata.xmp cannot be combined with JXL xml boxes in metadata.jxl_boxes"}

        true ->
          {:ok, [{native_box_type(:xml), xmp} | boxes]}
      end
    end
  end

  def boxes_from_metadata(jxl_boxes, _xmp),
    do: {:error, "JXL metadata must be a list, got: #{inspect(jxl_boxes)}"}

  defp native_box_type(:xml), do: "xml "
  defp native_box_type(:jumb), do: "jumb"

  # Returns nil for a valid box, or the error describing why it is invalid.
  defp box_error(%{type: type, contents: contents} = box) do
    cond do
      map_size(box) != 2 ->
        {:error, "unsupported JXL metadata keys: #{inspect(Map.keys(Map.drop(box, [:type, :contents])))}"}

      type == :exif ->
        {:error, "JXL Exif boxes must be provided via metadata.exif"}

      type not in [:xml, :jumb] ->
        {:error, "unsupported JXL metadata box type: #{inspect(type)}"}

      not is_binary(contents) ->
        {:error, "JXL metadata contents must be binaries, got: #{inspect(contents)}"}

      true ->
        nil
    end
  end

  defp box_error(box) do
    {:error, "JXL metadata entries must be maps with :type and :contents, got: #{inspect(box)}"}
  end
end
