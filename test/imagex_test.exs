defmodule ImagexTest do
  use ExUnit.Case

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

    test "decode returns an error for bad input" do
      {:error, error_reason} = Imagex.decode(<<0, 1, 2>>, format: :jpeg)
      assert String.starts_with?(error_reason, "Not a JPEG file")
    end

    test "decode returns an error for truncated data, but accepts a missing EOI marker" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")

      assert {:error, "Corrupt JPEG data: premature end of data segment"} =
               Imagex.decode(binary_part(jpeg_bytes, 0, byte_size(jpeg_bytes) - 1000))

      assert {:ok, _image} = Imagex.decode(binary_part(jpeg_bytes, 0, byte_size(jpeg_bytes) - 2))
    end

    test "decode returns an error for truncated arithmetic-coded data" do
      jpeg_bytes = File.read!("test/assets/arithmetic.jpg")
      assert {:ok, _image} = Imagex.decode(jpeg_bytes)

      assert {:error, "Premature end of JPEG file"} =
               Imagex.decode(binary_part(jpeg_bytes, 0, byte_size(jpeg_bytes) - 100))
    end

    test "decode drops a JFIF density that cannot be written back" do
      # lena.jpg with density units 0 and zero densities, as seen in files in the wild
      <<head::binary-size(13), _density::binary-size(5), rest::binary>> = File.read!("test/assets/lena.jpg")
      {:ok, image} = Imagex.decode(<<head::binary, 0, 0::16, 0::16, rest::binary>>)
      refute Map.has_key?(image.metadata.jfif, :density_units)
      assert {:ok, _bytes} = Imagex.encode(image, :jpeg)
    end

    test "rejects CMYK images rather than returning them as RGBA" do
      assert {:error, "CMYK JPEG images are not supported"} = Imagex.open("test/assets/cmyk.jpg")
    end

    test "killing an encode mid-call frees the output buffer once" do
      tensor = :crypto.strong_rand_bytes(1500 * 1500 * 3) |> Nx.from_binary(:u8) |> Nx.reshape({1500, 1500, 3})

      # Each encode takes about 15 ms, so some kills land after libjpeg has grown its output buffer. A double
      # free would abort the VM.
      for delay <- 1..10 do
        pid = spawn(fn -> Imagex.encode(tensor, :jpeg, quality: 95) end)
        Process.sleep(delay)
        Process.exit(pid, :kill)
      end

      :erlang.garbage_collect()
      assert {:ok, _bytes} = Imagex.encode(tensor, :jpeg)
    end

    test "encode grayscale image" do
      tensor = Nx.iota({8, 8}, type: {:u, 8})
      {:ok, bytes} = Imagex.encode(tensor, :jpeg)
      {:ok, %Image{} = image} = Imagex.decode(bytes)
      assert image.tensor.shape == {8, 8}
    end

    test "encode image preserves JFIF density" do
      {:ok, image} = Imagex.open("test/assets/exif/exif-org/olympus-d320l.jpg")
      {:ok, bytes} = Imagex.encode(image, :jpeg)
      {:ok, %Image{metadata: %{jfif: jfif}}} = Imagex.decode(bytes)
      assert {jfif.density_units, jfif.density_x, jfif.density_y} == {1, 144, 144}
    end

    test "encode image preserves xmp metadata", %{image: test_image} do
      xmp = "<x/>"
      image = %Image{tensor: test_image.tensor, metadata: %{xmp: xmp}}

      {:ok, compressed_bytes} = Imagex.encode(image, :jpeg)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jpeg)

      assert encoded_metadata.xmp == xmp
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

    test "decode rgb image without parsing exif data" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")
      {:ok, %Image{} = image} = Imagex.decode(jpeg_bytes, format: :jpeg, parse_metadata: false)
      assert image.tensor.type == {:u, 8}
      assert image.tensor.shape == {512, 512, 3}
      assert image.metadata == nil
    end
  end

  describe "png" do
    @palette <<255, 0, 0, 0, 255, 0>>
    @transparent_palette_pixels <<255, 0, 0, 0, 0, 255, 0, 128, 0, 255, 0, 128, 255, 0, 0, 0>>

    test "decodes palette PNG with transparency as RGBA" do
      # Distinct rows catch incorrectly overlapping decoded scanlines.
      png =
        build_png(<<2::32, 2::32, 8, 3, 0, 0, 0>>, [
          png_chunk("PLTE", @palette),
          png_chunk("tRNS", <<0, 128>>),
          png_chunk("IDAT", :zlib.compress(<<0, 0, 1, 0, 1, 0>>))
        ])

      assert {:ok, image} = Imagex.decode(png, format: :png)
      assert image.tensor.shape == {2, 2, 4}
      assert image.tensor.type == {:u, 8}
      assert Nx.to_binary(image.tensor) == @transparent_palette_pixels
    end

    test "decodes interlaced palette PNG with transparency as RGBA" do
      # For a 2x2 Adam7 image, only passes 1, 6, and 7 contain pixels.
      png =
        build_png(<<2::32, 2::32, 8, 3, 0, 0, 1>>, [
          png_chunk("PLTE", @palette),
          png_chunk("tRNS", <<0, 128>>),
          png_chunk("IDAT", :zlib.compress(<<0, 0, 0, 1, 0, 1, 0>>))
        ])

      assert {:ok, image} = Imagex.decode(png, format: :png)
      assert image.tensor.shape == {2, 2, 4}
      assert image.tensor.type == {:u, 8}
      assert Nx.to_binary(image.tensor) == @transparent_palette_pixels
    end

    test "decodes packed palette indices as eight-bit RGB" do
      # Two two-bit indices per row, padded to a byte; each row starts with its filter byte.
      png =
        build_png(<<2::32, 2::32, 2, 3, 0, 0, 0>>, [
          png_chunk("PLTE", @palette),
          png_chunk("IDAT", :zlib.compress(<<0, 0x10, 0, 0x40>>))
        ])

      assert {:ok, image} = Imagex.decode(png, format: :png)
      assert image.tensor.shape == {2, 2, 3}
      assert image.tensor.type == {:u, 8}
      assert Nx.to_binary(image.tensor) == <<255, 0, 0, 0, 255, 0, 0, 255, 0, 255, 0, 0>>
    end

    test "decodes one-bit grayscale as eight-bit grayscale" do
      png =
        build_png(<<2::32, 2::32, 1, 0, 0, 0, 0>>, [
          png_chunk("IDAT", :zlib.compress(<<0, 0x40, 0, 0x80>>))
        ])

      assert {:ok, image} = Imagex.decode(png, format: :png)
      assert image.tensor.shape == {2, 2}
      assert image.tensor.type == {:u, 8}
      assert Nx.to_binary(image.tensor) == <<0, 255, 255, 0>>
    end

    test "decode rgb image", %{image: test_image} do
      png_bytes = File.read!("test/assets/lena.png")
      {:ok, %Image{} = image} = Imagex.decode(png_bytes, format: :png)
      assert image.tensor.shape == {512, 512, 3}

      # should it be the same as our test PPM image
      assert Nx.to_binary(image.tensor) == Nx.to_binary(test_image.tensor)
      assert image.tensor.shape == test_image.tensor.shape

      assert %{xmp: xmp_text} = image.metadata
      assert map_size(image.metadata) == 1
      assert xmp_text =~ "<x:xmpmeta"
    end

    test "decode image returns :error for bad input" do
      {:error, error_reason} = Imagex.decode(<<0, 1, 2>>, format: :png)
      assert String.starts_with?(error_reason, "invalid png header")
    end

    test "decode expands tRNS transparency in RGB images" do
      {:ok, png_bytes} = Imagex.encode(Nx.tensor([[[255, 0, 0], [0, 0, 255]]], type: {:u, 8}), :png)
      [signature, ihdr | rest] = split_png_chunks(png_bytes)
      png_bytes = IO.iodata_to_binary([signature, ihdr, png_chunk("tRNS", <<0::16, 0::16, 255::16>>) | rest])

      {:ok, %Image{tensor: tensor}} = Imagex.decode(png_bytes)
      assert Nx.to_list(tensor) == [[[255, 0, 0, 255], [0, 0, 255, 0]]]
    end

    test "decode reads metadata after the image data and requires IEND" do
      {:ok, png_bytes} = Imagex.encode(Nx.iota({2, 2}, type: {:u, 8}), :png)
      [signature | chunks] = split_png_chunks(png_bytes)
      {chunks, [iend]} = Enum.split(chunks, -1)

      png_bytes = IO.iodata_to_binary([signature, chunks, png_chunk("tEXt", "Comment\0after IDAT"), iend])
      {:ok, %Image{metadata: metadata}} = Imagex.decode(png_bytes)
      assert [%{keyword: "Comment", text: "after IDAT"}] = metadata.png_chunks

      assert {:error, _} = Imagex.decode(IO.iodata_to_binary([signature, chunks]))
    end

    test "decode returns an error for truncated data" do
      png_bytes = File.read!("test/assets/lena.png")
      assert {:error, _} = Imagex.decode(binary_part(png_bytes, 0, 1000))
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

    test "encode image preserves decoded exif metadata" do
      {:ok, image} = Imagex.open("test/assets/16bit.png")
      {:ok, bytes} = Imagex.encode(image, :png)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(bytes)
      assert metadata.exif == image.metadata.exif
    end

    test "encode image writes metadata.xmp as a PNG XMP chunk", %{image: test_image} do
      xmp = "<x/>"
      image = %Image{tensor: test_image.tensor, metadata: %{xmp: xmp}}

      {:ok, compressed_bytes} = Imagex.encode(image, :png)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(compressed_bytes, format: :png)

      assert metadata == %{xmp: xmp}
      assert {:ok, _bytes} = Imagex.encode(%Image{tensor: test_image.tensor, metadata: metadata}, :png)
    end

    test "encode image rejects duplicate PNG XMP metadata", %{image: test_image} do
      image = %Image{
        tensor: test_image.tensor,
        metadata: %{
          xmp: "<x/>",
          png_chunks: [%{keyword: "XML:com.adobe.xmp", text: "<x/>"}]
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

    test "decode image converts Latin-1 zTXt metadata to UTF-8" do
      png_bytes = png_with_ztxt("Comment", "hello ztxt caf\xE9")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(png_bytes, format: :png)

      assert metadata == %{
               png_chunks: [%{keyword: "Comment", text: "hello ztxt café", language_tag: "", translated_keyword: ""}]
             }
    end

    test "encode round-trips 8- and 16-bit images with 1-4 channels" do
      for type <- [:u8, :u16], shape <- [{100, 100}, {100, 100, 2}, {100, 100, 3}, {100, 100, 4}] do
        image1 = Nx.iota(shape, type: type)
        {:ok, compressed_bytes} = Imagex.encode(image1, :png)
        {:ok, %Image{} = image2} = Imagex.decode(compressed_bytes, format: :png)
        assert image2.tensor == image1
        assert image2.metadata == nil
      end
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
      {:ok, %Image{} = image} = Imagex.open("test/assets/16bit.jxl")
      {:ok, png} = Imagex.open("test/assets/16bit.png")
      assert image.tensor == png.tensor
      assert image.metadata == nil
    end

    test "decode 10-bit image as full-range 16-bit" do
      {:ok, %Image{} = image} = Imagex.open("test/assets/jxl/10bit.jxl")
      assert image.tensor.type == {:u, 16}
      assert Nx.to_list(image.tensor[[.., 0, 0]]) == [0, 65535]
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

      contents = image.metadata.xmp
      refute Map.has_key?(image.metadata, :jxl_boxes)
      assert contents =~ "<dc:title>"
      assert contents =~ "<rdf:li xml:lang=\"x-default\">test</rdf:li>"
    end

    test "decode skips a malformed Exif box" do
      {:ok, jxl_bytes} = Imagex.encode(%Image{tensor: Nx.iota({2, 2}, type: :u8), metadata: %{xmp: "<x/>"}}, :jxl)
      # an Exif box whose TIFF header offset points past its end
      {:ok, image} = Imagex.decode(jxl_bytes <> <<12::32, "Exif", 99::32>>)
      assert image.metadata == %{xmp: "<x/>"}
    end

    test "encode rgb image lossless", %{image: test_image} do
      {:ok, compressed_bytes_lossless} = Imagex.encode(test_image, :jxl, lossless: true)
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
      assert encoded_metadata.jxl_boxes == [%{type: :jumb, contents: <<1, 2, 3>>}]
    end

    test "encode image writes metadata.xmp as a JXL xml box", %{image: test_image} do
      xmp = "<x/>"
      image = %Image{tensor: test_image.tensor, metadata: %{xmp: xmp}}

      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jxl)

      assert encoded_metadata == %{xmp: xmp}
      assert {:ok, _bytes} = Imagex.encode(%Image{tensor: test_image.tensor, metadata: encoded_metadata}, :jxl)
    end

    test "encode image preserves metadata.xmp alongside non-xml JXL boxes", %{image: test_image} do
      xmp = "<x/>"

      image = %Image{
        tensor: test_image.tensor,
        metadata: %{xmp: xmp, jxl_boxes: [%{type: :jumb, contents: <<1, 2, 3>>}]}
      }

      {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, %Image{metadata: encoded_metadata}} = Imagex.decode(compressed_bytes, format: :jxl)

      assert encoded_metadata.xmp == xmp

      assert encoded_metadata.jxl_boxes == [%{type: :jumb, contents: <<1, 2, 3>>}]
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
        metadata: %{xmp: "<x/>", jxl_boxes: [%{type: :xml, contents: "<x/>"}]}
      }

      assert {:error, "metadata.xmp cannot be combined with JXL xml boxes in metadata.jxl_boxes"} =
               Imagex.encode(image, :jxl)
    end

    test "encode with the highest distance is smaller than with the lowest", %{image: test_image} do
      {:ok, near_bytes} = Imagex.encode(test_image, :jxl, distance: 1)
      {:ok, far_bytes} = Imagex.encode(test_image, :jxl, distance: 15)
      assert byte_size(far_bytes) < byte_size(near_bytes)
    end

    test "lossy jpeg-xl encode rejects distance 0", %{image: test_image} do
      assert_raise ArgumentError, "JXL distance 0 requires lossless: true", fn ->
        Imagex.encode(test_image, :jxl, lossless: false, distance: 0)
      end
    end

    test "encode with the highest effort is smaller than with the lowest", %{image: test_image} do
      {:ok, low_effort_bytes} = Imagex.encode(test_image, :jxl, effort: 1)
      {:ok, high_effort_bytes} = Imagex.encode(test_image, :jxl, effort: 9)
      assert byte_size(high_effort_bytes) < byte_size(low_effort_bytes)
    end

    test "encode with progressive and order flags", %{image: test_image} do
      {:ok, compressed_0} = Imagex.encode(test_image, :jxl, progressive: 0, order: :scanline)
      {:ok, compressed_1} = Imagex.encode(test_image, :jxl, progressive: 1, order: :center)
      {:ok, compressed_2} = Imagex.encode(test_image, :jxl, progressive: 2, order: :center)

      # the defaults are progressive: 1 and order: :center
      assert Imagex.encode(test_image, :jxl) == {:ok, compressed_1}

      for bytes <- [compressed_0, compressed_1, compressed_2] do
        {:ok, %Image{} = decoded_image} = Imagex.decode(bytes, format: :jxl)
        assert decoded_image.tensor.shape == test_image.tensor.shape
      end
    end

    test "encode 16-bit grayscale-alpha, RGB and RGBA images losslessly" do
      for channels <- 2..4 do
        image = Nx.iota({8, 8, channels}, type: :u16)
        {:ok, compressed_bytes} = Imagex.encode(image, :jxl, lossless: true)

        {:ok, %Image{} = decoded_image} = Imagex.decode(compressed_bytes, format: :jxl)
        assert decoded_image.tensor == image
      end
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

    test "transcode reconstructs the original JPEG only when its metadata is stored" do
      jpeg_bytes = File.read!("test/assets/lena.jpg")

      {:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes)
      assert Imagex.Jxl.transcode_to_jpeg(jxl_bytes) == {:ok, jpeg_bytes}

      {:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes, store_jpeg_metadata: false)
      assert {:error, _} = Imagex.Jxl.transcode_to_jpeg(jxl_bytes)
      assert {:ok, %Image{}} = Imagex.decode(jxl_bytes)
    end

    test "transcode reconstructs a JPEG much larger than its JXL" do
      # zero-filled comments compress well, so the JPEG outgrows the initial output buffer
      <<0xFF, 0xD8, rest::binary>> = File.read!("test/assets/lena.jpg")
      comment = <<0xFF, 0xFE, 60_002::16, 0::size(60_000)-unit(8)>>
      jpeg_bytes = <<0xFF, 0xD8, :binary.copy(comment, 4)::binary, rest::binary>>

      {:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes)
      assert Imagex.Jxl.transcode_to_jpeg(jxl_bytes) == {:ok, jpeg_bytes}
    end

    test "decode transcoded jpeg image" do
      {:ok, jpeg_bytes} = Imagex.Jxl.transcode_to_jpeg(File.read!("test/assets/lena-transcode.jxl"))
      assert jpeg_bytes == File.read!("test/assets/lena.jpg")
    end

    test "decode transcoded jpeg image fails gracefully when not possible" do
      # for a file that did not come from a jpeg to begin with, it should fail gracefully
      jxl_bytes = File.read!("test/assets/lena.jxl")
      {:error, reason} = Imagex.Jxl.transcode_to_jpeg(jxl_bytes)
      assert String.starts_with?(reason, "Cannot transcode to JPEG")
    end
  end

  test "runs JXL operations concurrently" do
    {:ok, image} = Imagex.decode(File.read!("test/assets/lena.ppm"), format: :ppm)
    jxl_bytes = File.read!("test/assets/lena.jxl")
    transcoded_jxl_bytes = File.read!("test/assets/lena-transcode.jxl")

    for operation <- [
          fn -> Imagex.encode(image, :jxl, lossless: true) end,
          fn -> Imagex.decode(jxl_bytes, format: :jxl) end,
          fn -> Imagex.Jxl.transcode_to_jpeg(transcoded_jxl_bytes) end
        ] do
      results =
        1..8
        |> Task.async_stream(fn _ -> operation.() end, max_concurrency: 8, timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
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

  test "encode bmp round-trips RGB and RGBA rows that need padding" do
    for channels <- [3, 4] do
      tensor = Nx.iota({2, 3, channels}, type: {:u, 8})
      {:ok, bytes} = Imagex.encode(tensor, :bmp)
      {:ok, %Image{} = image} = Imagex.decode(bytes)
      assert image.tensor == tensor
    end
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

  test "load and render pdf document" do
    bytes = File.read!("test/assets/lena.pdf")
    assert {:error, "PDF documents must be loaded with Imagex.Pdf.load/1"} = Imagex.decode(bytes)

    {:ok, %Imagex.Pdf{} = pdf} = Imagex.Pdf.load(bytes)
    assert pdf.num_pages == 1
    assert {:error, "page index out of range"} = Imagex.Pdf.render_page(pdf, 1)
    assert {:error, "page index out of range"} = Imagex.Pdf.render_page(pdf, 2 ** 40)

    {:ok, %Image{} = image} = Imagex.Pdf.render_page(pdf, 0)
    assert image.tensor.shape == {512, 512, 4}

    # double the default dpi of 72
    {:ok, %Image{} = image} = Imagex.Pdf.render_page(pdf, 0, dpi: 144)
    assert image.tensor.shape == {1024, 1024, 4}
  end

  test "rendering a page missing from the page tree returns an error" do
    # /Count claims one page, but the page object is null
    {:ok, pdf} = Imagex.Pdf.load(File.read!("test/assets/broken-page-tree.pdf"))
    assert {:error, "failed to load PDF page"} = Imagex.Pdf.render_page(pdf, 0)
  end

  test "decode tiff as its first page" do
    bytes = File.read!("test/assets/lena.tiff")
    {:ok, %Image{} = image} = Imagex.decode(bytes)
    assert image.tensor.shape == {512, 512, 4}

    assert {:error, "page index out of range"} = Imagex.decode(bytes, page: 1)
  end

  test "renders pages of one TIFF document concurrently" do
    {:ok, tiff} = Imagex.Tiff.load(File.read!("test/assets/lena.tiff"))
    {:ok, expected} = Imagex.Tiff.render_page(tiff, 0)

    results =
      1..32
      |> Task.async_stream(fn _ -> Imagex.Tiff.render_page(tiff, 0) end, max_concurrency: 16)
      |> Enum.map(fn {:ok, {:ok, image}} -> image.tensor end)

    assert Enum.all?(results, &(&1 == expected.tensor))
  end

  test "load and render tiff document" do
    {:ok, %Imagex.Tiff{} = tiff} = Imagex.Tiff.load(File.read!("test/assets/lena.tiff"))
    assert tiff.num_pages == 1

    {:ok, %Image{} = image} = Imagex.Tiff.render_page(tiff, 0)
    assert image.tensor.shape == {512, 512, 4}
    assert {:error, "page index out of range"} = Imagex.Tiff.render_page(tiff, -1)
    assert {:error, "page index out of range"} = Imagex.Tiff.render_page(tiff, 2 ** 40)
  end

  describe "orientation" do
    # Expected pixels come from ImageMagick's -auto-orient on the same files.
    @oriented %{
      1 => {{2, 3}, [0, 40, 80, 120, 160, 200]},
      2 => {{2, 3}, [80, 40, 0, 200, 160, 120]},
      3 => {{2, 3}, [200, 160, 120, 80, 40, 0]},
      4 => {{2, 3}, [120, 160, 200, 0, 40, 80]},
      5 => {{3, 2}, [0, 120, 40, 160, 80, 200]},
      6 => {{3, 2}, [120, 0, 160, 40, 200, 80]},
      7 => {{3, 2}, [200, 80, 160, 40, 120, 0]},
      8 => {{3, 2}, [80, 200, 40, 160, 0, 120]}
    }

    setup do
      {:ok, tensor: Nx.iota({2, 3}, type: {:u, 8}) |> Nx.multiply(40)}
    end

    test "orient: true applies the EXIF orientation and resets it", %{tensor: tensor} do
      for {orientation, {shape, pixels}} <- @oriented do
        {:ok, bytes} =
          Imagex.encode(%Image{tensor: tensor, metadata: %{exif: %{ifd0: %{orientation: orientation}}}}, :png)

        {:ok, image} = Imagex.decode(bytes, orient: true)
        assert {image.tensor.shape, Nx.to_flat_list(image.tensor)} == {shape, pixels}
        assert image.metadata.exif.ifd0.orientation == 1
      end
    end

    test "pixels are left as stored by default", %{tensor: tensor} do
      {:ok, bytes} = Imagex.encode(%Image{tensor: tensor, metadata: %{exif: %{ifd0: %{orientation: 6}}}}, :png)
      {:ok, image} = Imagex.decode(bytes)
      assert image.tensor == tensor
      assert image.metadata.exif.ifd0.orientation == 6

      {:ok, image} = Imagex.decode(bytes, orient: true, parse_metadata: false)
      assert image.tensor.shape == {3, 2}
      assert image.metadata == nil
    end

    test "TIFF pages decode upright, including transposed orientations" do
      for orientation <- 2..8 do
        {:ok, image} = Imagex.open("test/assets/tiff/orientation-#{orientation}.tif")
        gray = image.tensor[[.., .., 0]]
        assert {gray.shape, Nx.to_flat_list(gray)} == @oriented[orientation]
      end
    end

    test "JXL carries the orientation in the codestream and decodes upright", %{tensor: tensor} do
      image = %Image{tensor: tensor, metadata: %{exif: %{ifd0: %{orientation: 6}}}}
      {:ok, bytes} = Imagex.encode(image, :jxl, lossless: true)
      {:ok, decoded} = Imagex.decode(bytes)
      assert {decoded.tensor.shape, Nx.to_flat_list(decoded.tensor)} == @oriented[6]
      assert decoded.metadata.exif.ifd0.orientation == 1
    end
  end

  describe "api" do
    @describetag :tmp_dir

    test "save accepts a tensor and infers the format from the extension", %{image: image, tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "image.PNG")
      assert :ok = Imagex.save(image.tensor, path)
      assert {:ok, %Image{tensor: tensor}} = Imagex.open(path)
      assert tensor == image.tensor
    end

    test "save takes an explicit format", %{image: image, tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "image")
      assert :ok = Imagex.save(image, path, format: :jxl, lossless: true)
      assert {:ok, %Image{}} = Imagex.decode(File.read!(path), format: :jxl)
    end

    test "save raises for an unknown extension", %{image: image, tmp_dir: tmp_dir} do
      assert_raise ArgumentError, ~r/extension ".gif"/, fn -> Imagex.save(image, Path.join(tmp_dir, "a.gif")) end
    end

    test "open returns a string error for a missing file" do
      assert {:error, "missing.png: no such file or directory"} = Imagex.open("missing.png")
    end

    test "metadata option overrides the image's metadata, and nil strips it", %{image: image} do
      image = %{image | metadata: %{xmp: "<from-struct/>"}}

      for {options, expected} <- [
            {[], %{xmp: "<from-struct/>"}},
            {[metadata: %{xmp: "<from-option/>"}], %{xmp: "<from-option/>"}},
            {[metadata: nil], nil}
          ] do
        {:ok, bytes} = Imagex.encode(image, :png, options)
        assert {:ok, %Image{metadata: ^expected}} = Imagex.decode(bytes)
      end
    end

    test "formats without metadata accept and ignore it", %{image: image} do
      image = %{image | metadata: %{xmp: "<x/>"}}
      assert {:ok, _} = Imagex.encode(image, :ppm)
      assert {:ok, _} = Imagex.encode(image, :bmp, metadata: nil)
    end

    test "invalid arguments raise", %{image: image} do
      assert_raise ArgumentError, fn -> Imagex.encode(image, :gif) end
      assert_raise ArgumentError, fn -> Imagex.encode(image, :tiff) end
      assert_raise ArgumentError, fn -> Imagex.encode(image, :jpeg, bogus: 1) end
      assert_raise ArgumentError, fn -> Imagex.encode(image, :jpeg, quality: 500) end
      assert_raise ArgumentError, fn -> Imagex.encode(image, :jxl, effort: :tortoise) end
      assert_raise ArgumentError, fn -> Imagex.decode(<<>>, format: :gif) end
      assert_raise ArgumentError, fn -> Imagex.decode(<<>>, bogus: 1) end
      assert_raise ArgumentError, fn -> Imagex.decode(<<>>, orient: :yes) end
      assert_raise ArgumentError, fn -> Imagex.decode(<<>>, page: -1) end

      {:ok, pdf} = Imagex.Pdf.load(File.read!("test/assets/lena.pdf"))
      assert_raise ArgumentError, fn -> Imagex.Pdf.render_page(pdf, 0, dpi: 0) end
    end

    test "metadata too large for a JPEG segment is dropped", %{image: image} do
      large = :binary.copy("x", 70_000)
      image = %{image | metadata: %{exif: %{ifd0: %{exif: %{maker_note: large}}}, xmp: large}}

      {:ok, bytes} = Imagex.encode(image, :jpeg)
      {:ok, %Image{metadata: metadata}} = Imagex.decode(bytes)
      refute Map.has_key?(metadata, :exif) or Map.has_key?(metadata, :xmp)
    end

    test "images larger than max_pixels return an error before decoding", %{image: image} do
      # an 8x8 JPEG whose header claims 65500x21858 pixels (about 4 GB of RGB)
      {:ok, jpeg} = Imagex.encode(Nx.broadcast(Nx.tensor(128, type: {:u, 8}), {8, 8, 3}), :jpeg)
      [{sof, _}] = :binary.matches(jpeg, <<0xFF, 0xC0>>)
      <<before::binary-size(^sof + 5), _height::16, _width::16, rest::binary>> = jpeg

      assert {:error, "image has more pixels than max_pixels allows"} =
               Imagex.decode(<<before::binary, 21858::16, 65500::16, rest::binary>>)

      for format <- [:png, :jxl, :webp, :ppm, :bmp] do
        {:ok, bytes} = Imagex.encode(image, format)
        assert {:error, "image has more pixels than max_pixels allows"} = Imagex.decode(bytes, max_pixels: 1000)
        assert {:ok, _} = Imagex.decode(bytes, max_pixels: :infinity)
      end

      {:ok, tiff} = Imagex.Tiff.load(File.read!("test/assets/lena.tiff"))
      assert {:error, _} = Imagex.Tiff.render_page(tiff, 0, max_pixels: 1000)
      assert {:error, _} = Imagex.open("test/assets/lena.tiff", max_pixels: 1000)
      assert {:ok, _} = Imagex.open("test/assets/lena.tiff", max_pixels: :infinity)

      # a 0.9 x 1000 point page must not round down to zero pixels
      thin_page =
        "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n" <>
          "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 0.9 1000]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"

      {:ok, thin} = Imagex.Pdf.load(thin_page)
      assert {:error, _} = Imagex.Pdf.render_page(thin, 0, max_pixels: 1)
      assert {:ok, _} = Imagex.Pdf.render_page(thin, 0)

      {:ok, pdf} = Imagex.Pdf.load(File.read!("test/assets/lena.pdf"))
      assert {:error, _} = Imagex.Pdf.render_page(pdf, 0, dpi: 100_000)

      assert_raise ArgumentError, fn -> Imagex.decode(<<>>, max_pixels: 0) end
    end

    test "invalid JFIF density metadata returns an error", %{image: image} do
      image = %{image | metadata: %{jfif: %{density_units: 1, density_x: 0, density_y: 72}}}
      assert {:error, "invalid JFIF density" <> _} = Imagex.encode(image, :jpeg)
    end

    test "pixels a codec cannot store return an error", %{image: image} do
      assert {:error, "JPEG cannot encode 3-channel u16 pixels"} =
               Imagex.encode(Nx.as_type(image.tensor, {:u, 16}), :jpeg)

      assert {:error, "PNG cannot encode 3-channel f32 pixels"} =
               Imagex.encode(Nx.as_type(image.tensor, {:f, 32}), :png)
    end

    test "convert returns the kind of value it was given" do
      tensor = Nx.iota({2, 2, 3}, type: :u8)
      assert %Nx.Tensor{shape: {2, 2}} = Imagex.convert(tensor, :L)
      assert %Image{tensor: %Nx.Tensor{shape: {2, 2, 4}}} = Imagex.convert(%Image{tensor: tensor}, :RGBA)
    end
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

  defp build_png(ihdr, chunks) do
    IO.iodata_to_binary([<<137, 80, 78, 71, 13, 10, 26, 10>>, png_chunk("IHDR", ihdr), chunks, png_chunk("IEND", <<>>)])
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32([type, data])
    <<byte_size(data)::32, type::binary-size(4), data::binary, crc::32>>
  end
end
