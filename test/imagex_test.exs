defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  test "decode jpeg image" do
    {:ok, jpeg_bytes} = File.read("test/lena.jpg")
    {pixels, width, height, channels} = Imagex.jpeg_decompress(jpeg_bytes)
    assert width == 1960
    assert height == 1960
    assert channels == 3
    assert byte_size(pixels) == 11_524_800
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.jpeg_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "convert rgb to grayscale" do
    rgb_pixels = << 255, 0, 0, 0, 255, 0, 0, 0, 255 >>
    grayscale_pixels = Imagex.rgb2gray(rgb_pixels)
    assert grayscale_pixels == << 76, 149, 29 >>
  end
end
