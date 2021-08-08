defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  alias Nx.Tensor

  setup do
    {:ok, image} = Imagex.decode(File.read!("test/assets/lena.ppm"), format: :ppm)
    {:ok, image: image}
  end

  test "decode jpeg image" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    {:ok, %Tensor{} = image} = Imagex.decode(jpeg_bytes, format: :jpeg)
    assert image.type == {:u, 8}
    assert image.shape == {512, 512, 3}
  end

  test "decode jpeg image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.decode(<< 0, 1, 2 >>, format: :jpeg)
    assert String.starts_with?(error_reason, "Not a JPEG file")
  end

  test "encode image to jpeg", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.encode(test_image, :jpeg)
    assert byte_size(compressed_bytes) < Nx.size(test_image)
  end

  test "decode png image", %{image: test_image} do
    png_bytes = File.read!("test/assets/lena.png")
    {:ok, %Tensor{} = image} = Imagex.decode(png_bytes, format: :png)
    assert image.shape== {512, 512, 3}

    assert Nx.to_binary(image) == Nx.to_binary(test_image)  # should it be the same as our test PPM image
    assert image.shape == test_image.shape
  end

  test "decode png image raises exception for bad stuff" do
    {:error, error_reason} = Imagex.decode(<< 0, 1, 2 >>, format: :png)
    assert String.starts_with?(error_reason, "invalid png header")
  end

  test "decode png - palette" do
    png_bytes = File.read!("test/assets/lena-palette.png")
    {:ok, %Tensor{} = image} = Imagex.decode(png_bytes, format: :png)
    assert image.shape == {512, 512, 3}
  end

  test "decode png - rgba" do
    png_bytes = File.read!("test/assets/lena-rgba.png")
    {:ok, %Tensor{} = image} = Imagex.decode(png_bytes, format: :png)
    assert image.shape == {512, 512, 4}
    assert String.at(Nx.to_binary(image), 3) == <<191>>  # the alpha channel was set to 75% (or 0.75 * 255)
  end

  test "encode image to png", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.encode(test_image, :png)
    assert byte_size(compressed_bytes) < Nx.size(test_image)

    # if we decompress again, we should get back the original pixels
    {:ok, image} = Imagex.decode(compressed_bytes, format: :png)
    assert Nx.to_binary(image) == Nx.to_binary(test_image)  # should it be the same as our test PPM image
    assert image.shape == test_image.shape
  end

  test "decode jpeg-xl image" do
    jxl_bytes = File.read!("test/assets/lena.jxl")
    {:ok, %Tensor{} = image} = Imagex.decode(jxl_bytes, format: :jxl)
    assert image.shape == {512, 512, 3}
  end

  test "encode image to jpeg-xl" do
    png_bytes = File.read!("test/assets/lena.png")
    {:ok, image} = Imagex.decode(png_bytes, format: :png)

    {:ok, compressed_bytes} = Imagex.encode(image, :jxl)
    assert byte_size(compressed_bytes) < byte_size(png_bytes)
  end

  test "encode jpeg-xl lossless", %{image: test_image} do
    {:ok, compressed_bytes} = Imagex.encode(test_image, :jxl)
    {:ok, compressed_bytes_lossless} = Imagex.encode(test_image, :jxl, lossless: true)
    assert byte_size(compressed_bytes_lossless) > byte_size(compressed_bytes)

    # we decompress the lossless compressed bytes, we should get back the exact same input
    {:ok, roundtrip_image_lossless} = Imagex.decode(compressed_bytes_lossless, format: :jxl)
    assert roundtrip_image_lossless == test_image
  end

  test "encode jpeg-xl with different distances", %{image: test_image} do
    compressed_sizes = for distance <- 0..15 do
      {:ok, compressed_bytes} = Imagex.encode(test_image, :jxl, lossless: false, distance: distance)
      byte_size(compressed_bytes)
    end

    for [first_size, second_size] <- Enum.chunk_every(compressed_sizes, 2, 1, :discard) do
      assert second_size < first_size
    end
  end

  test "jpeg-xl transcode from jpeg" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")

    # do a roundtrip conversion: jpeg -> jxl -> pixels
    # check that pixels ~= jpeg pixels, (almost equals b/c jxl might decode a bit differently)
    {:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes)
    assert byte_size(jxl_bytes) < byte_size(jpeg_bytes)

    {:ok, image_from_jxl} = Imagex.decode(jxl_bytes, format: :jxl)
    {:ok, image_from_jpeg} = Imagex.decode(jpeg_bytes, format: :jpeg)

    max_diff = Nx.subtract(
      Nx.as_type(image_from_jxl, {:s, 16}),
      Nx.as_type(image_from_jpeg, {:s, 16})
    )
    |> Nx.abs()
    |> Nx.reduce_max()
    |> Nx.to_scalar()

    assert max_diff <= 20
  end

  test "jpeg-xl transcode from jpeg with different efforts" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")

    {:ok, low_effort_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, effort: 3)
    {:ok, high_effort_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, effort: 9)

    assert byte_size(high_effort_bytes) < byte_size(low_effort_bytes)
  end

  test "decode ppm" do
    ppm_bytes = File.read!("test/assets/lena.ppm")
    {:ok, image} = Imagex.decode(ppm_bytes, format: :ppm)
    assert image.shape == {512, 512, 3}
  end

  test "encode ppm", %{image: test_image} do
    assert Imagex.encode(test_image, :ppm) == File.read!("test/assets/lena.ppm")
  end

  test "decode bmp rgb pos height", %{image: test_image} do
    bmp_bytes = File.read!("test/assets/lena-rgb-pos-height.bmp")
    {:ok, image} = Imagex.decode(bmp_bytes, format: :bmp)
    assert image.shape == {512, 512, 3}
    assert Nx.to_binary(image) == Nx.to_binary(test_image)
  end

  test "decode bmp rgba neg height", %{image: test_image} do
    bmp_bytes = File.read!("test/assets/lena-rgba-neg-height.bmp")
    {:ok, image} = Imagex.decode(bmp_bytes, format: :bmp)
    assert image.shape == {512, 512, 4}

    # get the rgb portion only, which should then equal the test_image
    {h, w, 3} = test_image.shape
    rgb_only_image = Nx.slice(image, [0, 0, 0], [h, w, 3])
    assert Nx.to_binary(rgb_only_image) == Nx.to_binary(test_image)
  end

  test "generic decode" do
    {:ok, %Tensor{} = image} = Imagex.decode(File.read!("test/assets/lena.jpg"))
    assert image.shape == {512, 512, 3}

    {:ok, %Tensor{} = image} = Imagex.decode(File.read!("test/assets/lena.png"))
    assert image.shape == {512, 512, 3}

    {:ok, %Tensor{} = image} = Imagex.decode(File.read!("test/assets/lena.jxl"))
    assert image.shape == {512, 512, 3}

    {:ok, %Tensor{} = image} = Imagex.decode(File.read!("test/assets/lena.ppm"))
    assert image.shape == {512, 512, 3}

    assert Imagex.decode(<< 0, 1, 2 >>) == {:error, "failed to decode"}
  end

  test "open from path directly" do
    {:ok, %Tensor{} = image} = Imagex.open("test/assets/lena.jpg")
    assert image.shape == {512, 512, 3}
  end

  test "load and render pdf document" do
    bytes = File.read!("test/assets/lena.pdf")
    {:ok, %Imagex.Pdf{} = pdf} = Imagex.decode(bytes, format: :pdf)
    assert pdf.num_pages == 1

    {:ok, %Nx.Tensor{} = image} = Imagex.Pdf.render_page(pdf, 0)
    assert image.shape == {512, 512, 4}

    {:ok, %Nx.Tensor{} = image} = Imagex.Pdf.render_page(pdf, 0, dpi: 144)  # double the default dpi of 72
    assert image.shape == {1024, 1024, 4}
  end

  test "load and render tiff document" do
    bytes = File.read!("test/assets/lena.tiff")
    {:ok, %Imagex.Tiff{} = tiff} = Imagex.decode(bytes, format: :tiff)
    assert tiff.num_pages == 1

    {:ok, %Nx.Tensor{} = image} = Imagex.Tiff.render_page(tiff, 0)
    assert image.shape == {512, 512, 4}
  end
end
