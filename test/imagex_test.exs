defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  alias Imagex.Image

  setup do
    {:ok, image} = Imagex.ppm_decode(File.read!("test/assets/lena.ppm"))
    {:ok, image: image}
  end

  defp get_shape(image) do
    {image.height, image.width, image.channels}
  end

  test "decode jpeg image" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    {:ok, %Image{} = image} = Imagex.jpeg_decompress(jpeg_bytes)
    assert get_shape(image) == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432

    # make sure the info field is has the right data
    assert %{jfif_version: {1, 1}, jfif_unit: 0, jfif_density: {72, 72}} = image.info
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.jpeg_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "encode image to jpeg", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.jpeg_compress(test_image)
    assert byte_size(compressed_bytes) < test_image.width * test_image.height * test_image.channels
  end

  test "decode png image", %{image: test_image} do
    png_bytes = File.read!("test/assets/lena.png")
    {:ok, %Image{} = image} = Imagex.png_decompress(png_bytes)
    assert get_shape(image) == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
    assert %{dpi: {72, 72}} = image.info
    assert image.pixels == test_image.pixels  # should it be the same as our test PPM image
    assert get_shape(image) == get_shape(test_image)
  end

  test "decode png image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.png_decompress(<< 0, 1, 2 >>)
    assert String.starts_with?(error_reason, "invalid png header")
  end

  test "decode png - palette" do
    png_bytes = File.read!("test/assets/lena-palette.png")
    {:ok, %Image{} = image} = Imagex.png_decompress(png_bytes)
    assert get_shape(image) == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
  end

  test "decode png - rgba" do
    png_bytes = File.read!("test/assets/lena-rgba.png")
    {:ok, %Image{} = image} = Imagex.png_decompress(png_bytes)
    assert get_shape(image) == {512, 512, 4}
    assert byte_size(image.pixels) == 1_048_576
    assert String.at(image.pixels, 3) == <<191>>  # the alpha channel was set to 75% (or 0.75 * 255)
  end

  test "encode image to png", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.png_compress(test_image)
    assert byte_size(compressed_bytes) < test_image.width * test_image.height * test_image.channels

    # if we decompress again, we should get back the original pixels
    {:ok, image} = Imagex.png_decompress(compressed_bytes)
    assert image.pixels == test_image.pixels  # should it be the same as our test PPM image
    assert get_shape(image) == get_shape(test_image)
  end

  test "decode jpeg-xl image" do
    jxl_bytes = File.read!("test/assets/lena.jxl")
    {:ok, %Image{} = image} = Imagex.jxl_decompress(jxl_bytes)
    assert get_shape(image) == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
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
    assert get_shape(image) == {512, 512, 3}
    assert byte_size(image.pixels) == 786_432
  end

  test "encode ppm", %{image: test_image} do
    assert Imagex.ppm_encode(test_image) == File.read!("test/assets/lena.ppm")
  end

  test "generic decode" do
    {:ok, {:jpeg, %Image{} = image}} = Imagex.decode(File.read!("test/assets/lena.jpg"))
    assert get_shape(image) == {512, 512, 3}

    {:ok, {:png, %Image{} = image}} = Imagex.decode(File.read!("test/assets/lena.png"))
    assert get_shape(image) == {512, 512, 3}

    {:ok, {:jxl, %Image{} = image}} = Imagex.decode(File.read!("test/assets/lena.jxl"))
    assert get_shape(image) == {512, 512, 3}

    {:ok, {:ppm, %Image{} = image}} = Imagex.decode(File.read!("test/assets/lena.ppm"))
    assert get_shape(image) == {512, 512, 3}

    assert Imagex.decode(<< 0, 1, 2 >>) == {:error, "failed to decode"}
  end

  test "open from path directly" do
    {:ok, {:jpeg, %Image{} = image}} = Imagex.open("test/assets/lena.jpg")
    assert get_shape(image) == {512, 512, 3}
  end
end
