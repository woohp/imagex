defmodule Imagex.Pdf do
  @enforce_keys [:ref, :num_pages]
  defstruct [:ref, :num_pages]

  def render_page(%Imagex.Pdf{ref: ref, num_pages: num_pages}, page_idx, options \\ [])
      when page_idx >= 0 and page_idx < num_pages do
    dpi = Keyword.get(options, :dpi, 72)
    {:ok, {pixels, width, height, channels}} = Imagex.pdf_render_page(ref, page_idx, dpi)

    shape = if channels == 1, do: {height, width}, else: {height, width, channels}
    {:ok, Nx.from_binary(pixels, {:u, 8}) |> Nx.reshape(shape)}
  end
end
