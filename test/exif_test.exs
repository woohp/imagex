defmodule ExifTest do
  use ExUnit.Case
  doctest Imagex.Exif

  test "exif from lena.jpg" do
    jpeg_bytes = File.read!("test/assets/lena.jpg")
    {:ok, {_image, exif}} = Imagex.decode(jpeg_bytes, format: :jpeg)

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
    {:ok, {_image, exif}} = Imagex.decode(png_bytes, format: :png)

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

  test "exif with rgb thumbnail in jpeg file" do
    jpeg_bytes = File.read!("test/assets/exif-rgb-thumbnail-sony-d700.jpg")
    {:ok, {_image, exif}} = Imagex.decode(jpeg_bytes, format: :jpeg)

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
    jpeg_bytes = File.read!("test/assets/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg")
    {:ok, {_image, exif}} = Imagex.decode(jpeg_bytes, format: :jpeg)

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
    assert {:ok, {_image, nil}} = Imagex.decode(thumbnail_data, format: :jpeg)
  end

  test "exif with empty icc profile" do
    jpeg_bytes = File.read!("test/assets/exif-empty-icc-profile.jpeg")
    {:ok, {_image, exif}} = Imagex.decode(jpeg_bytes, format: :jpeg)

    assert exif == %{
             ifd0: %{
               exif: %{
                 pixel_y_dimension: 3600,
                 pixel_x_dimension: 2700,
                 exif_version: ~c"0220",
                 interoperability_ifd_pointer: 188,
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
    jpeg_bytes = File.read!("test/assets/exif-jfif-app13-app14ycck-3channel.jpg")
    {:ok, {_image, exif}} = Imagex.decode(jpeg_bytes, format: :jpeg)

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
    jpeg_bytes = File.read!("test/assets/exif-rgb-thumbnail-bad-exif-kodak-dc210.jpg")
    {:ok, {_image, exif}} = Imagex.decode(jpeg_bytes, format: :jpeg)

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
end
