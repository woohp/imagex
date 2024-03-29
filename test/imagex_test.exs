defmodule ImagexTest do
  use ExUnit.Case
  doctest Imagex

  alias Imagex.Image

  setup do
    {:ok, image} = Imagex.decode(File.read!("test/assets/lena.ppm"), format: :ppm)
    {:ok, image: image}
  end

  describe "jpeg" do
    test "decode rgb image" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")
      {:ok, %Image{} = image} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert image.tensor.type == {:u, 8}
      assert image.tensor.shape == {512, 512, 3}
    end

    test "encode image raises exception for bad input" do
      {:error, error_reason} = Imagex.decode(<<0, 1, 2>>, format: :jpeg)
      assert String.starts_with?(error_reason, "Not a JPEG file")
    end

    test "encode image rgb image", %{image: test_image} do
      {:ok, compressed_bytes} = Imagex.encode(test_image, :jpeg)
      assert byte_size(compressed_bytes) < Nx.size(test_image.tensor)
    end

    @tag :skip
    test "decode rgb image without parsing exif data" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")
      {:ok, %Image{} = image} = Imagex.decode(jpeg_bytes, format: :jpeg, parse_metadata: false)
      assert image.tensor.type == {:u, 8}
      assert image.tensor.shape == {512, 512, 3}
      assert is_binary(image.metadata)
    end
  end

  describe "png" do
    test "decode rgb image", %{image: test_image} do
      png_bytes = File.read!("test/assets/lena.png")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :png)
      assert image.tensor.shape == {512, 512, 3}

      # should it be the same as our test PPM image
      assert Nx.to_binary(image.tensor) == Nx.to_binary(test_image.tensor)
      assert image.tensor.shape == test_image.tensor.shape
      assert image.metadata == nil
    end

    test "decode image returns :error for bad input" do
      {:error, error_reason} = Imagex.decode(<<0, 1, 2>>, format: :png)
      assert String.starts_with?(error_reason, "invalid png header")
    end

    test "decode grayscale image" do
      png_bytes = File.read!("test/assets/lena-grayscale.png")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :png)
      assert image.tensor.shape == {512, 512}
      assert image.metadata == nil
    end

    test "decode palette image" do
      png_bytes = File.read!("test/assets/lena-palette.png")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :png)
      assert image.tensor.shape == {512, 512, 3}
      assert image.metadata == nil
    end

    test "decode rgba image" do
      png_bytes = File.read!("test/assets/lena-rgba.png")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :png)
      assert image.tensor.shape == {512, 512, 4}
      # the alpha channel was set to 75% (or 0.75 * 255)
      assert String.at(Nx.to_binary(image.tensor), 3) == <<191>>
      assert image.metadata == nil
    end

    test "decode 16bit image" do
      png_bytes = File.read!("test/assets/16bit.png")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :png)
      assert image.tensor.shape == {118, 170, 4}
      assert image.tensor.type == {:u, 16}

      assert Nx.to_flat_list(image.tensor) |> Enum.take(10) == [
               45759,
               46783,
               49727,
               65535,
               45631,
               46655,
               49599,
               65535,
               45663,
               46783
             ]
    end

    test "encode rgb image", %{image: test_image} do
      {:ok, compressed_bytes} = Imagex.encode(test_image, :png)
      assert byte_size(compressed_bytes) < Nx.size(test_image.tensor)

      # if we decompress again, we should get back the original pixels
      {:ok, %{} = image} = Imagex.decode(compressed_bytes, format: :png)
      # should it be the same as our test PPM image
      assert Nx.to_binary(image.tensor) == Nx.to_binary(test_image.tensor)
      assert image.tensor.shape == test_image.tensor.shape
      assert image.metadata == nil
    end

    test "encode rgba image" do
      image1 = Nx.iota({10, 10, 4}, type: :u8)
      {:ok, compressed_bytes} = Imagex.encode(image1, :png)
      {:ok, image2} = Imagex.decode(compressed_bytes, format: :png)
      assert image2.tensor == image1
      assert image2.metadata == nil
    end

    test "encode grayscale image" do
      image1 = Nx.iota({10, 10}, type: :u8)
      {:ok, compressed_bytes} = Imagex.encode(image1, :png)
      {:ok, %Image{} = image2} = Imagex.decode(compressed_bytes, format: :png)
      assert image2.tensor == image1
      assert image2.metadata == nil
    end

    test "encode 16-bit rgb image" do
      image1 = Nx.iota({100, 100, 3}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image1, :png)
      {:ok, %Image{} = image2} = Imagex.decode(compressed_bytes, format: :png)
      assert image2.tensor == image1
      assert image2.metadata == nil
    end

    test "encode 16-bit rgba image" do
      image1 = Nx.iota({100, 100, 4}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image1, :png)
      {:ok, %Image{} = image2} = Imagex.decode(compressed_bytes, format: :png)
      assert image2.tensor == image1
      assert image2.metadata == nil
    end

    test "encode 16-bit grayscale image" do
      image1 = Nx.iota({100, 100}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image1, :png)
      {:ok, %Image{} = image2} = Imagex.decode(compressed_bytes, format: :png)
      assert image2.tensor == image1
      assert image2.metadata == nil
    end

    test "encode 16-bit grayscale-alpha image" do
      image1 = Nx.iota({100, 100, 2}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image1, :png)
      {:ok, image2} = Imagex.decode(compressed_bytes, format: :png)
      assert image2.tensor == image1
      assert image2.metadata == nil
    end
  end

  describe "jpeg-xl" do
    test "decode rgb image" do
      jxl_bytes = File.read!("test/assets/lena.jxl")
      {:ok, %Image{} = image} = Imagex.decode(jxl_bytes, format: :jxl)
      assert image.tensor.shape == {512, 512, 3}
      assert image.metadata == nil
    end

    test "decode rgba image" do
      jxl_bytes = File.read!("test/assets/lena-rgba.jxl")
      {:ok, %Image{} = image} = Imagex.decode(jxl_bytes, format: :jxl)
      assert image.tensor.shape == {512, 512, 4}
      assert image.metadata == nil
    end

    test "decode grayscale image" do
      jxl_bytes = File.read!("test/assets/lena-grayscale.jxl")
      {:ok, %Image{} = image} = Imagex.decode(jxl_bytes, format: :jxl)
      assert image.tensor.shape == {512, 512}
      assert image.metadata == nil
    end

    test "decode 16-bit image" do
      png_bytes = File.read!("test/assets/16bit.jxl")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :jxl)
      assert image.tensor.shape == {118, 170, 4}
      assert image.tensor.type == {:u, 16}
      assert image.metadata == nil

      assert Nx.to_flat_list(image.tensor) |> Enum.take(10) == [
               45759,
               46783,
               49727,
               65535,
               45631,
               46655,
               49599,
               65535,
               45663,
               46783
             ]
    end

    test "encode rgb image", %{image: test_image} do
      png_bytes = File.read!("test/assets/lena.png")

      {:ok, compressed_bytes} = Imagex.encode(test_image, :jxl)
      assert byte_size(compressed_bytes) < byte_size(png_bytes)
    end

    test "encode rgb image lossless", %{image: test_image} do
      {:ok, compressed_bytes} = Imagex.encode(test_image, :jxl)
      {:ok, compressed_bytes_lossless} = Imagex.encode(test_image, :jxl, lossless: true)
      assert byte_size(compressed_bytes_lossless) > byte_size(compressed_bytes)

      # we decompress the lossless compressed bytes, we should get back the exact same input
      {:ok, %Image{} = roundtrip_image_lossless} = Imagex.decode(compressed_bytes_lossless, format: :jxl)
      assert roundtrip_image_lossless.tensor == test_image.tensor
    end

    test "encode with increasing distances", %{image: test_image} do
      # If we encode images with increasing distance, the resulting file size should be smaller and smaller
      compressed_sizes =
        for distance <- 0..15 do
          {:ok, compressed_bytes} = Imagex.encode(test_image, :jxl, lossless: false, distance: distance)
          byte_size(compressed_bytes)
        end

      for [first_size, second_size] <- Enum.chunk_every(compressed_sizes, 2, 1, :discard) do
        assert second_size < first_size
      end
    end

    test "encode with increasing efforts", %{image: test_image} do
      # If we encode images with increasing effort, the resulting file size should be smaller and smaller
      compressed_sizes =
        for effort <- 1..9 do
          {:ok, compressed_bytes} = Imagex.encode(test_image, :jxl, lossless: false, effort: effort)
          byte_size(compressed_bytes)
        end

      assert List.last(compressed_sizes) < List.first(compressed_sizes)
    end

    test "encode 16-bit image" do
      image = Nx.iota({8, 8, 3}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)

      {:ok, %Image{} = decoded_image} = Imagex.decode(compressed_bytes, format: :jxl)
      assert decoded_image.tensor == image
    end

    test "encode 16-bit rgba image" do
      image = Nx.iota({8, 8, 4}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)

      {:ok, %Image{} = decoded_image} = Imagex.decode(compressed_bytes, format: :jxl)
      assert decoded_image.tensor == image
    end

    test "encode 16-bit grayscale image" do
      image = Nx.iota({8, 8, 2}, type: :u16)
      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)

      {:ok, %Image{} = decoded_image} = Imagex.decode(compressed_bytes, format: :jxl)
      assert decoded_image.tensor == image
    end

    test "transcode from jpeg" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")

      # do a roundtrip conversion: jpeg -> jxl -> pixels
      # check that pixels ~= jpeg pixels, (almost equals b/c jxl might decode a bit differently)
      {:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes)
      assert byte_size(jxl_bytes) < byte_size(jpeg_bytes)

      {:ok, %Image{} = image_from_jxl} = Imagex.decode(jxl_bytes, format: :jxl)
      {:ok, %Image{} = image_from_jpeg} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert image_from_jxl.metadata.exif == image_from_jpeg.metadata.exif
      exif = image_from_jxl.metadata.exif

      assert exif == %{
               ifd0: %{
                 exif: %{pixel_y_dimension: 512, pixel_x_dimension: 512, color_space: 1},
                 orientation: 1,
                 resolution_unit: 2,
                 y_resolution: {72, 1},
                 x_resolution: {72, 1}
               }
             }

      max_diff =
        Nx.subtract(
          Nx.as_type(image_from_jxl.tensor, {:s, 16}),
          Nx.as_type(image_from_jpeg.tensor, {:s, 16})
        )
        |> Nx.abs()
        |> Nx.reduce_max()
        |> Nx.to_number()

      assert max_diff <= 20
    end

    test "transcode from jpeg with different efforts" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")

      {:ok, low_effort_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, effort: 3)
      {:ok, high_effort_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, effort: 9)

      assert byte_size(high_effort_bytes) < byte_size(low_effort_bytes)
    end

    test "transcode from jpeg without metadata" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")

      {:ok, bytes_with_metadata} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, store_jpeg_metadata: true)
      {:ok, bytes_without_metadata} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, store_jpeg_metadata: false)

      assert byte_size(bytes_with_metadata) > byte_size(bytes_without_metadata)
    end

    test "decode transcoded jpeg image" do
      jxl_bytes = File.read!("test/assets/lena-transcode.jxl")
      {:ok, jpeg_bytes} = Imagex.Jxl.transcode_to_jpeg(jxl_bytes)
      assert byte_size(jpeg_bytes) == 68750

      # should be able to decode the jpeg bytes
      {:ok, %Image{} = image} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert image.tensor.shape == {512, 512, 3}
    end

    test "decode transcoded jpeg image fails gracefully when not possible" do
      # for a file that did not come from a jpeg to begin with, it should fail gracefully
      jxl_bytes = File.read!("test/assets/lena.jxl")
      {:error, reason} = Imagex.Jxl.transcode_to_jpeg(jxl_bytes)
      assert String.starts_with?(reason, "cannot be transcoded")
    end
  end

  test "decode ppm" do
    ppm_bytes = File.read!("test/assets/lena.ppm")
    {:ok, %Image{} = image} = Imagex.decode(ppm_bytes, format: :ppm)
    assert image.tensor.shape == {512, 512, 3}
    assert image.metadata == nil
  end

  test "encode ppm", %{image: test_image} do
    assert {:ok, compressed} = Imagex.encode(test_image, :ppm)
    assert compressed == File.read!("test/assets/lena.ppm")
  end

  test "decode bmp rgb pos height", %{image: test_image} do
    bmp_bytes = File.read!("test/assets/lena-rgb-pos-height.bmp")
    {:ok, %Image{} = image} = Imagex.decode(bmp_bytes, format: :bmp)
    assert image.tensor.shape == {512, 512, 3}
    assert Nx.to_binary(image.tensor) == Nx.to_binary(test_image.tensor)
    assert image.metadata == nil
  end

  test "decode bmp rgba neg height", %{image: test_image} do
    bmp_bytes = File.read!("test/assets/lena-rgba-neg-height.bmp")
    {:ok, %Image{} = image} = Imagex.decode(bmp_bytes, format: :bmp)
    assert image.tensor.shape == {512, 512, 4}
    assert image.metadata == nil

    # get the rgb portion only, which should then equal the test_image
    {h, w, 3} = test_image.tensor.shape
    rgb_only_image = Nx.slice(image.tensor, [0, 0, 0], [h, w, 3])
    assert Nx.to_binary(rgb_only_image) == Nx.to_binary(test_image.tensor)
  end

  test "generic decode" do
    {:ok, %Image{} = image} = Imagex.decode(File.read!("test/assets/lena.jpg"))
    assert image.tensor.shape == {512, 512, 3}

    {:ok, %Image{} = image} = Imagex.decode(File.read!("test/assets/lena.png"))
    assert image.tensor.shape == {512, 512, 3}
    assert image.metadata == nil

    {:ok, %Image{} = image} = Imagex.decode(File.read!("test/assets/lena.jxl"))
    assert image.tensor.shape == {512, 512, 3}
    assert image.metadata == nil

    {:ok, %Image{} = image} = Imagex.decode(File.read!("test/assets/lena.ppm"))
    assert image.tensor.shape == {512, 512, 3}
    assert image.metadata == nil

    assert Imagex.decode(<<0, 1, 2>>) == {:error, "failed to decode"}
  end

  test "open from path directly" do
    {:ok, %Image{} = image} = Imagex.open("test/assets/lena.jpg")
    assert image.tensor.shape == {512, 512, 3}
  end

  test "load and render pdf document" do
    bytes = File.read!("test/assets/lena.pdf")
    {:ok, %Imagex.Pdf{} = pdf} = Imagex.decode(bytes, format: :pdf)
    assert pdf.num_pages == 1

    {:ok, %Image{} = image} = Imagex.Pdf.render_page(pdf, 0)
    assert image.tensor.shape == {512, 512, 4}

    # double the default dpi of 72
    {:ok, %Image{} = image} = Imagex.Pdf.render_page(pdf, 0, dpi: 144)
    assert image.tensor.shape == {1024, 1024, 4}
  end

  test "load and render tiff document" do
    bytes = File.read!("test/assets/lena.tiff")
    {:ok, %Imagex.Tiff{} = tiff} = Imagex.decode(bytes, format: :tiff)
    assert tiff.num_pages == 1

    {:ok, %Image{} = image} = Imagex.Tiff.render_page(tiff, 0)
    assert image.tensor.shape == {512, 512, 4}
  end
end
