defmodule Imagex.Jxl do
  @moduledoc """
  JPEG XL (JXL) codec functions for transcoding and metadata extraction.
  """

  # Suppress dialyzer warnings for functions that call NIFs
  @dialyzer {:nowarn_function, transcode_from_jpeg: 2}
  @dialyzer {:nowarn_function, transcode_to_jpeg: 1}
  @dialyzer {:nowarn_function, read_metadata_from_jxl: 1}

  @type box_type :: :xml | :jumb
  @xmp_box_type :xml

  @typedoc """
  Effort level for JXL encoding.
  Can be 1-9 or named presets.
  """
  @type effort ::
          1..9
          | :lightning
          | :thunder
          | :falcon
          | :cheetah
          | :hare
          | :wombat
          | :squirrel
          | :kitten
          | :tortoise

  @spec transcode_from_jpeg(binary(), keyword()) ::
          {:ok, binary()} | {:error, String.t() | [atom()]}
  def transcode_from_jpeg(jpeg_bytes, options \\ []) when is_binary(jpeg_bytes) do
    with {:ok, options} <- Keyword.validate(options, effort: 7, store_jpeg_metadata: 1),
         effort <- parse_effort(Keyword.get(options, :effort)),
         store_jpeg_metadata <- parse_boolean(Keyword.get(options, :store_jpeg_metadata)) do
      Imagex.C.jxl_transcode_from_jpeg(jpeg_bytes, effort, store_jpeg_metadata)
    end
  end

  @spec transcode_to_jpeg(binary()) :: {:ok, binary()} | {:error, String.t()}
  def transcode_to_jpeg(jxl_bytes) when is_binary(jxl_bytes) do
    Imagex.C.jxl_transcode_to_jpeg(jxl_bytes)
  end

  @spec read_metadata_from_jxl(binary()) :: {:ok, map() | nil} | {:error, String.t()}
  def read_metadata_from_jxl(jxl_bytes) when is_binary(jxl_bytes) do
    case Imagex.C.jxl_decompress(jxl_bytes) do
      {:ok, {_pixels, _width, _height, _channels, _bit_depth, exif_binary, _png_texts, xml_boxes, jumb_boxes}} ->
        {:ok, boxes_to_metadata({exif_binary, xml_boxes, jumb_boxes})}

      {:error, _} = error ->
        error
    end
  end

  @spec metadata_to_boxes(map() | nil) ::
          {:ok, {binary() | nil, list({box_type(), binary()}) | nil}} | {:error, String.t()}
  def metadata_to_boxes(nil), do: {:ok, {nil, nil}}

  def metadata_to_boxes(metadata) when is_map(metadata) do
    with {:ok, exif_binary} <- exif_binary_from_metadata(metadata),
         {:ok, xmp} <- xmp_from_metadata(metadata),
         {:ok, jxl_boxes} <- jxl_boxes_from_metadata(metadata, xmp) do
      {:ok, {exif_binary, jxl_boxes}}
    end
  end

  def metadata_to_boxes(metadata),
    do: {:error, "image metadata must be a map or nil, got: #{inspect(metadata)}"}

  @spec boxes_to_metadata({binary() | nil, list(binary()), list(binary())} | nil) :: map() | nil
  def boxes_to_metadata(nil), do: nil

  def boxes_to_metadata({exif_binary, xml_boxes, jumb_boxes}) do
    exif_metadata =
      if is_binary(exif_binary) do
        Imagex.Exif.read_exif_from_tiff(exif_binary)
      else
        %{}
      end

    xmp_metadata =
      case xml_boxes do
        [xmp] -> %{xmp: xmp}
        _ -> %{}
      end

    jxl_metadata =
      [
        Enum.map(xml_boxes, &%{type: :xml, contents: &1}),
        Enum.map(jumb_boxes, &%{type: :jumb, contents: &1})
      ]
      |> List.flatten()
      |> case do
        [] -> %{}
        jxl_boxes -> %{jxl_boxes: jxl_boxes}
      end

    metadata = exif_metadata |> Map.merge(xmp_metadata) |> Map.merge(jxl_metadata)
    if metadata == %{}, do: nil, else: metadata
  end

  # Private helper functions

  def parse_effort(value) when value in 1..9, do: value
  def parse_effort(:lightning), do: 1
  def parse_effort(:thunder), do: 2
  def parse_effort(:falcon), do: 3
  def parse_effort(:cheetah), do: 4
  def parse_effort(:hare), do: 5
  def parse_effort(:wombat), do: 6
  def parse_effort(:squirrel), do: 7
  def parse_effort(:kitten), do: 8
  def parse_effort(:tortoise), do: 9

  defp parse_boolean(value) when value in [0, false], do: 0
  defp parse_boolean(value) when value in [1, true], do: 1

  defp exif_binary_from_metadata(metadata) do
    case Map.get(metadata, :exif) do
      nil -> {:ok, nil}
      exif when is_map(exif) -> Imagex.Exif.encode_exif(exif)
      exif -> {:error, "EXIF metadata must be a map, got: #{inspect(exif)}"}
    end
  end

  defp xmp_from_metadata(metadata) do
    case Map.get(metadata, :xmp) do
      nil -> {:ok, nil}
      xmp when is_binary(xmp) -> {:ok, xmp}
      xmp -> {:error, "XMP metadata must be a binary, got: #{inspect(xmp)}"}
    end
  end

  defp jxl_boxes_from_metadata(metadata, xmp) do
    case Map.get(metadata, :jxl_boxes) do
      nil ->
        xmp_to_jxl_boxes(xmp, [])

      jxl_boxes when is_list(jxl_boxes) ->
        jxl_boxes
        |> Enum.map(&box_from_metadata/1)
        |> Enum.reduce_while({:ok, []}, fn
          {:ok, box}, {:ok, acc} -> {:cont, {:ok, [box | acc]}}
          {:error, _} = error, _acc -> {:halt, error}
        end)
        |> case do
          {:ok, boxes} -> xmp_to_jxl_boxes(xmp, Enum.reverse(boxes))
          error -> error
        end

      jxl_boxes ->
        {:error, "JXL metadata must be a list, got: #{inspect(jxl_boxes)}"}
    end
  end

  defp xmp_to_jxl_boxes(nil, []), do: {:ok, nil}
  defp xmp_to_jxl_boxes(nil, boxes), do: {:ok, boxes}

  defp xmp_to_jxl_boxes(xmp, boxes) do
    if Enum.any?(boxes, fn {type, _contents} -> type == @xmp_box_type end) do
      {:error, "metadata.xmp cannot be combined with JXL xml boxes in metadata.jxl_boxes"}
    else
      {:ok, [{@xmp_box_type, xmp} | boxes]}
    end
  end

  defp box_from_metadata(%{type: type, contents: contents} = box) when map_size(box) == 2 do
    with {:ok, type} <- validate_box_type(type),
         :ok <- validate_box_contents(contents) do
      {:ok, {type, contents}}
    end
  end

  defp box_from_metadata(%{type: _type, contents: _contents} = box) do
    extra_keys = Map.keys(Map.drop(box, [:type, :contents]))
    {:error, "unsupported JXL metadata keys: #{inspect(extra_keys)}"}
  end

  defp box_from_metadata(box) do
    {:error, "JXL metadata entries must be maps with :type and :contents, got: #{inspect(box)}"}
  end

  defp validate_box_type(:xml), do: {:ok, :xml}
  defp validate_box_type(:jumb), do: {:ok, :jumb}
  defp validate_box_type(:exif), do: {:error, "JXL Exif boxes must be provided via metadata.exif"}

  defp validate_box_type(type),
    do: {:error, "unsupported JXL metadata box type: #{inspect(type)}"}

  defp validate_box_contents(contents) when is_binary(contents), do: :ok

  defp validate_box_contents(contents),
    do: {:error, "JXL metadata contents must be binaries, got: #{inspect(contents)}"}
end
