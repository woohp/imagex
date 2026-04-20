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

    test "encode image preserves exif metadata from Image struct", %{image: test_image} do
      {:ok, %Image{metadata: metadata}} = Imagex.decode(File.read!("test/assets/lena.jpg"), format: :jpeg)
      image = %Image{tensor: test_image.tensor, metadata: metadata}

      {:ok, compressed_bytes} = Imagex.encode(image, :jpeg)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jpeg)

      assert encoded_metadata.exif == metadata.exif
    end

    test "encode image preserves xmp metadata", %{image: test_image} do
      xmp = sample_xmp("jpeg-xmp")
      image = %Image{tensor: test_image.tensor, metadata: %{xmp: xmp}}

      {:ok, compressed_bytes} = Imagex.encode(image, :jpeg)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jpeg)

      assert encoded_metadata.xmp == xmp
    end

    test "encode image preserves thumbnail-bearing exif metadata" do
      jpeg_bytes = File.read!("test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg")
      {:ok, %Image{} = source_image} = Imagex.decode(jpeg_bytes, format: :jpeg)

      {:ok, compressed_bytes} = Imagex.encode(source_image, :jpeg)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(compressed_bytes, format: :jpeg)

      assert metadata.exif.ifd1.thumbnail_data == source_image.metadata.exif.ifd1.thumbnail_data

      assert metadata.exif.ifd1.jpeg_interchange_format_length ==
               byte_size(source_image.metadata.exif.ifd1.thumbnail_data)
    end

    test "encode image returns error for unsupported exif values", %{image: test_image} do
      image = %Image{tensor: test_image.tensor, metadata: %{exif: %{ifd0: %{orientation: %{bad: true}}}}}

      assert {:error, reason} = Imagex.encode(image, :jpeg)
      assert String.contains?(reason, "unsupported EXIF")
    end

    test "encode image returns error for malformed exif metadata", %{image: test_image} do
      image = %Image{tensor: test_image.tensor, metadata: %{exif: :bad_metadata}}

      assert {:error, "EXIF metadata must be a map, got: :bad_metadata"} = Imagex.encode(image, :jpeg)
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

      %{png_chunks: [%{text: xmp_text}]} = image.metadata

      assert image.metadata == %{
               xmp: xmp_text,
               png_chunks: [
                 %{
                   keyword: "XML:com.adobe.xmp",
                   text: xmp_text,
                   language_tag: "",
                   translated_keyword: ""
                 }
               ]
             }

      assert xmp_text =~ "<x:xmpmeta"
      assert image.metadata.xmp == xmp_text
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

    test "encode image preserves png text metadata", %{image: test_image} do
      image = %Image{
        tensor: test_image.tensor,
        metadata: %{png_chunks: [%{keyword: "Author", text: "Imagex"}, %{keyword: "Comment", text: "Hello"}]}
      }

      {:ok, compressed_bytes} = Imagex.encode(image, :png)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(compressed_bytes, format: :png)

      assert metadata == %{
               png_chunks: [
                 %{keyword: "Author", text: "Imagex", language_tag: "", translated_keyword: ""},
                 %{keyword: "Comment", text: "Hello", language_tag: "", translated_keyword: ""}
               ]
             }
    end

    test "encode image writes metadata.xmp as a PNG XMP chunk", %{image: test_image} do
      xmp = sample_xmp("png-xmp")
      image = %Image{tensor: test_image.tensor, metadata: %{xmp: xmp}}

      {:ok, compressed_bytes} = Imagex.encode(image, :png)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(compressed_bytes, format: :png)

      assert metadata.xmp == xmp

      assert metadata.png_chunks == [
               %{
                 keyword: "XML:com.adobe.xmp",
                 text: xmp,
                 language_tag: "",
                 translated_keyword: ""
               }
             ]
    end

    test "encode image rejects duplicate PNG XMP metadata", %{image: test_image} do
      image = %Image{
        tensor: test_image.tensor,
        metadata: %{
          xmp: sample_xmp("png-duplicate"),
          png_chunks: [%{keyword: "XML:com.adobe.xmp", text: sample_xmp("png-existing")}]
        }
      }

      assert {:error, "metadata.xmp cannot be combined with PNG XMP chunks in metadata.png_chunks"} =
               Imagex.encode(image, :png)
    end

    test "encode image preserves png iTXt metadata fields", %{image: test_image} do
      image = %Image{
        tensor: test_image.tensor,
        metadata: %{
          png_chunks: [
            %{
              keyword: "Title",
              text: "Miyazaki 宮崎",
              language_tag: "ja",
              translated_keyword: "タイトル"
            }
          ]
        }
      }

      {:ok, compressed_bytes} = Imagex.encode(image, :png)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(compressed_bytes, format: :png)

      assert metadata == %{
               png_chunks: [
                 %{
                   keyword: "Title",
                   text: "Miyazaki 宮崎",
                   language_tag: "ja",
                   translated_keyword: "タイトル"
                 }
               ]
             }
    end

    test "encode image preserves png text order and duplicate keywords", %{image: test_image} do
      image = %Image{
        tensor: test_image.tensor,
        metadata: %{png_chunks: [%{keyword: "Tag", text: "first"}, %{keyword: "Tag", text: "second"}]}
      }

      {:ok, compressed_bytes} = Imagex.encode(image, :png)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(compressed_bytes, format: :png)

      assert metadata == %{
               png_chunks: [
                 %{keyword: "Tag", text: "first", language_tag: "", translated_keyword: ""},
                 %{keyword: "Tag", text: "second", language_tag: "", translated_keyword: ""}
               ]
             }
    end

    test "encode image returns error for malformed png metadata", %{image: test_image} do
      image = %Image{tensor: test_image.tensor, metadata: %{png_chunks: :bad_metadata}}

      assert {:error, "PNG metadata must be a list, got: :bad_metadata"} = Imagex.encode(image, :png)
    end

    test "encode image returns error for malformed png text entry", %{image: test_image} do
      image = %Image{tensor: test_image.tensor, metadata: %{png_chunks: [%{keyword: "Tag", text: 123}]}}

      assert {:error, "PNG text values must be binaries, got: 123"} = Imagex.encode(image, :png)
    end

    test "encode image returns error for malformed png iTXt language tag", %{image: test_image} do
      image = %Image{
        tensor: test_image.tensor,
        metadata: %{png_chunks: [%{keyword: "Tag", text: "value", language_tag: 123}]}
      }

      assert {:error, "PNG language tags must be binaries, got: 123"} = Imagex.encode(image, :png)
    end

    test "decode image preserves zTXt metadata" do
      png_bytes = png_with_ztxt("Comment", "hello ztxt 世界")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(png_bytes, format: :png)

      assert metadata == %{
               png_chunks: [
                 %{
                   keyword: "Comment",
                   text: "hello ztxt 世界",
                   language_tag: "",
                   translated_keyword: ""
                 }
               ]
             }
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

    test "decode official conformance grayscale fixture" do
      jxl_bytes = File.read!("test/assets/jxl/conformance-grayscale.jxl")
      {:ok, %Image{} = image} = Imagex.decode(jxl_bytes, format: :jxl)

      assert image.tensor.shape == {200, 200}
      assert image.tensor.type == {:u, 8}
      assert image.metadata == nil
    end

    test "decode official conformance progressive fixture" do
      jxl_bytes = File.read!("test/assets/jxl/conformance-progressive.jxl")
      {:ok, %Image{} = image} = Imagex.decode(jxl_bytes, format: :jxl)

      assert image.tensor.shape == {2704, 4064, 3}
      assert image.tensor.type == {:u, 8}
      assert image.metadata == nil
    end

    test "decode official exif and xmp metadata fixture" do
      jxl_bytes = File.read!("test/assets/jxl/1x1_exif_xmp.jxl")
      {:ok, %Image{} = image} = Imagex.decode(jxl_bytes, format: :jxl)

      assert image.tensor.shape == {1, 1, 3}
      assert image.tensor.type == {:u, 8}

      assert image.metadata.exif.ifd0.image_description == "Created with GIMP"
      assert image.metadata.exif.ifd0.software == "GIMP 2.10.28"
      assert image.metadata.exif.ifd0.x_resolution == {300, 1}
      assert image.metadata.exif.ifd0.y_resolution == {300, 1}

      [%{type: :xml, contents: contents}] = image.metadata.jxl_boxes

      assert image.metadata.xmp == contents
      assert contents =~ "<dc:title>"
      assert contents =~ "<rdf:li xml:lang=\"x-default\">test</rdf:li>"
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

    test "encode image preserves exif metadata from Image struct", %{image: test_image} do
      {:ok, %Image{metadata: metadata}} = Imagex.decode(File.read!("test/assets/lena.jpg"), format: :jpeg)
      image = %Image{tensor: test_image.tensor, metadata: metadata}

      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jxl)

      assert encoded_metadata.exif == metadata.exif
    end

    test "encode image preserves jxl box metadata", %{image: test_image} do
      metadata = %{
        jxl_boxes: [%{type: :xml, contents: "<x:xmpmeta>Hello</x:xmpmeta>"}, %{type: :jumb, contents: <<1, 2, 3>>}]
      }

      image = %Image{tensor: test_image.tensor, metadata: metadata}

      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jxl)

      assert encoded_metadata.xmp == "<x:xmpmeta>Hello</x:xmpmeta>"
      assert encoded_metadata.jxl_boxes == metadata.jxl_boxes
    end

    test "encode image writes metadata.xmp as a JXL xml box", %{image: test_image} do
      xmp = sample_xmp("jxl-xmp")
      image = %Image{tensor: test_image.tensor, metadata: %{xmp: xmp}}

      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jxl)

      assert encoded_metadata.xmp == xmp
      assert encoded_metadata.jxl_boxes == [%{type: :xml, contents: xmp}]
    end

    test "encode image preserves metadata.xmp alongside non-xml JXL boxes", %{image: test_image} do
      xmp = sample_xmp("jxl-xmp-with-jumb")

      image = %Image{
        tensor: test_image.tensor,
        metadata: %{xmp: xmp, jxl_boxes: [%{type: :jumb, contents: <<1, 2, 3>>}]}
      }

      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jxl)

      assert encoded_metadata.xmp == xmp

      assert encoded_metadata.jxl_boxes == [
               %{type: :xml, contents: xmp},
               %{type: :jumb, contents: <<1, 2, 3>>}
             ]
    end

    test "encode image returns error for malformed jxl metadata", %{image: test_image} do
      image = %Image{tensor: test_image.tensor, metadata: %{jxl_boxes: :bad_metadata}}

      assert {:error, "JXL metadata must be a list, got: :bad_metadata"} = Imagex.encode(image, :jxl)

      image = %Image{tensor: test_image.tensor, metadata: %{jxl_boxes: [%{type: :xml, contents: 123}]}}

      assert {:error, "JXL metadata contents must be binaries, got: 123"} = Imagex.encode(image, :jxl)

      image = %Image{tensor: test_image.tensor, metadata: %{jxl_boxes: [%{type: :nope, contents: "bad"}]}}

      assert {:error, "unsupported JXL metadata box type: :nope"} = Imagex.encode(image, :jxl)

      image = %Image{tensor: test_image.tensor, metadata: %{xmp: 123}}

      assert {:error, "XMP metadata must be a binary, got: 123"} = Imagex.encode(image, :jxl)

      image = %Image{
        tensor: test_image.tensor,
        metadata: %{xmp: sample_xmp("duplicate-jxl"), jxl_boxes: [%{type: :xml, contents: sample_xmp("existing-jxl")}]}
      }

      assert {:error, "metadata.xmp cannot be combined with JXL xml boxes in metadata.jxl_boxes"} =
               Imagex.encode(image, :jxl)
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

    test "encode with progressive and order flags", %{image: test_image} do
      {:ok, compressed_0} = Imagex.encode(test_image, :jxl, progressive: 0, order: :scanline)
      {:ok, compressed_1} = Imagex.encode(test_image, :jxl, progressive: 1, order: :center)
      {:ok, compressed_2} = Imagex.encode(test_image, :jxl, progressive: 2, order: :center)

      assert byte_size(compressed_1) != byte_size(compressed_0)
      assert byte_size(compressed_2) != byte_size(compressed_1)

      # default should now be progressive: true (1) and order: :center (1)
      {:ok, compressed_default} = Imagex.encode(test_image, :jxl)
      assert byte_size(compressed_default) == byte_size(compressed_1)

      # verify they can still be decoded
      for bytes <- [compressed_1, compressed_2, compressed_default] do
        {:ok, %Image{} = decoded_image} = Imagex.decode(bytes, format: :jxl)
        assert decoded_image.tensor.shape == test_image.tensor.shape
      end
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
      assert String.starts_with?(reason, "Cannot transcode to JPEG")
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

    {:ok, %Image{} = image} = Imagex.decode(File.read!("test/assets/lena.jxl"))
    assert image.tensor.shape == {512, 512, 3}

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

  defp png_with_ztxt(keyword, text) do
    tensor = Nx.broadcast(Nx.tensor([0, 0, 0], type: {:u, 8}), {8, 8, 3})
    {:ok, png_bytes} = Imagex.encode(tensor, :png)

    [signature, ihdr_chunk | remaining_chunks] = split_png_chunks(png_bytes)
    ztxt_chunk = png_chunk("zTXt", <<keyword::binary, 0, 0, :zlib.compress(text)::binary>>)

    IO.iodata_to_binary([signature, ihdr_chunk, ztxt_chunk, remaining_chunks])
  end

  defp split_png_chunks(<<signature::binary-size(8), rest::binary>>) do
    [signature | split_png_chunks(rest, [])]
  end

  defp split_png_chunks(<<>>, acc), do: Enum.reverse(acc)

  defp split_png_chunks(<<length::32, type::binary-size(4), data::binary-size(length), crc::32, rest::binary>>, acc) do
    split_png_chunks(rest, [<<length::32, type::binary, data::binary, crc::32>> | acc])
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32, type::binary-size(4), data::binary, crc::32>>
  end

  defp sample_xmp(label) do
    """
    <x:xmpmeta xmlns:x=\"adobe:ns:meta/\">
      <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">
        <rdf:Description xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
          <dc:title>#{label}</dc:title>
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    """
    |> String.trim()
  end
end
