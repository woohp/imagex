defmodule ExifTest do
  use ExUnit.Case
  doctest Imagex.Exif

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
                 user_comment: [65, 83, 67, 73, 73, 0, 0, 0, 83, 99, 114, 101, 101, 110, 115, 104, 111, 116],
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
             png: %{"MyNewInt" => "1234", "MyNewString" => "A string"}
           }
  end

  test "exif from jpeg-xl file" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    {:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(jpeg_bytes)
    metadata = Imagex.Exif.read_exif_from_jxl(jxl_bytes)

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

  test "exif with rgb thumbnail in jpeg file" do
    jpeg_bytes = File.read!("test/assets/exif/exif-rgb-thumbnail-sony-d700.jpg")
    %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

    assert %{
             ifd0: %{
               make: "SONY",
               exif: %{
                 pixel_y_dimension: 1024,
                 pixel_x_dimension: 1344,
                 color_space: 1,
                 date_time_original: "1998:12:01 14:22:36",
                 flash_pix_version: ~c"0100",
                 flash: 0,
                 metering_mode: 2,
                 exposure_bias_value: {0, 100},
                 aperture_value: {250, 100},
                 shutter_speed_value: {500, 100},
                 compressed_bits_per_pixel: {6, 1},
                 components_configuration: [1, 2, 3, 0],
                 date_time_digitized: "1998:12:01 14:22:36",
                 exif_version: ~c"0200",
                 iso_speed_ratings: 200,
                 exposure_program: 3
               },
               orientation: 1,
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               ycbcr_positioning: 1,
               date_time: "1998:12:01 14:22:36",
               model: "DSC-D700",
               image_description: ""
             },
             ifd1: %{
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               strip_byte_counts: 14400,
               rows_per_strip: 60,
               samples_per_pixel: 3,
               strip_offsets: 648,
               photometric_interpretation: 2,
               compression: 1,
               bits_per_sample: ~c"\b\b\b",
               image_length: 60,
               image_width: 80,
               thumbnail_data: thumbnail_data
             }
           } = exif

    assert byte_size(thumbnail_data) == 14400
  end

  test "exif with jpeg thumbnail in jpeg file" do
    jpeg_bytes = File.read!("test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg")
    %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

    assert %{
             ifd1: %{
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               ycbcr_positioning: 2,
               compression: 6,
               thumbnail_data: thumbnail_data,
               jpeg_interchange_format_length: 7935,
               jpeg_interchange_format: 862
             }
           } = exif

    assert byte_size(thumbnail_data) == 7935

    # the jpeg can be decoded from the thumbnail data
    assert {:ok, %Image{}} = Imagex.decode(thumbnail_data, format: :jpeg)
  end

  test "exif with empty icc profile" do
    jpeg_bytes = File.read!("test/assets/exif/exif-empty-icc-profile.jpeg")
    %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

    assert exif == %{
             ifd0: %{
               exif: %{
                 pixel_y_dimension: 3600,
                 pixel_x_dimension: 2700,
                 exif_version: ~c"0220",
                 interoperability: %{interoperability_version: ~c"0100", interoperability_index: "R98"},
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
    %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

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
               thumbnail_data: _thumbnail_data,
               jpeg_interchange_format_length: 2644,
               jpeg_interchange_format: 286
             }
           } = exif
  end

  test "exif with bad-exif-kodak-dc210" do
    jpeg_bytes = File.read!("test/assets/exif/exif-rgb-thumbnail-bad-exif-kodak-dc210.jpg")
    %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

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
                 components_configuration: [1, 2, 3, 0],
                 exif_version: ~c"0110",
                 maker_note: [1, 4, 3, 0, 2, 1, 255, 255, 0, 1 | _rest],
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
               image_description: <<0, 0, 0, 134>>,
               copyright: <<0, 0, 0, 246>>
             },
             ifd1: %{
               resolution_unit: 2,
               y_resolution: {72, 1},
               x_resolution: {72, 1},
               strip_byte_counts: 20736,
               rows_per_strip: 72,
               samples_per_pixel: 3,
               strip_offsets: 928,
               photometric_interpretation: 2,
               compression: 1,
               bits_per_sample: ~c"\b\b\b",
               image_length: 72,
               image_width: 96,
               thumbnail_data: _thumbnail_data
             }
           } = exif
  end

  test "long description" do
    jpeg_bytes = File.read!("test/assets/exif/exif-rgb-thumbnail-bad-exif-kodak-dc210.jpg")
    %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)
    assert %{ifd0: %{}, ifd1: %{}} = exif
  end

  describe "GPS exif" do
    test "DSCN0010.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/gps/DSCN0010.jpg")
      %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

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

    test "DSCN0012.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/gps/DSCN0012.jpg")
      %{exif: exif} = Imagex.Exif.read_exif_from_jpeg(jpeg_bytes)

      assert %{
               ifd0: %{
                 gps: %{
                   longitude_ref: "E",
                   longitude: [{11, 1}, {53, 1}, {742_199_999, 100_000_000}],
                   altitude_ref: 0,
                   time_stamp: [{14, 1}, {28, 1}, {17240, 1000}],
                   satellites: "06",
                   img_direction_ref: "",
                   map_datum: "WGS-84   ",
                   date_stamp: "2008:10:23",
                   latitude_ref: "N",
                   latitude: [{43, 1}, {28, 1}, {176_399_999, 100_000_000}]
                 }
               }
             } = exif
    end
  end

  describe "exif-org examples" do
    test "olympus-d320l.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/olympus-d320l.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)

      assert metadata == %{
               jfif: %{
                 thumbnail_data: :not_working_yet,
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

    test "sony-cybershot.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/sony-cybershot.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "SONY",
                   exif: %{
                     pixel_y_dimension: 480,
                     pixel_x_dimension: 640,
                     color_space: 1,
                     date_time_original: "2000:09:30 10:59:45",
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 2,
                     exposure_bias_value: {0, 10},
                     compressed_bits_per_pixel: {2, 1},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2000:09:30 10:59:45",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 100,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     focal_length: {216, 10},
                     light_source: 0,
                     max_aperture_value: {3, 1},
                     fnumber: {40, 10},
                     exposure_time: {1, 197},
                     file_source: 3,
                     scene_type: 1
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "2000:09:30 10:59:45",
                   model: "CYBERSHOT",
                   image_description: "                               "
                 },
                 ifd1: %{
                   make: "SONY",
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   date_time: "2000:09:30 10:59:45",
                   model: "CYBERSHOT",
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 2959,
                   jpeg_interchange_format: 797
                 }
               }
             } = metadata
    end

    test "fujifilm-finepix40i.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/fujifilm-finepix40i.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "FUJIFILM",
                   exif: %{
                     pixel_y_dimension: 1800,
                     pixel_x_dimension: 2400,
                     color_space: 1,
                     date_time_original: "2000:08:04 18:22:57",
                     flash_pix_version: ~c"0100",
                     flash: 1,
                     metering_mode: 5,
                     exposure_bias_value: {0, 100},
                     aperture_value: {300, 100},
                     shutter_speed_value: {550, 100},
                     compressed_bits_per_pixel: {15, 10},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2000:08:04 18:22:57",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 200,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {870, 100},
                     max_aperture_value: {300, 100},
                     brightness_value: {26, 100},
                     fnumber: {280, 100},
                     file_source: 3,
                     scene_type: 1,
                     sensing_method: 2,
                     focal_plane_resolution_unit: 3,
                     focal_plane_y_resolution: {2381, 1},
                     focal_plane_x_resolution: {2381, 1}
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "2000:08:04 18:22:57",
                   model: "FinePix40i",
                   software: "Digital Camera FinePix40i Ver1.39",
                   copyright: "          "
                 },
                 ifd1: %{
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 8691,
                   jpeg_interchange_format: 1074
                 }
               }
             } = metadata
    end

    test "sony-d700.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/sony-d700.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "SONY",
                   exif: %{
                     pixel_y_dimension: 1024,
                     pixel_x_dimension: 1344,
                     color_space: 1,
                     date_time_original: "1998:12:01 14:22:36",
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 2,
                     exposure_bias_value: {0, 100},
                     aperture_value: {250, 100},
                     shutter_speed_value: {500, 100},
                     compressed_bits_per_pixel: {6, 1},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "1998:12:01 14:22:36",
                     exif_version: ~c"0200",
                     iso_speed_ratings: 200,
                     exposure_program: 3
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 1,
                   date_time: "1998:12:01 14:22:36",
                   model: "DSC-D700",
                   image_description: ""
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   strip_byte_counts: 14400,
                   rows_per_strip: 60,
                   samples_per_pixel: 3,
                   strip_offsets: 648,
                   photometric_interpretation: 2,
                   compression: 1,
                   bits_per_sample: ~c"\b\b\b",
                   image_length: 60,
                   image_width: 80,
                   thumbnail_data: _thumbnail_data
                 }
               }
             } = metadata
    end

    test "kodak-dc240.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/kodak-dc240.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "EASTMAN KODAK COMPANY",
                   exif: %{
                     pixel_y_dimension: 960,
                     pixel_x_dimension: 1280,
                     color_space: 1,
                     date_time_original: "1999:05:25 21:00:09",
                     flash_pix_version: ~c"0100",
                     flash: 1,
                     metering_mode: 1,
                     exposure_bias_value: {0, 100},
                     aperture_value: {40, 10},
                     shutter_speed_value: {50, 10},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "1999:05:25 21:00:09",
                     exif_version: ~c"0210",
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {140, 10},
                     light_source: 0,
                     max_aperture_value: {38, 10},
                     fnumber: {4, 1},
                     exposure_time: {1, 30},
                     file_source: 3,
                     scene_type: 1,
                     sensing_method: 2,
                     exposure_index: {140, 1}
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {192, 1},
                   x_resolution: {192, 1},
                   ycbcr_positioning: 1,
                   model: "KODAK DC240 ZOOM DIGITAL CAMERA",
                   copyright: "KODAK DC240 ZOOM DIGITAL CAMERA "
                 },
                 ifd1: %{
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 6934,
                   jpeg_interchange_format: 1480
                 }
               }
             } = metadata
    end

    test "olympus-c960.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/olympus-c960.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "OLYMPUS OPTICAL CO.,LTD",
                   exif: %{
                     pixel_y_dimension: 960,
                     pixel_x_dimension: 1280,
                     color_space: 1,
                     user_comment: _user_comment,
                     date_time_original: "2000:11:07 10:41:43",
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 5,
                     exposure_bias_value: {0, 10},
                     compressed_bits_per_pixel: {1, 1},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2000:11:07 10:41:43",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 125,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {56, 10},
                     light_source: 0,
                     max_aperture_value: {3, 1},
                     fnumber: {80, 10},
                     exposure_time: {1, 345},
                     file_source: 3,
                     scene_type: 1
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "2000:11:08 20:14:38",
                   model: "C960Z,D460Z",
                   image_description: "OLYMPUS DIGITAL CAMERA         ",
                   software: "OLYMPUS CAMEDIA Master"
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 5145,
                   jpeg_interchange_format: 2012
                 }
               }
             } = metadata
    end

    test "sanyo-vpcg250.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/sanyo-vpcg250.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "SANYO Electric Co.,Ltd.",
                   exif: %{
                     pixel_y_dimension: 480,
                     pixel_x_dimension: 640,
                     color_space: 65535,
                     date_time_original: "1998:01:01 00:00:00",
                     flash_pix_version: ~c"0100",
                     flash: 1,
                     metering_mode: 2,
                     exposure_bias_value: {0, 10},
                     compressed_bits_per_pixel: {17, 10},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "1998:01:01 00:00:00",
                     exif_version: ~c"0200",
                     maker_note: _maker_note,
                     focal_length: {60, 10},
                     light_source: 0,
                     max_aperture_value: {3, 1},
                     fnumber: {80, 10},
                     exposure_time: {1, 171},
                     related_sound_file: "            ",
                     file_source: 3
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "1998:01:01 00:00:00",
                   model: "SR6 ",
                   image_description: "SANYO DIGITAL CAMERA",
                   software: "V06P-74"
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 3602,
                   jpeg_interchange_format: 877
                 }
               }
             } = metadata
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
                     flash_pix_version: ~c"0100",
                     flash: 1,
                     exposure_bias_value: {0, 10},
                     aperture_value: {40, 10},
                     shutter_speed_value: {65, 10},
                     compressed_bits_per_pixel: {300, 100},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2000:05:31 21:50:40",
                     exif_version: ~c"0210",
                     interoperability: %{
                       interoperability_version: ~c"0100",
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
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 5046,
                   jpeg_interchange_format: 1061
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
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 5,
                     exposure_bias_value: {0, 10},
                     compressed_bits_per_pixel: {4, 1},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2001:04:06 11:51:40",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 80,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {128, 10},
                     light_source: 0,
                     max_aperture_value: {26, 10},
                     fnumber: {55, 10},
                     exposure_time: {10, 770},
                     file_source: 3,
                     scene_type: 1
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
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 4662,
                   jpeg_interchange_format: 2036
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

    test "fujifilm-mx1700.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/fujifilm-mx1700.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "FUJIFILM",
                   exif: %{
                     pixel_y_dimension: 480,
                     pixel_x_dimension: 640,
                     color_space: 1,
                     date_time_original: "2000:09:02 14:30:10",
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 5,
                     exposure_bias_value: {0, 10},
                     aperture_value: {56, 10},
                     shutter_speed_value: {74, 10},
                     compressed_bits_per_pixel: {2, 1},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2000:09:02 14:30:10",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 125,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     focal_length: {99, 10},
                     max_aperture_value: {33, 10},
                     brightness_value: {76, 10},
                     fnumber: {70, 10},
                     file_source: 3,
                     sensing_method: 2,
                     focal_plane_resolution_unit: 3,
                     focal_plane_y_resolution: {1087, 1},
                     focal_plane_x_resolution: {1087, 1},
                     scene_type: 1
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "2000:09:02 14:30:10",
                   model: "MX-1700ZOOM",
                   software: "Digital Camera MX-1700ZOOM Ver1.00",
                   copyright: "          "
                 },
                 ifd1: %{
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 4354,
                   jpeg_interchange_format: 856
                 }
               }
             } = metadata
    end

    test "fujifilm-dx10.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/fujifilm-dx10.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "FUJIFILM",
                   exif: %{
                     pixel_y_dimension: 768,
                     pixel_x_dimension: 1024,
                     color_space: 1,
                     date_time_original: "2001:04:12 20:33:14",
                     flash_pix_version: ~c"0100",
                     flash: 1,
                     metering_mode: 5,
                     exposure_bias_value: {0, 10},
                     aperture_value: {41, 10},
                     shutter_speed_value: {66, 10},
                     compressed_bits_per_pixel: {14, 10},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2001:04:12 20:33:14",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 150,
                     exposure_program: 2,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     focal_length: {58, 10},
                     max_aperture_value: {41, 10},
                     brightness_value: {-27, 10},
                     fnumber: {42, 10},
                     file_source: 3,
                     sensing_method: 2,
                     focal_plane_resolution_unit: 3,
                     focal_plane_y_resolution: {2151, 1},
                     focal_plane_x_resolution: {2151, 1},
                     scene_type: 1
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "2001:04:12 20:33:14",
                   model: "DX-10",
                   software: "Digital Camera DX-10 Ver1.00",
                   copyright: "J P Bowen "
                 },
                 ifd1: %{
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 10274,
                   jpeg_interchange_format: 856
                 }
               }
             } = metadata
    end

    test "kodak-dc210.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/kodak-dc210.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
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
                     components_configuration: [1, 2, 3, 0],
                     exif_version: ~c"0110",
                     maker_note: _maker_note,
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
                   image_description: <<0, 0, 0, 134>>,
                   copyright: <<0, 0, 0, 246>>
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   strip_byte_counts: 20736,
                   rows_per_strip: 72,
                   samples_per_pixel: 3,
                   strip_offsets: 928,
                   photometric_interpretation: 2,
                   compression: 1,
                   bits_per_sample: ~c"\b\b\b",
                   image_length: 72,
                   image_width: 96,
                   thumbnail_data: _thumbnail_data
                 }
               }
             } = metadata
    end

    test "canon-ixus.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/canon-ixus.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)
      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "Canon",
                   exif: %{
                     pixel_y_dimension: 480,
                     pixel_x_dimension: 640,
                     color_space: 1,
                     user_comment: _user_comment,
                     date_time_original: "2001:06:09 15:17:32",
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 2,
                     exposure_bias_value: {0, 3},
                     aperture_value: {262_144, 65536},
                     shutter_speed_value: {553_859, 65536},
                     compressed_bits_per_pixel: {3, 1},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2001:06:09 15:17:32",
                     exif_version: ~c"0210",
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98",
                       related_image_length: 480,
                       related_image_width: 640
                     },
                     maker_note: _maker_note,
                     focal_length: {346, 32},
                     subject_distance: {3750, 1000},
                     max_aperture_value: {194_698, 65536},
                     fnumber: {40, 10},
                     exposure_time: {1, 350},
                     file_source: 3,
                     sensing_method: 2,
                     focal_plane_resolution_unit: 2,
                     focal_plane_y_resolution: {480_000, 155},
                     focal_plane_x_resolution: {640_000, 206}
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {180, 1},
                   x_resolution: {180, 1},
                   ycbcr_positioning: 1,
                   date_time: "2001:06:09 15:17:32",
                   model: "Canon DIGITAL IXUS"
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {180, 1},
                   x_resolution: {180, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 5342,
                   jpeg_interchange_format: 1524
                 }
               }
             } = metadata
    end

    test "sony-powershota5.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/sony-powershota5.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)

      assert metadata == %{
               jfif: %{
                 version_major: 1,
                 version_minor: 2,
                 density_units: 1,
                 density_x: 180,
                 density_y: 180,
                 thumbnail_width: 0,
                 thumbnail_height: 0,
                 thumbnail_data: ""
               }
             }
    end

    test "sanyo-vpcsx550.jpg" do
      jpeg_bytes = File.read!("test/assets/exif/exif-org/sanyo-vpcsx550.jpg")
      {:ok, %Image{metadata: metadata}} = Imagex.decode(jpeg_bytes, format: :jpeg)

      assert Map.keys(metadata) == [:exif]

      assert %{
               exif: %{
                 ifd0: %{
                   make: "SANYO Electric Co.,Ltd.",
                   exif: %{
                     pixel_y_dimension: 480,
                     pixel_x_dimension: 640,
                     color_space: 1,
                     user_comment: _user_comment,
                     date_time_original: "2000:11:18 21:14:19",
                     flash_pix_version: ~c"0100",
                     flash: 0,
                     metering_mode: 2,
                     exposure_bias_value: {0, 10},
                     compressed_bits_per_pixel: {17, 10},
                     components_configuration: [1, 2, 3, 0],
                     date_time_digitized: "2000:11:18 21:14:19",
                     exif_version: ~c"0210",
                     iso_speed_ratings: 400,
                     interoperability: %{
                       interoperability_version: ~c"0100",
                       interoperability_index: "R98"
                     },
                     maker_note: _maker_note,
                     focal_length: {60, 10},
                     light_source: 0,
                     max_aperture_value: {3, 1},
                     fnumber: {24, 10},
                     exposure_time: {10, 483},
                     file_source: 3
                   },
                   orientation: 1,
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   ycbcr_positioning: 2,
                   date_time: "2000:11:18 21:14:19",
                   model: "SX113 ",
                   image_description: "SANYO DIGITAL CAMERA",
                   software: "V113p-73"
                 },
                 ifd1: %{
                   resolution_unit: 2,
                   y_resolution: {72, 1},
                   x_resolution: {72, 1},
                   compression: 6,
                   thumbnail_data: _thumbnail_data,
                   jpeg_interchange_format_length: 13234,
                   jpeg_interchange_format: 1070
                 }
               }
             } = metadata
    end
  end
end
