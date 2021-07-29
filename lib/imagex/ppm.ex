defmodule Imagex.PPM do
  def encode(%Nx.Tensor{shape: {height, width}} = image) do
    pixels = Nx.to_binary(image)
    <<"P5\n#{width} #{height}\n255\n", pixels::binary>>
  end

  def encode(%Nx.Tensor{shape: {height, width, 3}} = image) do
    pixels = Nx.to_binary(image)
    <<"P6\n#{width} #{height}\n255\n", pixels::binary>>
  end

  def decode(bytes) do
    with <<"P", n, "\n", rest::binary>> when n == ?5 or n == ?6 <- bytes,
         [width, height, _max_value, pixels] <- String.split(rest, [" ", "\n"], parts: 4),
         {width, ""} <- Integer.parse(width),
         {height, ""} <- Integer.parse(height) do
      {shape, channels} =
        if n == ?5 do
          {{height, width}, 1}
        else
          {{height, width, 3}, 3}
        end

      if byte_size(pixels) != width * height * channels do
        {:error, "parse error"}
      else
        {:ok, Nx.reshape(Nx.from_binary(pixels, {:u, 8}), shape)}
      end
    else
      _ -> {:error, "parse error"}
    end
  end
end
