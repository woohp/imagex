defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  alias Imagex.Image

  test "decode jpeg image" do
    jpeg_bytes = File.read!("test/lena.jpg")
    {:ok, %Image{} = image} = Imagex.jpeg_decompress(jpeg_bytes)
    assert {image.width, image.height, image.channels} == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.jpeg_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "encode image to jpeg" do
    jpeg_bytes = File.read!("test/lena.jpg")
    {:ok, image} = Imagex.jpeg_decompress(jpeg_bytes)
    {:ok, compressed_bytes} = Imagex.jpeg_compress(image.pixels, image.width, image.height, image.channels)
    assert byte_size(compressed_bytes) < image.width * image.height * image.channels
  end

  test "decode png image" do
    png_bytes = File.read!("test/lena.png")
    {:ok, %Image{} = image} = Imagex.png_decompress(png_bytes)
    assert {image.width, image.height, image.channels} == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
  end

  test "decode png image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.png_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "invalid png header")
  end

  test "encode image to png" do
    png_bytes = File.read!("test/lena.png")
    {:ok, image} = Imagex.png_decompress(png_bytes)
    {:ok, compressed_bytes} = Imagex.png_compress(image.pixels, image.width, image.height, image.channels)
    assert byte_size(compressed_bytes) < image.width * image.height * image.channels

    # if we decompress again, we should get back the original pixels
    {:ok, new_image} = Imagex.png_decompress(png_bytes)
    assert new_image == image
  end

  test "decode jpeg-xl image" do
    jxl_bytes = File.read!("test/lena.jxl")
    {:ok, %Image{} = image} = Imagex.jxl_decompress(jxl_bytes)
    assert {image.width, image.height, image.channels} == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
  end

  test "encode image to jpeg-xl" do
    png_bytes = File.read!("test/lena.png")
    {:ok, image} = Imagex.png_decompress(png_bytes)

    {:ok, compressed_bytes} = Imagex.jxl_compress(image.pixels, image.width, image.height, image.channels)
    assert byte_size(compressed_bytes) < byte_size(png_bytes)
  end

  test "generic decode" do
    jpeg_bytes = File.read!("test/lena.jpg")
    {:jpeg, %Image{} = image} = Imagex.decode(jpeg_bytes)
    assert {image.width, image.height, image.channels} == {512, 512, 3}

    png_bytes = File.read!("test/lena.png")
    {:png, %Image{} = image} = Imagex.decode(png_bytes)
    assert {image.width, image.height, image.channels} == {512, 512, 3}

    jxl_bytes = File.read!("test/lena.jxl")
    {:jxl, %Image{} = image} = Imagex.decode(jxl_bytes)
    assert {image.width, image.height, image.channels} == {512, 512, 3}

    assert Imagex.decode(<< 0, 1, 2 >>) == nil
  end
end
