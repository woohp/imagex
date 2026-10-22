defmodule ExifTest do
  use ExUnit.Case

  alias Imagex.Image

  test "exif from lena.jpg" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    {:ok, %Image{metadata: %{exif: exif}}} = Imagex.decode(jpeg_bytes, format: :jpeg)

    assert exif == %{
             ifd0: %{
               exif: %{pixel_y_dimension: 512, pixel_x_dimension: 512, color_space: 1},
               orientation: 1,
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1}
             }
           }
  end

  test "exif from png file" do
    png_bytes = File.read!("test/assets/16bit.png")
    {:ok, %Image{metadata: %{exif: exif}}} = Imagex.decode(png_bytes, format: :png)

    assert exif == %{
             ifd0: %{
               exif: %{
                 pixel_y_dimension: 118,
                 pixel_x_dimension: 170,
                 user_comment: <<65, 83, 67, 73, 73, 0, 0, 0, 83, 99, 114, 101, 101, 110, 115, 104, 111, 116>>,
                 date_time_original: "2022:10:22 00:36:00"
               },
               orientation: 1
             }
           }
  end

  test "text data from png file" do
    png_bytes = File.read!("test/assets/png_with_text_data.png")
    {:ok, %Image{metadata: metadata}} = Imagex.decode(png_bytes, format: :png)

    assert metadata == %{
             png_chunks: [
               %{keyword: "MyNewString", text: "A string", language_tag: "", translated_keyword: ""},
               %{keyword: "MyNewInt", text: "1234", language_tag: "", translated_keyword: ""}
             ]
           }
  end

  test "exif from jpeg-xl file" do
    jxl_bytes = File.read!("test/assets/lena.jxl")
    metadata = read_metadata(jxl_bytes)

    assert metadata == %{
             exif: %{
               ifd0: %{
                 exif: %{pixel_y_dimension: 512, pixel_x_dimension: 512, color_space: 1},
                 orientation: 1,
                 resolution_unit: 2,
                 y_resolution: {72, 1},
                 x_resolution: {72, 1}
               }
             }
           }
  end

  test "encode_exif roundtrips parsed exif" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    %{exif: exif} = read_metadata(jpeg_bytes)

    assert {:ok, exif_binary} = Imagex.Exif.encode_exif(exif)
    assert Imagex.Exif.read_exif_from_tiff(exif_binary) == %{exif: exif}
  end

  test "encode_exif roundtrips parsed exif with thumbnail data" do
    jpeg_bytes = File.read!("test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg")
    %{exif: exif} = read_metadata(jpeg_bytes)

    assert {:ok, exif_binary} = Imagex.Exif.encode_exif(exif)

    assert Imagex.Exif.read_exif_from_tiff(exif_binary) == %{exif: exif}
  end

  describe "malformed EXIF" do
    test "is dropped instead of raising or looping" do
      for exif <- [
            "II*",
            <<"XX", 42, 0, 8::32-little, 0::16, 0::32>>,
            <<"II", 42, 0, 9999::32-little>>
          ] do
        assert Imagex.Exif.read_exif_from_tiff(exif) == %{}
      end

      # IFD0 whose next-IFD pointer and EXIF sub-IFD pointer both point back at itself
      cyclic =
        <<"II", 42, 0, 8::32-little, 1::16-little, 0x8769::16-little, 4::16-little, 1::32-little, 8::32-little,
          8::32-little>>

      assert %{exif: %{ifd0: %{}}} = Imagex.Exif.read_exif_from_tiff(cyclic)
    end

    test "only keeps what can be written back" do
      # a third IFD, x_resolution stored as SHORT, and exposure_time (an EXIF IFD tag) in IFD0
      exif =
        <<"II", 42, 0, 8::32-little, 2::16-little, 0x011A::16-little, 3::16-little, 1::32-little, 72::32-little,
          0x829A::16-little, 3::16-little, 1::32-little, 1::32-little, 38::32-little, 0::16-little, 44::32-little,
          0::16-little, 0::32-little>>

      assert %{exif: decoded} = Imagex.Exif.read_exif_from_tiff(exif)
      assert decoded == %{ifd0: %{}, ifd1: %{}}
      assert {:ok, _} = Imagex.Exif.encode_exif(decoded)
    end

    test "uncompressed thumbnails are read strip by strip" do
      # header (0), empty IFD0 (8), IFD1 (14) whose two entries point to the strip offsets (44) and
      # byte counts (52); the 3-byte strips sit at 60 and 66 with padding between them
      exif =
        <<"II", 42, 0, 8::32-little, 0::16-little, 14::32-little, 2::16-little, 0x0111::16-little, 4::16-little,
          2::32-little, 44::32-little, 0x0117::16-little, 4::16-little, 2::32-little, 52::32-little, 0::32-little,
          60::32-little, 66::32-little, 3::32-little, 3::32-little, 1, 2, 3, 0, 0, 0, 4, 5, 6>>

      assert %{exif: %{ifd1: %{thumbnail_data: <<1, 2, 3, 4, 5, 6>>}}} = Imagex.Exif.read_exif_from_tiff(exif)
    end

    test "many entries sharing one large value decode quickly" do
      count = 400
      data_offset = 8 + 2 + count * 12 + 4
      entry = <<0x8773::16-little, 7::16-little, 100_000::32-little, data_offset::32-little>>

      exif =
        <<"II", 42, 0, 8::32-little, count::16-little, :binary.copy(entry, count)::binary, 0::32,
          :binary.copy(<<7>>, 100_000)::binary>>

      {microseconds, %{exif: %{ifd0: ifd0}}} = :timer.tc(fn -> Imagex.Exif.read_exif_from_tiff(exif) end)
      assert byte_size(ifd0.inter_color_profile) == 100_000
      assert microseconds < 2_000_000
    end

    test "numeric arrays share one decode budget across IFDs" do
      # 1000 distinct tags, each a 65,536-element rational array over one shared block, plus EXIF, GPS and
      # interoperability pointers back to the same entry table
      ids = Enum.to_list(0x0100..0x04E7)

      pointers =
        for tag <- [0x8769, 0x8825, 0xA005],
            into: <<>>,
            do: <<tag::16-little, 4::16-little, 1::32-little, 8::32-little>>

      count = length(ids) + 3
      data_offset = 8 + 2 + count * 12 + 4
      arrays = for id <- ids, into: <<>>, do: <<id::16-little, 5::16-little, 65_536::32-little, data_offset::32-little>>

      exif =
        <<"II", 42, 0, 8::32-little, count::16-little, pointers::binary, arrays::binary, 0::32,
          :binary.copy(<<1::32-little, 1::32-little>>, 65_536)::binary>>

      {microseconds, %{exif: _}} = :timer.tc(fn -> Imagex.Exif.read_exif_from_tiff(exif) end)
      assert microseconds < 2_000_000
    end

    test "negative thumbnail offsets are ignored" do
      # IFD1 with a signed LONG jpeg_interchange_format of -1
      exif =
        <<"II", 42, 0, 8::32-little, 0::16-little, 14::32-little, 2::16-little, 0x0201::16-little, 9::16-little,
          1::32-little, -1::signed-32-little, 0x0202::16-little, 4::16-little, 1::32-little, 3::32-little, 0::32>>

      assert %{exif: %{ifd1: %{}}} = Imagex.Exif.read_exif_from_tiff(exif)
    end

    test "inline values ignore unused padding" do
      # make: ASCII with count 2 ("A\0"), followed by padding "BC" in the 4-byte value field
      exif =
        <<"II", 42, 0, 8::32-little, 1::16-little, 0x010F::16-little, 2::16-little, 2::32-little, "A", 0, "BC", 0::32>>

      assert %{exif: %{ifd0: %{make: "A"}}} = Imagex.Exif.read_exif_from_tiff(exif)
    end

    test "JPEG fill bytes before a marker do not hide metadata" do
      image = %Image{tensor: Nx.iota({4, 6, 3}, type: {:u, 8}), metadata: %{exif: %{ifd0: %{orientation: 6}}}}
      {:ok, jpeg} = Imagex.encode(image, :jpeg)
      [{app1, _}] = :binary.matches(jpeg, <<0xFF, 0xE1>>)
      padded = binary_part(jpeg, 0, app1) <> <<0xFF>> <> binary_part(jpeg, app1, byte_size(jpeg) - app1)

      assert {:ok, %Image{metadata: %{exif: %{ifd0: %{orientation: 6}}}}} = Imagex.decode(padded)
    end

    test "malformed JFXX segments are skipped" do
      {:ok, jpeg} = Imagex.encode(Nx.iota({4, 6, 3}, type: {:u, 8}), :jpeg)
      <<0xFF, 0xD8, rest::binary>> = jpeg
      bytes = <<0xFF, 0xD8, 0xFF, 0xE0, 8::16, "JFXX", 0, 0x11, rest::binary>>
      assert {:ok, %Image{}} = Imagex.decode(bytes)
    end
  end

  test "encode_exif keeps GPS ASCII ref tags as ASCII" do
    exif = %{
      ifd0: %{
        gps: %{
          version_id: [2, 3, 0, 0],
          latitude_ref: "N",
          latitude: [{43, 1}, {28, 1}, {281_400_000, 100_000_000}],
          longitude_ref: "E",
          longitude: [{11, 1}, {53, 1}, {645_599_999, 100_000_000}]
        }
      }
    }

    assert {:ok, exif_binary} = Imagex.Exif.encode_exif(exif)
    assert Imagex.Exif.read_exif_from_tiff(exif_binary) == %{exif: exif}
  end

  test "encode_exif requires ifd0" do
    assert {:error, "EXIF metadata must contain ifd0"} = Imagex.Exif.encode_exif(%{ifd1: %{orientation: 1}})
  end

  test "encode_exif honors the thumbnail compression tag" do
    exif = %{ifd0: %{}, ifd1: %{thumbnail_data: <<0, 1, 2>>, compression: 7}}

    assert {:error, "EXIF thumbnails must use compression 6 (JPEG) or 1 (uncompressed)"} =
             Imagex.Exif.encode_exif(exif)

    # explicit compression wins over sniffing, so raw pixels may start like a JPEG
    exif = %{ifd0: %{}, ifd1: %{thumbnail_data: <<0xFF, 0xD8, 0>>, compression: 1}}
    {:ok, binary} = Imagex.Exif.encode_exif(exif)
    assert Imagex.Exif.read_exif_from_tiff(binary) == %{exif: exif}
  end

  test "decoded EXIF from every sample JPEG survives re-encoding" do
    for path <- Path.wildcard("test/assets/exif/**/*.jp*g") do
      {:ok, image} = Imagex.open(path)
      assert {:ok, bytes} = Imagex.encode(image, :jpeg), path
      assert drop_compression(read_metadata(bytes)[:exif]) == drop_compression(image.metadata[:exif]), path
    end
  end

  test "exif with jpeg thumbnail in jpeg file" do
    jpeg_bytes = File.read!("test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg")
    %{exif: exif} = read_metadata(jpeg_bytes)

    assert %{
             ifd1: %{
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               ycbcr_positioning: 2,
               compression: 6,
               thumbnail_data: thumbnail_data
             }
           } = exif

    assert byte_size(thumbnail_data) == 7935

    # the jpeg can be decoded from the thumbnail data
    assert {:ok, %Image{}} = Imagex.decode(thumbnail_data, format: :jpeg)
  end

  test "exif with empty icc profile" do
    jpeg_bytes = File.read!("test/assets/exif/exif-empty-icc-profile.jpeg")
    %{exif: exif} = read_metadata(jpeg_bytes)

    assert exif == %{
             ifd0: %{
               exif: %{
                 pixel_y_dimension: 3600,
                 pixel_x_dimension: 2700,
                 exif_version: "0220",
                 interoperability: %{interoperability_version: "0100", interoperability_index: "R98"},
                 sub_sec_time: "567"
               },
               orientation: 1,
               ycbcr_positioning: 1,
               date_time: "2019:03:26 04:23:33",
               software: "ACD Systems Digital Imaging"
             }
           }
  end

  test "exif with jfif-app13" do
    jpeg_bytes = File.read!("test/assets/exif/exif-jfif-app13-app14ycck-3channel.jpg")
    %{exif: exif} = read_metadata(jpeg_bytes)

    assert %{
             ifd0: %{
               exif: %{pixel_y_dimension: 384, pixel_x_dimension: 310, color_space: 65535},
               resolution_unit: 2,
               y_resolution: {300, 1},
               x_resolution: {300, 1},
               date_time: "2009:02:13 14:23:19",
               software: "Adobe Photoshop CS Windows"
             },
             ifd1: %{
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               compression: 6,
               thumbnail_data: _thumbnail_data
             }
           } = exif
  end

  test "exif with bad-exif-kodak-dc210" do
    jpeg_bytes = File.read!("test/assets/exif/exif-rgb-thumbnail-bad-exif-kodak-dc210.jpg")
    %{exif: exif} = read_metadata(jpeg_bytes)

    assert %{
             ifd0: %{
               make: "Eastman Kodak Company",
               exif: %{
                 date_time_original: "2000:10:26 16:46:51",
                 flash: 1,
                 metering_mode: 2,
                 exposure_bias_value: {0, 10},
                 aperture_value: {40, 10},
                 shutter_speed_value: {50, 10},
                 compressed_bits_per_pixel: {0, 0},
                 components_configuration: <<1, 2, 3, 0>>,
                 exif_version: "0110",
                 maker_note: <<1, 4, 3, 0, 2, 1, 255, 255, 0, 1, _::binary>>,
                 focal_length: {44, 10},
                 light_source: 0,
                 subject_distance: {0, 0},
                 max_aperture_value: {400, 100},
                 brightness_value: {15, 10},
                 fnumber: {40, 10},
                 exposure_time: {1, 30}
               },
               orientation: 1,
               resolution_unit: 2,
               y_resolution: {216, 1},
               x_resolution: {216, 1},
               ycbcr_positioning: 1,
               model: "DC210 Zoom (V05.00)",
               image_description: "",
               copyright: ""
             },
             ifd1: %{
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               rows_per_strip: 72,
               samples_per_pixel: 3,
               photometric_interpretation: 2,
               compression: 1,
               bits_per_sample: ~c"\b\b\b",
               image_length: 72,
               image_width: 96,
               thumbnail_data: thumbnail_data
             }
           } = exif

    assert byte_size(thumbnail_data) == 96 * 72 * 3
  end

  test "long description" do
    %{exif: exif} = read_metadata(File.read!("test/assets/exif/long_description.jpg"))
    assert "Operation Mountain Viper put the soldiers" <> _ = exif.ifd0.image_description
    assert byte_size(exif.ifd0.image_description) > 255
  end

  describe "GPS exif" do
    test "DSCN0010.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/gps/DSCN0010.jpg")
      %{exif: exif} = read_metadata(jpeg_bytes)

      assert %{
               ifd0: %{
                 gps: %{
                   longitude_ref: "E",
                   longitude: [{11, 1}, {53, 1}, {645_599_999, 100_000_000}],
                   altitude_ref: 0,
                   time_stamp: [{14, 1}, {27, 1}, {724, 100}],
                   satellites: "06",
                   img_direction_ref: "",
                   map_datum: "WGS-84   ",
                   date_stamp: "2008:10:23",
                   latitude_ref: "N",
                   latitude: [{43, 1}, {28, 1}, {281_400_000, 100_000_000}]
                 }
               }
             } = exif
    end
  end

  describe "exif-org examples" do
    test "olympus-d320l.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/olympus-d320l.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)

      {<<0xFF, 0xD8, _::binary>>, metadata} = pop_in(metadata, [:jfif, :thumbnail_data])

      assert metadata == %{
               jfif: %{
                 thumbnail_height: 0,
                 thumbnail_width: 0,
                 density_units: 1,
                 density_x: 144,
                 density_y: 144,
                 version_major: 1,
                 version_minor: 2,
                 thumbnail_format: 16
               }
             }
    end

    test "ricoh-rdc5300.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/ricoh-rdc5300.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "RICOH      ",
                   exif: %{
                     pixel_y_dimension: 1200,
                     pixel_x_dimension: 1792,
                     color_space: 1,
                     user_comment: _user_comment,
                     date_time_original: "2000:05:31 21:50:40",
                     flash_pix_version: "0100",
                     flash: 1,
                     exposure_bias_value: {0, 10},
                     aperture_value: {40, 10},
                     shutter_speed_value: {65, 10},
                     compressed_bits_per_pixel: {300, 100},
                     components_configuration: <<1, 2, 3, 0>>,
                     date_time_digitized: "2000:05:31 21:50:40",
                     exif_version: "0210",
                     interoperability: %{
                       interoperability_version: "0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {133, 10},
                     light_source: 0,
                     max_aperture_value: {39, 10},
                     brightness_value: {-20, 10},
                     related_sound_file: "            "
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   model: "RDC-5300       ",
                   copyright: "(C) by RDC-5300 User     "
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data
                 }
               }
             } = metadata
    end

    test "nikon-e950.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/nikon-e950.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)

      assert %{
               exif: %{
                 ifd0: %{
                   make: "NIKON",
                   exif: %{
                     pixel_y_dimension: 1200,
                     pixel_x_dimension: 1600,
                     color_space: 1,
                     user_comment: _user_comment,
                     date_time_original: "2001:04:06 11:51:40",
                     flash_pix_version: "0100",
                     flash: 0,
                     metering_mode: 5,
                     exposure_bias_value: {0, 10},
                     compressed_bits_per_pixel: {4, 1},
                     components_configuration: <<1, 2, 3, 0>>,
                     date_time_digitized: "2001:04:06 11:51:40",
                     exif_version: "0210",
                     iso_speed_ratings: 80,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: "0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {128, 10},
                     light_source: 0,
                     max_aperture_value: {26, 10},
                     fnumber: {55, 10},
                     exposure_time: {10, 770},
                     file_source: <<3>>,
                     scene_type: <<1>>
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {300, 1},
                   x_resolution: {300, 1},
                   ycbcr_positioning: 2,
                   date_time: "2001:04:06 11:51:40",
                   model: "E950",
                   image_description: "          ",
                   software: "v981-79"
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {300, 1},
                   x_resolution: {300, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data
                 }
               },
               jfif: %{
                 thumbnail_data: "",
                 thumbnail_height: 0,
                 thumbnail_width: 0,
                 density_units: 1,
                 density_x: 72,
                 density_y: 72,
                 version_major: 1,
                 version_minor: 2
               }
             } = metadata
    end

    test "canon-ixus.jpg" do
      %{exif: exif} = read_metadata(File.read!("test/assets/exif/exif-org/canon-ixus.jpg"))
      assert %{related_image_width: 640, related_image_length: 480} = exif.ifd0.exif.interoperability
    end
  end

  defp read_metadata(bytes) do
    {:ok, %Image{metadata: metadata}} = Imagex.decode(bytes)
    metadata
  end

  # The encoder adds the compression tag that thumbnails require when the source omitted it.
  defp drop_compression(nil), do: nil
  defp drop_compression(exif), do: Map.update(exif, :ifd1, nil, &Map.delete(&1, :compression))
end
