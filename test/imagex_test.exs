defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  test "decode jpeg image" do
    jpeg_bytes = File.read!("test/lena.jpg")
    {:ok, {pixels, width, height, channels}} = Imagex.jpeg_decompress(jpeg_bytes)
    assert {width, height, channels} == {512, 512, 3}
    assert byte_size(pixels) == 786_432
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.jpeg_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "encode image to jpeg" do
    jpeg_bytes = File.read!("test/lena.jpg")
    {:ok, {pixels, width, height, channels}} = Imagex.jpeg_decompress(jpeg_bytes)
    {:ok, compressed_bytes} = Imagex.jpeg_compress(pixels, width, height, channels)
    assert byte_size(compressed_bytes) < width * height * channels
  end

  test "decode png image" do
    png_bytes = File.read!("test/lena.png")
    {:ok, {pixels, width, height, channels}} = Imagex.png_decompress(png_bytes)
    assert {width, height, channels} == {512, 512, 3}
    assert byte_size(pixels) == 786_432
  end

  test "decode png image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.png_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "invalid png header")
  end

  test "encode image to png" do
    png_bytes = File.read!("test/lena.png")
    {:ok, image = {pixels, width, height, channels}} = Imagex.png_decompress(png_bytes)
    {:ok, compressed_bytes} = Imagex.png_compress(pixels, width, height, channels)
    assert byte_size(compressed_bytes) < width * height * channels

    # if we decompress again, we should get back the original pixels
    {:ok, new_image} = Imagex.png_decompress(png_bytes)
    assert new_image == image
  end

  test "decode jpeg-xl image" do
    jxl_bytes = File.read!("test/lena.jxl")
    {:ok, {pixels, width, height, channels}} = Imagex.jxl_decompress(jxl_bytes)
    assert {width, height, channels} == {512, 512, 3}
    assert byte_size(pixels) == 786_432
  end

  test "encode image to jpeg-xl" do
    png_bytes = File.read!("test/lena.png")
    {:ok, {pixels, width, height, channels}} = Imagex.png_decompress(png_bytes)

    {:ok, compressed_bytes} = Imagex.jxl_compress(pixels, width, height, channels)
    assert byte_size(compressed_bytes) < byte_size(png_bytes)
  end

  test "generic decode" do
    jpeg_bytes = File.read!("test/lena.jpg")
    {:jpeg, {_pixels, width, height, channels}} = Imagex.decode(jpeg_bytes)
    assert {width, height, channels} == {512, 512, 3}

    png_bytes = File.read!("test/lena.png")
    {:png, {_pixels, width, height, channels}} = Imagex.decode(png_bytes)
    assert {width, height, channels} == {512, 512, 3}

    jxl_bytes = File.read!("test/lena.jxl")
    {:jxl, {_pixels, width, height, channels}} = Imagex.decode(jxl_bytes)
    assert {width, height, channels} == {512, 512, 3}

    assert Imagex.decode(<< 0, 1, 2 >>) == nil
  end

  test "convert rgb to grayscale" do
    rgb_pixels = << 255, 0, 0, 0, 255, 0, 0, 0, 255 >>
    grayscale_pixels = Imagex.rgb2gray(rgb_pixels)
    assert grayscale_pixels == << 76, 149, 29 >>
  end
end
