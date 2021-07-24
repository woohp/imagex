defmodule Imagex.PPM do
  def encode(image = %Imagex.Image{channels: 1}) do
    <<"P5\n#{image.width} #{image.height}\n255\n", image.pixels::binary>>
  end

  def encode(image = %Imagex.Image{channels: 3}) do
    <<"P6\n#{image.width} #{image.height}\n255\n", image.pixels::binary>>
  end

  def decode(bytes) do
    with <<"P", n, "\n", rest::binary>> when n == ?5 or n == ?6 <- bytes,
         [width, height, _max_value, pixels] <- String.split(rest, [" ", "\n"], parts: 4),
         {width, ""} <- Integer.parse(width),
         {height, ""} <- Integer.parse(height) do
      channels = if n == ?5, do: 1, else: 3

      if byte_size(pixels) != width * height * channels do
        {:error, "parse error"}
      else
        {:ok,
         %Imagex.Image{
           width: width,
           height: height,
           channels: channels,
           pixels: pixels
         }}
      end
    else
      _ -> {:error, "parse error"}
    end
  end
end
