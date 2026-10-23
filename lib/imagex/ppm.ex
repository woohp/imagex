defmodule Imagex.PPM do
  @moduledoc false
  alias Imagex.Image

  @spec encode(Nx.Tensor.t()) :: {:ok, binary()} | {:error, String.t()}
  def encode(%Nx.Tensor{type: {:u, 8}, shape: {height, width}} = image), do: encode("P5", width, height, image)
  def encode(%Nx.Tensor{type: {:u, 8}, shape: {height, width, 1}} = image), do: encode("P5", width, height, image)
  def encode(%Nx.Tensor{type: {:u, 8}, shape: {height, width, 3}} = image), do: encode("P6", width, height, image)
  def encode(_image), do: {:error, "PPM requires unsigned 8-bit grayscale or RGB pixels"}

  defp encode(magic, width, height, image) do
    {:ok, <<magic::binary, "\n#{width} #{height}\n255\n", Nx.to_binary(image)::binary>>}
  end

  @spec decode(binary()) :: {:ok, Image.t()} | {:error, String.t()}
  def decode(bytes) do
    with <<"P", n, "\n", rest::binary>> when n == ?5 or n == ?6 <- bytes,
         [width, height, max_value, pixels] <- String.split(rest, [" ", "\n"], parts: 4),
         {width, ""} when width > 0 <- Integer.parse(width),
         {height, ""} when height > 0 <- Integer.parse(height),
         # Only 8-bit samples spanning 0-255, as the encoder writes, are supported.
         {255, ""} <- Integer.parse(max_value) do
      {shape, channels} =
        if n == ?5 do
          {{height, width}, 1}
        else
          {{height, width, 3}, 3}
        end

      if byte_size(pixels) != width * height * channels do
        {:error, "parse error"}
      else
        tensor = Nx.reshape(Nx.from_binary(pixels, {:u, 8}), shape)
        {:ok, %Image{tensor: tensor}}
      end
    else
      _ -> {:error, "parse error"}
    end
  end
end
