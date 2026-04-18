defmodule Imagex.Tiff do
  @enforce_keys [:ref, :num_pages]
  defstruct [:ref, :num_pages]

  @type t :: %__MODULE__{ref: reference(), num_pages: integer()}

  @spec render_page(t(), integer()) :: {:ok, Imagex.Image.t()} | {:error, String.t()}
  def render_page(%Imagex.Tiff{ref: ref, num_pages: num_pages}, page_idx)
      when page_idx >= 0 and page_idx < num_pages do
    case Imagex.C.tiff_render_page(ref, page_idx) do
      {:ok, {pixels, width, height, channels, bit_depth, _exif_data, _png_texts, _xml_boxes, _jumb_boxes}} ->
        shape = if channels == 1, do: {height, width}, else: {height, width, channels}
        tensor = Nx.from_binary(pixels, {:u, bit_depth}) |> Nx.reshape(shape)
        {:ok, %Imagex.Image{tensor: tensor}}

      error ->
        error
    end
  end

  def render_page(_, page_idx) when page_idx < 0 do
    {:error, "page index must be non-negative"}
  end

  def render_page(%Imagex.Tiff{num_pages: num_pages}, page_idx) when page_idx >= num_pages do
    {:error, "page index out of bounds"}
  end
end
