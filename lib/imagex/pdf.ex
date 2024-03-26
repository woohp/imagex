defmodule Imagex.Pdf do
  @enforce_keys [:ref, :num_pages]
  defstruct [:ref, :num_pages]

  def render_page(%Imagex.Pdf{ref: ref, num_pages: num_pages}, page_idx, options \\ [])
      when page_idx >= 0 and page_idx < num_pages do
    with {:ok, options} <- Keyword.validate(options, dpi: 72) do
      dpi = Keyword.get(options, :dpi)
      {:ok, {pixels, width, height, channels, bit_depth, _exif_data}} = Imagex.C.pdf_render_page(ref, page_idx, dpi)

      shape = if channels == 1, do: {height, width}, else: {height, width, channels}
      tensor = Nx.from_binary(pixels, {:u, bit_depth}) |> Nx.reshape(shape)
      {:ok, %Imagex.Image{tensor: tensor}}
    else
      error -> error
    end
  end
end
