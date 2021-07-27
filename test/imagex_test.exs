defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  alias Nx.Tensor

  setup do
    {:ok, image} = Imagex.ppm_decode(File.read!("test/assets/lena.ppm"))
    {:ok, image: image}
  end

  test "decode jpeg image" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    {:ok, %Tensor{} = image} = Imagex.jpeg_decompress(jpeg_bytes)
    assert image.type == {:u, 8}
    assert image.shape == {512, 512, 3}
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.jpeg_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "encode image to jpeg", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.jpeg_compress(test_image)
    assert byte_size(compressed_bytes) < Nx.size(test_image)
  end

  test "decode png image", %{image: test_image} do
    png_bytes = File.read!("test/assets/lena.png")
    {:ok, %Tensor{} = image} = Imagex.png_decompress(png_bytes)
    assert image.shape== {512, 512, 3}

    assert Nx.to_binary(image) == Nx.to_binary(test_image)  # should it be the same as our test PPM image
    assert image.shape == test_image.shape
  end

  test "decode png image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.png_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "invalid png header")
  end

  test "decode png - palette" do
    png_bytes = File.read!("test/assets/lena-palette.png")
    {:ok, %Tensor{} = image} = Imagex.png_decompress(png_bytes)
    assert image.shape == {512, 512, 3}
  end

  test "decode png - rgba" do
    png_bytes = File.read!("test/assets/lena-rgba.png")
    {:ok, %Tensor{} = image} = Imagex.png_decompress(png_bytes)
    assert image.shape == {512, 512, 4}
    assert String.at(Nx.to_binary(image), 3) == <<191>>  # the alpha channel was set to 75% (or 0.75 * 255)
  end

  test "encode image to png", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.png_compress(test_image)
    assert byte_size(compressed_bytes) < Nx.size(test_image)

    # if we decompress again, we should get back the original pixels
    {:ok, image} = Imagex.png_decompress(compressed_bytes)
    assert Nx.to_binary(image) == Nx.to_binary(test_image)  # should it be the same as our test PPM image
    assert image.shape == test_image.shape
  end

  test "decode jpeg-xl image" do
    jxl_bytes = File.read!("test/assets/lena.jxl")
    {:ok, %Tensor{} = image} = Imagex.jxl_decompress(jxl_bytes)
    assert image.shape == {512, 512, 3}
  end

  test "encode image to jpeg-xl" do
    png_bytes = File.read!("test/assets/lena.png")
    {:ok, image} = Imagex.png_decompress(png_bytes)

    {:ok, compressed_bytes} = Imagex.jxl_compress(image)
    assert byte_size(compressed_bytes) < byte_size(png_bytes)
  end

  test "encode jpeg-xl lossless", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.jxl_compress(test_image)
    {:ok, compressed_bytes_lossless} = Imagex.jxl_compress(test_image, lossless: true)
    assert byte_size(compressed_bytes_lossless) > byte_size(compressed_bytes)

    # we decompress the lossless compressed bytes, we should get back the exact same input
    {:ok, roundtrip_image_lossless} = Imagex.jxl_decompress(compressed_bytes_lossless)
    assert roundtrip_image_lossless == test_image
  end

  test "encode jpeg-xl with different distances", %{image: test_image} do
    compressed_sizes = for distance <- 0..15 do
      {:ok, compressed_bytes} = Imagex.jxl_compress(test_image, lossless: false, distance: distance)
      byte_size(compressed_bytes)
    end

    for [first_size, second_size] <- Enum.chunk_every(compressed_sizes, 2, 1, :discard) do
      assert second_size < first_size
    end
  end

  test "decode ppm" do
    ppm_bytes = File.read!("test/assets/lena.ppm")
    {:ok, image} = Imagex.ppm_decode(ppm_bytes)
    assert image.shape == {512, 512, 3}
  end

  test "encode ppm", %{image: test_image} do
    assert Imagex.ppm_encode(test_image) == File.read!("test/assets/lena.ppm")
  end

  test "generic decode" do
    {:ok, {:jpeg, %Tensor{} = image}} = Imagex.decode(File.read!("test/assets/lena.jpg"))
    assert image.shape == {512, 512, 3}

    {:ok, {:png, %Tensor{} = image}} = Imagex.decode(File.read!("test/assets/lena.png"))
    assert image.shape == {512, 512, 3}

    {:ok, {:jxl, %Tensor{} = image}} = Imagex.decode(File.read!("test/assets/lena.jxl"))
    assert image.shape == {512, 512, 3}

    {:ok, {:ppm, %Tensor{} = image}} = Imagex.decode(File.read!("test/assets/lena.ppm"))
    assert image.shape == {512, 512, 3}

    assert Imagex.decode(<< 0, 1, 2 >>) == {:error, "failed to decode"}
  end

  test "open from path directly" do
    {:ok, {:jpeg, %Tensor{} = image}} = Imagex.open("test/assets/lena.jpg")
    assert image.shape == {512, 512, 3}
  end
end
