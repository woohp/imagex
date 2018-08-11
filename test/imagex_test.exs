defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  test "decode jpeg image" do
    {:ok, jpeg_bytes} = File.read("test/lena.jpg")
    {pixels, width, height, channels} = Imagex.jpeg_decompress(jpeg_bytes)
    assert width == 512
    assert height == 512
    assert channels == 3
    assert byte_size(pixels) == 786_432
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.jpeg_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "decode png image" do
    {:ok, png_bytes} = File.read("test/lena.png")
    {pixels, width, height, channels} = Imagex.png_decompress(png_bytes)
    assert width == 512
    assert height == 512
    assert channels == 3
    assert byte_size(pixels) == 786_432
  end

  test "decode png image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.png_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "invalid png header")
  end

  test "generic decode" do
    {:ok, jpeg_bytes} = File.read("test/lena.jpg")
    {_pixels, width, height, channels} = Imagex.decode(jpeg_bytes)
    assert {width, height, channels} == {512, 512, 3}

    {:ok, png_bytes} = File.read("test/lena.png")
    {_pixels, width, height, channels} = Imagex.decode(png_bytes)
    assert {width, height, channels} == {512, 512, 3}

    assert Imagex.decode(<< 0, 1, 2 >>) == {:error, "failed to decode"}
  end

  test "convert rgb to grayscale" do
    rgb_pixels = << 255, 0, 0, 0, 255, 0, 0, 0, 255 >>
    grayscale_pixels = Imagex.rgb2gray(rgb_pixels)
    assert grayscale_pixels == << 76, 149, 29 >>
  end
end
