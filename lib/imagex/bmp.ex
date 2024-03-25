defmodule Imagex.BMP do
  @spec encode(Nx.Tensor.t()) :: {:ok, binary()}
  def encode(image) when is_struct(image, Nx.Tensor) do
    {h, w, 3} = Nx.shape(image)
    total_file_size = 14 + 40 + Nx.size(image)

    out = <<
      # bitmap file header
      "BM",
      total_file_size::32-little,
      0::16,
      0::16,
      52::32-little,

      # DIB header
      40::32-little,
      w::32-little,
      h::32-little,
      1::16-little,
      24::16-little,
      0::32,
      0::32,
      2834::32-little,
      2834::32-little,
      0::32,
      0::32,

      # pixels
      Nx.to_binary(image)
    >>

    ^total_file_size = byte_size(out)
    {:ok, out}
  end

  @spec decode(binary()) :: {:ok, {Nx.Tensor.t(), map() | nil}} | {:error, String.t()}
  def decode(bytes) do
    with <<
           # bitmap file header
           "BM",
           _size_of_file::32,
           _::16,
           _::16,
           offset_to_pixels::32-little,

           # DIB header (we only parse a subset of it)
           dib_header_size::32-little,
           width::signed-32-little,
           height::signed-32-little,
           1::16-little,
           bits_per_pixel::16-little,
           0::32,

           # everything else
           _rest::binary
         >>
         when (dib_header_size == 40 or dib_header_size == 124) and bits_per_pixel in [24, 32] <- bytes,
         <<_header::size(offset_to_pixels)-bytes, pixels::binary>> <- bytes do
      channels = div(bits_per_pixel, 8)

      pixels_exploded = for <<pixel::binary-size(channels) <- pixels>>, do: pixel
      # convert the pixels to RGB*
      pixels_exploded = Enum.map(pixels_exploded, &to_rgb/1)

      pixels =
        if height > 0 do
          # this is annoying, since windows use positive height to indicate that the image is to be shown bottom-to-top
          # and so we need to flip the rows
          pixels_exploded
          |> Enum.chunk_every(width)
          |> Enum.reverse()
          |> List.flatten()
          |> Enum.join("")
        else
          Enum.join(pixels_exploded, "")
        end

      tensor = Nx.reshape(Nx.from_binary(pixels, {:u, 8}), {abs(height), width, channels})
      {:ok, {tensor, nil}}
    else
      error -> {:error, error}
    end
  end

  defp to_rgb(<<b, g, r>>), do: <<r, g, b>>
  defp to_rgb(<<b, g, r, a>>), do: <<r, g, b, a>>
end
