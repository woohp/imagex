defmodule Imagex.Jxl do
  @moduledoc """
  JPEG XL (JXL) codec functions for transcoding and metadata extraction.
  """

  # Suppress dialyzer warnings for functions that call NIFs
  @dialyzer {:nowarn_function, transcode_from_jpeg: 2}
  @dialyzer {:nowarn_function, transcode_to_jpeg: 1}

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
    with {:ok, options} <- Keyword.validate(options, effort: 7, store_jpeg_metadata: true) do
      effort = parse_effort(Keyword.get(options, :effort))
      Imagex.C.jxl_transcode_from_jpeg(jpeg_bytes, effort, Keyword.get(options, :store_jpeg_metadata))
    end
  end

  @spec transcode_to_jpeg(binary()) :: {:ok, binary()} | {:error, String.t()}
  def transcode_to_jpeg(jxl_bytes) when is_binary(jxl_bytes) do
    Imagex.C.jxl_transcode_to_jpeg(jxl_bytes)
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

  @doc false
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
