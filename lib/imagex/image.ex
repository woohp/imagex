defmodule Imagex.Image do
  @moduledoc """
  A decoded image: its pixels as an `Nx.Tensor` and its metadata.

  The tensor has shape `{height, width}` for grayscale images and `{height, width, channels}` otherwise,
  with channels in L/LA/RGB/RGBA order. `metadata` is `nil` or a map such as
  `%{exif: ..., xmp: ..., png_chunks: ..., jxl_boxes: ..., jfif: ...}`; see the README for its shapes.
  """

  @type t :: %__MODULE__{tensor: Nx.Tensor.t(), metadata: map() | nil}

  @enforce_keys [:tensor]
  defstruct [:tensor, :metadata]

  @dialyzer {:nowarn_function, from_native: 2}

  # Builds an image from a native decoder result.
  @doc false
  def from_native(
        {:ok, {pixels, width, height, channels, bit_depth, exif, png_texts, xml_boxes, jumb_boxes}},
        parse_metadata
      ) do
    metadata =
      if parse_metadata do
        metadata =
          if(exif, do: Imagex.Exif.read_exif_from_tiff(exif), else: %{})
          |> Map.merge(Imagex.Png.metadata_from_texts(png_texts))
          |> Map.merge(Imagex.Jxl.metadata_from_boxes(xml_boxes, jumb_boxes))

        if metadata != %{}, do: metadata
      end

    shape = if channels == 1, do: {height, width}, else: {height, width, channels}
    tensor = pixels |> Nx.from_binary({:u, bit_depth}) |> Nx.reshape(shape)
    {:ok, %__MODULE__{tensor: tensor, metadata: metadata}}
  end

  def from_native({:error, _reason} = error, _parse_metadata), do: error
end
