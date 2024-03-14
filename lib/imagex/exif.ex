defmodule Imagex.Exif do
  @moduledoc """
  Provides functions for reading EXIF data.

  Reference:
  https://www.media.mit.edu/pia/Research/deepview/exif.html
  """

  def read_exif_from_jpeg(bytes) when is_binary(bytes) do
    Imagex.Jfif.read_metadata_from_jpeg(bytes)
  end

  def read_exif_from_jxl(bytes) when is_binary(bytes) do
    Imagex.Jxl.read_metadata_from_jxl(bytes)
  end

  def read_exif_from_tiff(app1_data) do
    # first, parse the header for the endian and offset
    <<tiff_header::binary-size(8), _rest::binary>> = app1_data

    {endian, offset} =
      case tiff_header do
        <<"II"::binary, 0x2A::16-little, offset::binary-size(4)>> -> {:little, offset}
        <<"MM"::binary, 0x2A::16-big, offset::binary-size(4)>> -> {:big, offset}
      end

    offset = :binary.decode_unsigned(offset, endian)

    # parse the Image File Directory (IFD)
    exif =
      parse_ifds(app1_data, endian, offset)

      # for each IFD, give it a name ifd#n where n is its index, and put them all into a map
      |> Enum.with_index(fn element, index -> {String.to_atom("ifd#{index}"), element} end)
      |> Enum.into(%{})

    # if we have a thumbnail, extract the binary of the thumbnail
    exif =
      case exif do
        %{ifd1: %{compression: 1, strip_offsets: strip_offsets, strip_byte_counts: strip_byte_counts}} ->
          strip_byte_counts_sum =
            case strip_byte_counts do
              counts when is_list(counts) -> Enum.sum(counts)
              count when is_integer(count) -> count
            end

          thumbnail_data = binary_part(app1_data, strip_offsets, strip_byte_counts_sum)
          put_in(exif, [:ifd1, :thumbnail_data], thumbnail_data)

        %{
          ifd1: %{
            compression: 6,
            jpeg_interchange_format: jpeg_interchange_format,
            jpeg_interchange_format_length: jpeg_interchange_format_length
          }
        } ->
          thumbnail_data = binary_part(app1_data, jpeg_interchange_format, jpeg_interchange_format_length)
          put_in(exif, [:ifd1, :thumbnail_data], thumbnail_data)

        _ ->
          exif
      end

    %{exif: exif}
  end

  def parse_ifds(_app1_data, _endian, 0) do
    []
  end

  def parse_ifds(app1_data, endian, offset) do
    <<_::binary-size(offset), num_entries::binary-size(2), rest::binary>> = app1_data
    num_entries = :binary.decode_unsigned(num_entries, endian)

    <<idf_buffer::binary-size(num_entries * 12), next_idf_offset::binary-size(4), _rest::binary>> = rest
    next_idf_offset = :binary.decode_unsigned(next_idf_offset, endian)

    tags =
      for <<chunk::binary-size(12) <- idf_buffer>> do
        parse_tag(chunk, endian, app1_data)
      end

    [Enum.into(tags, %{}) | parse_ifds(app1_data, endian, next_idf_offset)]
  end

  def parse_tag(chunk, endian, app1_data) do
    <<tag_id::binary-size(2), data_format::binary-size(2), num_components::binary-size(4), data_value::binary-size(4)>> =
      chunk

    tag_id = :binary.decode_unsigned(tag_id, endian)

    {data_format, bytes_per_component} =
      case :binary.decode_unsigned(data_format, endian) do
        1 -> {:unsigned_byte, 1}
        2 -> {:ascii_string, 1}
        3 -> {:unsigned_short, 2}
        4 -> {:unsigned_long, 4}
        5 -> {:unsigned_rational, 8}
        6 -> {:signed_byte, 1}
        7 -> {:undefined, 1}
        8 -> {:signed_short, 2}
        9 -> {:signed_long, 4}
        10 -> {:signed_rational, 8}
        11 -> {:float, 4}
        12 -> {:double, 8}
      end

    num_components = :binary.decode_unsigned(num_components, endian)
    total_bytes_size = num_components * bytes_per_component

    # the data is either the value itself if the size <= 4, or it is an offset to the value
    data_value =
      if total_bytes_size > 4 do
        value_offset = :binary.decode_unsigned(data_value, endian)
        <<_::binary-size(value_offset), data_value::binary-size(total_bytes_size), _::binary>> = app1_data
        data_value
      else
        data_value
      end

    # map the tag_ids to their names
    # copied from: https://github.com/libexif/libexif/blob/60190e7/libexif/exif-tag.h#L37-L172
    tag_name =
      case tag_id do
        0x0001 -> :interoperability_index
        0x0002 -> :interoperability_version
        0x00FE -> :new_subfile_type
        0x0100 -> :image_width
        0x0101 -> :image_length
        0x0102 -> :bits_per_sample
        0x0103 -> :compression
        0x0106 -> :photometric_interpretation
        0x010A -> :fill_order
        0x010D -> :document_name
        0x010E -> :image_description
        0x010F -> :make
        0x0110 -> :model
        0x0111 -> :strip_offsets
        0x0112 -> :orientation
        0x0115 -> :samples_per_pixel
        0x0116 -> :rows_per_strip
        0x0117 -> :strip_byte_counts
        0x011A -> :x_resolution
        0x011B -> :y_resolution
        0x011C -> :planar_configuration
        0x0128 -> :resolution_unit
        0x012D -> :transfer_function
        0x0131 -> :software
        0x0132 -> :date_time
        0x013B -> :artist
        0x013E -> :white_point
        0x013F -> :primary_chromaticities
        0x014A -> :sub_ifds
        0x0156 -> :transfer_range
        0x0200 -> :jpeg_proc
        0x0201 -> :jpeg_interchange_format
        0x0202 -> :jpeg_interchange_format_length
        0x0211 -> :ycbcr_coefficients
        0x0212 -> :ycbcr_sub_sampling
        0x0213 -> :ycbcr_positioning
        0x0214 -> :reference_black_white
        0x02BC -> :xml_packet
        0x1000 -> :related_image_file_format
        0x1001 -> :related_image_width
        0x1002 -> :related_image_length
        0x80E5 -> :image_depth
        0x828D -> :cfa_repeat_pattern_dim
        0x828E -> :cfa_pattern
        0x828F -> :battery_level
        0x8298 -> :copyright
        0x829A -> :exposure_time
        0x829D -> :fnumber
        0x83BB -> :iptc_naa
        0x8649 -> :image_resources
        0x8769 -> :exif_ifd_pointer
        0x8773 -> :inter_color_profile
        0x8822 -> :exposure_program
        0x8824 -> :spectral_sensitivity
        0x8825 -> :gps_info_ifd_pointer
        0x8827 -> :iso_speed_ratings
        0x8828 -> :oecf
        0x882A -> :time_zone_offset
        0x8830 -> :sensitivity_type
        0x8831 -> :standard_output_sensitivity
        0x8832 -> :recommended_exposure_index
        0x8833 -> :iso_speed
        0x8834 -> :iso_speedlatitudeyyy
        0x8835 -> :iso_speedlatitudezzz
        0x9000 -> :exif_version
        0x9003 -> :date_time_original
        0x9004 -> :date_time_digitized
        0x9010 -> :offset_time
        0x9011 -> :offset_time_original
        0x9012 -> :offset_time_digitized
        0x9101 -> :components_configuration
        0x9102 -> :compressed_bits_per_pixel
        0x9201 -> :shutter_speed_value
        0x9202 -> :aperture_value
        0x9203 -> :brightness_value
        0x9204 -> :exposure_bias_value
        0x9205 -> :max_aperture_value
        0x9206 -> :subject_distance
        0x9207 -> :metering_mode
        0x9208 -> :light_source
        0x9209 -> :flash
        0x920A -> :focal_length
        0x9214 -> :subject_area
        0x9216 -> :tiff_ep_standard_id
        0x927C -> :maker_note
        0x9286 -> :user_comment
        0x9290 -> :sub_sec_time
        0x9291 -> :sub_sec_time_original
        0x9292 -> :sub_sec_time_digitized
        0x9C9B -> :xp_title
        0x9C9C -> :xp_comment
        0x9C9D -> :xp_author
        0x9C9E -> :xp_keywords
        0x9C9F -> :xp_subject
        0xA000 -> :flash_pix_version
        0xA001 -> :color_space
        0xA002 -> :pixel_x_dimension
        0xA003 -> :pixel_y_dimension
        0xA004 -> :related_sound_file
        0xA005 -> :interoperability_ifd_pointer
        0xA20B -> :flash_energy
        0xA20C -> :spatial_frequency_response
        0xA20E -> :focal_plane_x_resolution
        0xA20F -> :focal_plane_y_resolution
        0xA210 -> :focal_plane_resolution_unit
        0xA214 -> :subject_location
        0xA215 -> :exposure_index
        0xA217 -> :sensing_method
        0xA300 -> :file_source
        0xA301 -> :scene_type
        0xA302 -> :new_cfa_pattern
        0xA401 -> :custom_rendered
        0xA402 -> :exposure_mode
        0xA403 -> :white_balance
        0xA404 -> :digital_zoom_ratio
        0xA405 -> :focal_length_in_35mm_film
        0xA406 -> :scene_capture_type
        0xA407 -> :gain_control
        0xA408 -> :contrast
        0xA409 -> :saturation
        0xA40A -> :sharpness
        0xA40B -> :device_setting_description
        0xA40C -> :subject_distance_range
        0xA420 -> :image_unique_id
        0xA430 -> :camera_owner_name
        0xA431 -> :body_serial_number
        0xA432 -> :lens_specification
        0xA433 -> :lens_make
        0xA434 -> :lens_model
        0xA435 -> :lens_serial_number
        0xA460 -> :composite_image
        0xA461 -> :source_image_number_of_composite_image
        0xA462 -> :source_exposure_times_of_composite_image
        0xA500 -> :gamma
        0xC4A5 -> :print_image_matching
        0xEA1C -> :padding
        # GPS tags overlap with above ones.
        0x0000 -> :version_id
        # overlaps with :interoperability_index and :interoperability_version
        # 0x0001 -> :latitude_ref
        # 0x0002 -> :latitude
        0x0003 -> :longitude_ref
        0x0004 -> :longitude
        0x0005 -> :altitude_ref
        0x0006 -> :altitude
        0x0007 -> :time_stamp
        0x0008 -> :satellites
        0x0009 -> :status
        0x000A -> :measure_mode
        0x000B -> :dop
        0x000C -> :speed_ref
        0x000D -> :speed
        0x000E -> :track_ref
        0x000F -> :track
        0x0010 -> :img_direction_ref
        0x0011 -> :img_direction
        0x0012 -> :map_datum
        0x0013 -> :dest_latitude_ref
        0x0014 -> :dest_latitude
        0x0015 -> :dest_longitude_ref
        0x0016 -> :dest_longitude
        0x0017 -> :dest_bearing_ref
        0x0018 -> :dest_bearing
        0x0019 -> :dest_distance_ref
        0x001A -> :dest_distance
        0x001B -> :processing_method
        0x001C -> :area_information
        0x001D -> :date_stamp
        0x001E -> :differential
        0x001F -> :h_positioning_error
        # tiff tags (see tiff.h)
        0xFF -> :osubfiletype
        0x107 -> :threshholding
        0x108 -> :cellwidth
        0x109 -> :celllength
        0x118 -> :minsamplevalue
        0x119 -> :maxsamplevalue
        0x11D -> :pagename
        0x11E -> :xposition
        0x11F -> :yposition
        0x120 -> :freeoffsets
        0x121 -> :freebytecounts
        0x122 -> :grayresponseunit
        0x123 -> :grayresponsecurve
        0x124 -> :group3options
        0x125 -> :group4options
        0x129 -> :pagenumber
        0x12C -> :colorresponseunit
        0x13C -> :hostcomputer
        0x13D -> :predictor
        0x140 -> :colormap
        0x141 -> :halftonehints
        0x142 -> :tilewidth
        0x143 -> :tilelength
        0x144 -> :tileoffsets
        0x145 -> :tilebytecounts
        0x146 -> :badfaxlines
        0x147 -> :cleanfaxdata
        0x148 -> :consecutivebadfaxlines
        0x14C -> :inkset
        0x14D -> :inknames
        0x14E -> :numberofinks
        0x150 -> :dotrange
        0x151 -> :targetprinter
        0x152 -> :extrasamples
        0x153 -> :sampleformat
        0x154 -> :sminsamplevalue
        0x155 -> :smaxsamplevalue
        0x157 -> :clippath
        0x158 -> :xclippathunits
        0x159 -> :yclippathunits
        0x15A -> :indexed
        0x15B -> :jpegtables
        0x15F -> :opiproxy
        0x190 -> :globalparametersifd
        0x191 -> :profiletype
        0x192 -> :faxprofile
        0x193 -> :codingmethods
        0x194 -> :versionyear
        0x195 -> :modenumber
        0x1B1 -> :decode
        0x1B2 -> :imagebasecolor
        0x1B3 -> :t82options
        0x203 -> :jpegrestartinterval
        0x205 -> :jpeglosslesspredictors
        0x206 -> :jpegpointtransform
        0x207 -> :jpegqtables
        0x208 -> :jpegdctables
        0x209 -> :jpegactables
        0x22F -> :striprowcounts
        0x800D -> :opiimageid
        0x80A4 -> :tiffannotationdata
        0x80B9 -> :refpts
        0x80BA -> :regiontackpoint
        0x80BB -> :regionwarpcorners
        0x80BC -> :regionaffine
        0x80E3 -> :matteing
        0x80E4 -> :datatype
        0x80E6 -> :tiledepth
        0x8214 -> :pixar_imagefullwidth
        0x8215 -> :pixar_imagefulllength
        0x8216 -> :pixar_textureformat
        0x8217 -> :pixar_wrapmodes
        0x8218 -> :pixar_fovcot
        0x8219 -> :pixar_matrix_worldtoscreen
        0x821A -> :pixar_matrix_worldtocamera
        0x827D -> :writerserialnumber
        0x82A5 -> :md_filetag
        0x82A6 -> :md_scalepixel
        0x82A7 -> :md_colortable
        0x82A8 -> :md_labname
        0x82A9 -> :md_sampleinfo
        0x82AA -> :md_prepdate
        0x82AB -> :md_preptime
        0x82AC -> :md_fileunits
        0x847E -> :ingr_packet_data_tag
        0x847F -> :ingr_flag_registers
        0x8480 -> :irasb_transormation_matrix
        0x8482 -> :modeltiepointtag
        0x84E0 -> :it8site
        0x84E1 -> :it8colorsequence
        0x84E2 -> :it8header
        0x84E3 -> :it8rasterpadding
        0x84E4 -> :it8bitsperrunlength
        0x84E5 -> :it8bitsperextendedrunlength
        0x84E6 -> :it8colortable
        0x84E7 -> :it8imagecolorindicator
        0x84E8 -> :it8bkgcolorindicator
        0x84E9 -> :it8imagecolorvalue
        0x84EA -> :it8bkgcolorvalue
        0x84EB -> :it8pixelintensityrange
        0x84EC -> :it8transparencyindicator
        0x84ED -> :it8colorcharacterization
        0x84EE -> :it8hcusage
        0x84EF -> :it8trapindicator
        0x84F0 -> :it8cmykequivalent
        0x85B8 -> :framecount
        0x85D8 -> :modeltransformationtag
        0x87AC -> :imagelayer
        0x87BE -> :jbigoptions
        0x885C -> :faxrecvparams
        0x885D -> :faxsubaddress
        0x885E -> :faxrecvtime
        0x885F -> :faxdcs
        0x923F -> :stonits
        0x8871 -> :fedex_edr
        0x935C -> :imagesourcedata
        0xA480 -> :gdal_metadata
        0xA481 -> :gdal_nodata
        0xC427 -> :oce_scanjob_description
        0xC428 -> :oce_application_selector
        0xC429 -> :oce_identification_number
        0xC42A -> :oce_imagelogic_characteristics
        0xC5F2 -> :lerc_parameters
        0xC612 -> :dngversion
        0xC613 -> :dngbackwardversion
        0xC614 -> :uniquecameramodel
        0xC615 -> :localizedcameramodel
        0xC616 -> :cfaplanecolor
        0xC617 -> :cfalayout
        0xC618 -> :linearizationtable
        0xC619 -> :blacklevelrepeatdim
        0xC61A -> :blacklevel
        0xC61B -> :blackleveldeltah
        0xC61C -> :blackleveldeltav
        0xC61D -> :whitelevel
        0xC61E -> :defaultscale
        0xC61F -> :defaultcroporigin
        0xC620 -> :defaultcropsize
        0xC621 -> :colormatrix1
        0xC622 -> :colormatrix2
        0xC623 -> :cameracalibration1
        0xC624 -> :cameracalibration2
        0xC625 -> :reductionmatrix1
        0xC626 -> :reductionmatrix2
        0xC627 -> :analogbalance
        0xC628 -> :asshotneutral
        0xC629 -> :asshotwhitexy
        0xC62A -> :baselineexposure
        0xC62B -> :baselinenoise
        0xC62C -> :baselinesharpness
        0xC62D -> :bayergreensplit
        0xC62E -> :linearresponselimit
        0xC62F -> :cameraserialnumber
        0xC630 -> :lensinfo
        0xC631 -> :chromablurradius
        0xC632 -> :antialiasstrength
        0xC633 -> :shadowscale
        0xC634 -> :dngprivatedata
        0xC635 -> :makernotesafety
        0xC65A -> :calibrationilluminant1
        0xC65B -> :calibrationilluminant2
        0xC65C -> :bestqualityscale
        0xC65D -> :rawdatauniqueid
        0xC68B -> :originalrawfilename
        0xC68C -> :originalrawfiledata
        0xC68D -> :activearea
        0xC68E -> :maskedareas
        0xC68F -> :asshoticcprofile
        0xC690 -> :asshotpreprofilematrix
        0xC691 -> :currenticcprofile
        0xC692 -> :currentpreprofilematrix
        0xC6BF -> :colorimetricreference
        0xC6F3 -> :cameracalibrationsignature
        0xC6F4 -> :profilecalibrationsignature
        0xC6F6 -> :asshotprofilename
        0xC6F7 -> :noisereductionapplied
        0xC6F8 -> :profilename
        0xC6F9 -> :profilehuesatmapdims
        0xC6FA -> :profilehuesatmapdata1
        0xC6FB -> :profilehuesatmapdata2
        0xC6FC -> :profiletonecurve
        0xC6FD -> :profileembedpolicy
        0xC6FE -> :profilecopyright
        0xC714 -> :forwardmatrix1
        0xC715 -> :forwardmatrix2
        0xC716 -> :previewapplicationname
        0xC717 -> :previewapplicationversion
        0xC718 -> :previewsettingsname
        0xC719 -> :previewsettingsdigest
        0xC71A -> :previewcolorspace
        0xC71B -> :previewdatetime
        0xC71C -> :rawimagedigest
        0xC71D -> :originalrawfiledigest
        0xC71E -> :subtileblocksize
        0xC71F -> :rowinterleavefactor
        0xC725 -> :profilelooktabledims
        0xC726 -> :profilelooktabledata
        0xC740 -> :opcodelist1
        0xC741 -> :opcodelist2
        0xC74E -> :opcodelist3
        0xC761 -> :noiseprofile
        0xC7B5 -> :defaultusercrop
        0xC7A6 -> :defaultblackrender
        0xC7A5 -> :baselineexposureoffset
        0xC7A4 -> :profilelooktableencoding
        0xC7A3 -> :profilehuesatmapencoding
        0xC791 -> :originaldefaultfinalsize
        0xC792 -> :originalbestqualityfinalsize
        0xC793 -> :originaldefaultcropsize
        0xC7A7 -> :newrawimagedigest
        0xC7A8 -> :rawtopreviewgain
        0xC7E9 -> :depthformat
        0xC7EA -> :depthnear
        0xC7EB -> :depthfar
        0xC7EC -> :depthunits
        0xC7ED -> :depthmeasuretype
        0xC7EE -> :enhanceparams
        0xCD2D -> :profilegaintablemap
        0xCD2E -> :semanticname
        0xCD30 -> :semanticinstanceid
        0xCD38 -> :masksubarea
        0xCD3F -> :rgbtables
        0xCD31 -> :calibrationilluminant3
        0xCD33 -> :colormatrix3
        0xCD32 -> :cameracalibration3
        0xCD3A -> :reductionmatrix3
        0xCD39 -> :profilehuesatmapdata3
        0xCD34 -> :forwardmatrix3
        0xCD35 -> :illuminantdata1
        0xCD36 -> :illuminantdata2
        0xD11F -> :illuminantdata3
        0x8829 -> :ep_interlace
        0x882B -> :ep_selftimermode
        0x920B -> :ep_flashenergy
        0x920C -> :ep_spatialfrequencyresponse
        0x920D -> :ep_noise
        0x920E -> :ep_focalplanexresolution
        0x920F -> :ep_focalplaneyresolution
        0x9210 -> :ep_focalplaneresolutionunit
        0x9211 -> :ep_imagenumber
        0x9212 -> :ep_securityclassification
        0x9213 -> :ep_imagehistory
        0x9215 -> :ep_exposureindex
        0x9217 -> :ep_sensingmethod
        0xC69C -> :rpccoefficient
        0xC660 -> :alias_layer_metadata
        0xC6DC -> :tiff_rsid
        0xC6DD -> :geo_metadata
        0xC6F5 -> :extracameraprofiles
        0xFFFF -> :dcshueshiftvalues
        0x10000 -> :faxmode
        0x10001 -> :jpegquality
        0x10002 -> :jpegcolormode
        0x10003 -> :jpegtablesmode
        0x10004 -> :faxfillfunc
        0x1000D -> :pixarlogdatafmt
        0x1000E -> :dcsimagertype
        0x1000F -> :dcsinterpmode
        0x10010 -> :dcsbalancearray
        0x10011 -> :dcscorrectmatrix
        0x10012 -> :dcsgamma
        0x10013 -> :dcstoeshoulderpts
        0x10014 -> :dcscalibrationfd
        0x10015 -> :zipquality
        0x10016 -> :pixarlogquality
        0x10017 -> :dcscliprectangle
        0x10018 -> :sgilogdatafmt
        0x10019 -> :sgilogencode
        0x1001A -> :lzmapreset
        0x1001B -> :persample
        0x1001C -> :zstd_level
        0x1001D -> :lerc_version
        0x1001E -> :lerc_add_compression
        0x1001F -> :lerc_maxzerror
        0x10020 -> :webp_level
        0x10021 -> :webp_lossless
        0x10023 -> :webp_lossless_exact
        0x10022 -> :deflate_subcodec
        _ -> :unknown
      end

    decode_multiple = fn fun, args ->
      decode_maybe_multiple(fun, num_components, bytes_per_component, data_value, args)
    end

    # parse the data value, depending on the data type
    data_value =
      case data_format do
        :ascii_string ->
          String.trim_trailing(data_value, "\0")

        :unsigned_byte ->
          decode_multiple.(&decode_integer/4, [1, false, endian])

        :unsigned_short ->
          decode_multiple.(&decode_integer/4, [2, false, endian])

        :unsigned_long ->
          decode_multiple.(&decode_integer/4, [4, false, endian])

        :unsigned_rational ->
          decode_multiple.(&decode_rational/3, [false, endian])

        :signed_byte ->
          decode_multiple.(&decode_integer/4, [1, true, endian])

        :signed_short ->
          decode_multiple.(&decode_integer/4, [2, true, endian])

        :signed_long ->
          decode_multiple.(&decode_integer/4, [4, true, endian])

        :signed_rational ->
          decode_multiple.(&decode_rational/3, [true, endian])

        :float ->
          decode_multiple.(&decode_float/2, [4])

        :double ->
          decode_multiple.(&decode_float/2, [8])

        :undefined ->
          decode_multiple.(&decode_integer/4, [1, false, endian])
      end

    # for pointers, follow the pointer and parse the IFD instead of returning the pointer
    case tag_name do
      :exif_ifd_pointer ->
        {:exif, parse_ifds(app1_data, endian, data_value) |> hd() |> Enum.into(%{})}

      :gps_info_ifd_pointer ->
        {:gps,
         parse_ifds(app1_data, endian, data_value)
         |> hd()
         |> Enum.map(fn {key, value} = entry ->
           # we need to replace a couple of tag names because they overlap with other tags
           case key do
             :interoperability_index -> {:latitude_ref, value}
             :interoperability_version -> {:latitude, value}
             _ -> entry
           end
         end)
         |> Enum.into(%{})}

      :interoperability_ifd_pointer ->
        {:interoperability, parse_ifds(app1_data, endian, data_value) |> hd() |> Enum.into(%{})}

      _ ->
        {tag_name, data_value}
    end
  end

  defp decode_maybe_multiple(fun, count, bytes_per_component, data_value, args) do
    if count == 1 do
      apply(fun, [data_value | args])
    else
      for <<chunk::binary-size(bytes_per_component) <- data_value>> do
        apply(fun, [chunk | args])
      end
    end
  end

  defp decode_integer(buffer, num_bytes, signed, endian) do
    if signed do
      case endian do
        :little ->
          <<value::integer-signed-size(num_bytes * 8)-little, _rest::binary>> = buffer
          value

        :big ->
          <<value::integer-signed-size(num_bytes * 8)-big, _rest::binary>> = buffer
          value
      end
    else
      case endian do
        :little ->
          <<value::integer-unsigned-size(num_bytes * 8)-little, _rest::binary>> = buffer
          value

        :big ->
          <<value::integer-unsigned-size(num_bytes * 8)-big, _rest::binary>> = buffer
          value
      end
    end
  end

  defp decode_float(buffer, num_bytes) do
    <<value::float-size(num_bytes * 8), _rest::binary>> = buffer
    value
  end

  defp decode_rational(buffer, signed, endian) do
    <<numerator::binary-size(4), denominator::binary-size(4)>> = buffer
    {decode_integer(numerator, 4, signed, endian), decode_integer(denominator, 4, signed, endian)}
  end
end
