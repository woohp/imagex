defmodule Imagex.Tiff do
  @moduledoc """
  Loads multi-page TIFF documents and renders their pages as images.

  `Imagex.decode/2` already decodes a single TIFF page (the first, or the one given by `page:`);
  use this module to inspect the page count or render several pages from one load.

      {:ok, document} = Imagex.Tiff.load(File.read!("scan.tiff"))
      {:ok, image} = Imagex.Tiff.render_page(document, document.num_pages - 1)
  """

  @enforce_keys [:ref, :num_pages]
  defstruct [:ref, :num_pages]

  @type t :: %__MODULE__{ref: reference(), num_pages: pos_integer()}

  @doc "Loads a TIFF document from its bytes."
  @spec load(binary()) :: {:ok, t()} | {:error, String.t()}
  def load(bytes) when is_binary(bytes) do
    with {:ok, {ref, num_pages}} <- Imagex.C.tiff_load_document(bytes) do
      {:ok, %__MODULE__{ref: ref, num_pages: num_pages}}
    end
  end

  @doc """
  Renders a zero-indexed page as an 8-bit RGBA image.

  Options:

    * `:max_pixels` - as for `Imagex.decode/2`.
  """
  @spec render_page(t(), non_neg_integer(), keyword()) :: {:ok, Imagex.Image.t()} | {:error, String.t()}
  def render_page(%__MODULE__{ref: ref}, page_idx, options \\ []) do
    options = Keyword.validate!(options, max_pixels: Imagex.Image.default_max_pixels())
    max_pixels = Imagex.Image.native_max_pixels(options[:max_pixels])
    Imagex.Image.from_native(Imagex.C.tiff_render_page(ref, page_idx, max_pixels), false)
  end
end
