defmodule Imagex.Tiff do
  @enforce_keys [:ref, :num_pages]
  defstruct [:ref, :num_pages]

  def render_page(%Imagex.Tiff{ref: ref, num_pages: num_pages}, page_idx)
      when page_idx >= 0 and page_idx < num_pages do
    {:ok, {pixels, width, height, channels, bit_depth, _exif_data}} = Imagex.C.tiff_render_page(ref, page_idx)

    shape = if channels == 1, do: {height, width}, else: {height, width, channels}
    tensor = Nx.from_binary(pixels, {:u, bit_depth}) |> Nx.reshape(shape)
    {:ok, %Imagex.Image{tensor: tensor}}
  end
end
