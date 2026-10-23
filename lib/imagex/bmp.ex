defmodule Imagex.BMP do
  @moduledoc false
  alias Imagex.Image

  @header_size 14 + 40

  @spec encode(Nx.Tensor.t()) :: {:ok, binary()} | {:error, String.t()}
  def encode(%Nx.Tensor{type: {:u, 8}, shape: {height, width, channels}} = image) when channels in [3, 4] do
    row_size = width * channels
    padding = stride(row_size) - row_size
    pixels = image |> swap_red_blue() |> Nx.to_binary()
    pixels = for <<row::binary-size(^row_size) <- pixels>>, into: <<>>, do: <<row::binary, 0::size(padding)-unit(8)>>

    # A negative height stores the rows top-down.
    {:ok,
     <<"BM", @header_size + byte_size(pixels)::32-little, 0::32, @header_size::32-little, 40::32-little,
       width::32-little, -height::signed-32-little, 1::16-little, channels * 8::16-little, 0::32,
       byte_size(pixels)::32-little, 2835::32-little, 2835::32-little, 0::32, 0::32, pixels::binary>>}
  end

  def encode(_image), do: {:error, "BMP requires unsigned 8-bit RGB or RGBA pixels"}

  @spec decode(binary()) :: {:ok, Image.t()} | {:error, String.t()}
  def decode(bytes) do
    with <<"BM", _file_size::32, _reserved::32, offset::32-little, dib_header_size::32-little, width::signed-32-little,
           height::signed-32-little, 1::16-little, bits_per_pixel::16-little, 0::32, _rest::binary>>
         when dib_header_size in [40, 124] and bits_per_pixel in [24, 32] and width > 0 and height != 0 and
                offset >= 14 + dib_header_size <- bytes,
         channels = div(bits_per_pixel, 8),
         row_size = width * channels,
         stride = stride(row_size),
         pixel_bytes = stride * abs(height),
         <<_header::binary-size(^offset), pixels::binary-size(^pixel_bytes), _::binary>> <- bytes do
      pixels = for <<row::binary-size(^stride) <- pixels>>, into: <<>>, do: binary_part(row, 0, row_size)
      tensor = pixels |> Nx.from_binary({:u, 8}) |> Nx.reshape({abs(height), width, channels}) |> swap_red_blue()

      # a positive height means the rows are stored bottom-up
      tensor = if height > 0, do: Nx.reverse(tensor, axes: [0]), else: tensor
      {:ok, %Image{tensor: tensor}}
    else
      _ -> {:error, "invalid or unsupported BMP data"}
    end
  end

  # BMP rows are padded to a multiple of 4 bytes.
  defp stride(row_size), do: div(row_size + 3, 4) * 4

  defp swap_red_blue(%Nx.Tensor{shape: {_, _, 3}} = tensor), do: Nx.take(tensor, Nx.tensor([2, 1, 0]), axis: 2)
  defp swap_red_blue(%Nx.Tensor{shape: {_, _, 4}} = tensor), do: Nx.take(tensor, Nx.tensor([2, 1, 0, 3]), axis: 2)
end
