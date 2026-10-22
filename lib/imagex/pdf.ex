defmodule Imagex.Pdf do
  @moduledoc """
  Loads PDF documents and renders their pages as images.

      {:ok, document} = Imagex.Pdf.load(File.read!("document.pdf"))
      {:ok, image} = Imagex.Pdf.render_page(document, 0, dpi: 150)
  """

  @enforce_keys [:ref, :num_pages]
  defstruct [:ref, :num_pages]

  @type t :: %__MODULE__{ref: reference(), num_pages: non_neg_integer()}

  @dialyzer {:nowarn_function, load: 1}
  @dialyzer {:nowarn_function, render_page: 3}

  @doc "Loads a PDF document from its bytes."
  @spec load(binary()) :: {:ok, t()} | {:error, String.t()}
  def load(bytes) when is_binary(bytes) do
    with {:ok, {ref, num_pages}} <- Imagex.C.pdf_load_document(bytes) do
      {:ok, %__MODULE__{ref: ref, num_pages: num_pages}}
    end
  end

  @doc """
  Renders a zero-indexed page as an RGB(A) image.

  Options:

    * `:dpi` - the rendering resolution (default `72`).
    * `:max_pixels` - as for `Imagex.decode/2`.
  """
  @spec render_page(t(), non_neg_integer(), keyword()) :: {:ok, Imagex.Image.t()} | {:error, String.t()}
  def render_page(%__MODULE__{ref: ref, num_pages: num_pages}, page_idx, options \\ []) do
    options = Keyword.validate!(options, dpi: 72, max_pixels: Imagex.Image.default_max_pixels())
    max_pixels = Imagex.Image.native_max_pixels(options[:max_pixels])

    unless is_integer(options[:dpi]) and options[:dpi] > 0 do
      raise ArgumentError, "expected :dpi to be a positive integer, got: #{inspect(options[:dpi])}"
    end

    if is_integer(page_idx) and page_idx in 0..(num_pages - 1)//1 do
      Imagex.Image.from_native(Imagex.C.pdf_render_page(ref, page_idx, options[:dpi], max_pixels), false)
    else
      {:error, "page index out of range"}
    end
  end
end
