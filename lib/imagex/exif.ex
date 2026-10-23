defmodule Imagex.Exif do
  @moduledoc false

  # Reference: https://www.media.mit.edu/pia/Research/deepview/exif.html

  # The tags that can be written, as {id, name, type, count} by the IFDs they belong to. Decoding keeps
  # only these, so decoded EXIF can always be written back.
  @tags [
    {[:ifd0, :ifd1],
     [
       {0x00FE, :new_subfile_type, :unsigned_long, :any},
       {0x0100, :image_width, :unsigned_long, :any},
       {0x0101, :image_length, :unsigned_long, :any},
       {0x0102, :bits_per_sample, :unsigned_short, :any},
       {0x0103, :compression, :unsigned_short, :any},
       {0x0106, :photometric_interpretation, :unsigned_short, :any},
       {0x010A, :fill_order, :unsigned_short, :any},
       {0x010D, :document_name, :ascii_string, :any},
       {0x010E, :image_description, :ascii_string, :any},
       {0x010F, :make, :ascii_string, :any},
       {0x0110, :model, :ascii_string, :any},
       {0x0112, :orientation, :unsigned_short, :any},
       {0x0115, :samples_per_pixel, :unsigned_short, :any},
       {0x0116, :rows_per_strip, :unsigned_long, :any},
       {0x0117, :strip_byte_counts, :unsigned_long, :any},
       {0x011A, :x_resolution, :unsigned_rational, 1},
       {0x011B, :y_resolution, :unsigned_rational, 1},
       {0x011C, :planar_configuration, :unsigned_short, :any},
       {0x0128, :resolution_unit, :unsigned_short, :any},
       {0x012D, :transfer_function, :unsigned_short, :any},
       {0x0131, :software, :ascii_string, :any},
       {0x0132, :date_time, :ascii_string, :any},
       {0x013B, :artist, :ascii_string, :any},
       {0x013C, :hostcomputer, :ascii_string, :any},
       {0x013E, :white_point, :unsigned_rational, 2},
       {0x013F, :primary_chromaticities, :unsigned_rational, :any},
       {0x0202, :jpeg_interchange_format_length, :unsigned_long, :any},
       {0x0211, :ycbcr_coefficients, :unsigned_rational, :any},
       {0x0212, :ycbcr_sub_sampling, :unsigned_short, 2},
       {0x0213, :ycbcr_positioning, :unsigned_short, :any},
       {0x0214, :reference_black_white, :unsigned_rational, :any},
       {0x02BC, :xml_packet, :ascii_string, :any},
       {0x8298, :copyright, :ascii_string, :any},
       {0x8773, :inter_color_profile, :undefined, :any},
       {0x882A, :time_zone_offset, :signed_short, :any},
       {0x9C9B, :xp_title, :unsigned_byte, :any},
       {0x9C9C, :xp_comment, :unsigned_byte, :any},
       {0x9C9D, :xp_author, :unsigned_byte, :any},
       {0x9C9E, :xp_keywords, :unsigned_byte, :any},
       {0x9C9F, :xp_subject, :unsigned_byte, :any}
     ]},
    {[:exif],
     [
       {0x828D, :cfa_repeat_pattern_dim, :unsigned_short, 2},
       {0x828E, :cfa_pattern, :undefined, :any},
       {0x829A, :exposure_time, :unsigned_rational, :any},
       {0x829D, :fnumber, :unsigned_rational, :any},
       {0x8822, :exposure_program, :unsigned_short, :any},
       {0x8824, :spectral_sensitivity, :ascii_string, :any},
       {0x8827, :iso_speed_ratings, :unsigned_short, :any},
       {0x8828, :oecf, :undefined, :any},
       {0x8830, :sensitivity_type, :unsigned_short, :any},
       {0x8831, :standard_output_sensitivity, :unsigned_long, :any},
       {0x8832, :recommended_exposure_index, :unsigned_long, :any},
       {0x8833, :iso_speed, :unsigned_long, :any},
       {0x9000, :exif_version, :undefined, 4},
       {0x9003, :date_time_original, :ascii_string, :any},
       {0x9004, :date_time_digitized, :ascii_string, :any},
       {0x9010, :offset_time, :ascii_string, :any},
       {0x9011, :offset_time_original, :ascii_string, :any},
       {0x9012, :offset_time_digitized, :ascii_string, :any},
       {0x9101, :components_configuration, :undefined, 4},
       {0x9102, :compressed_bits_per_pixel, :unsigned_rational, :any},
       {0x9201, :shutter_speed_value, :signed_rational, :any},
       {0x9202, :aperture_value, :unsigned_rational, :any},
       {0x9203, :brightness_value, :signed_rational, :any},
       {0x9204, :exposure_bias_value, :signed_rational, :any},
       {0x9205, :max_aperture_value, :unsigned_rational, :any},
       {0x9206, :subject_distance, :unsigned_rational, :any},
       {0x9207, :metering_mode, :unsigned_short, :any},
       {0x9208, :light_source, :unsigned_short, :any},
       {0x9209, :flash, :unsigned_short, :any},
       {0x920A, :focal_length, :unsigned_rational, :any},
       {0x9214, :subject_area, :unsigned_short, :any},
       {0x927C, :maker_note, :undefined, :any},
       {0x9286, :user_comment, :undefined, :any},
       {0x9290, :sub_sec_time, :ascii_string, :any},
       {0x9291, :sub_sec_time_original, :ascii_string, :any},
       {0x9292, :sub_sec_time_digitized, :ascii_string, :any},
       {0xA000, :flash_pix_version, :undefined, 4},
       {0xA001, :color_space, :unsigned_short, :any},
       {0xA002, :pixel_x_dimension, :unsigned_long, :any},
       {0xA003, :pixel_y_dimension, :unsigned_long, :any},
       {0xA004, :related_sound_file, :ascii_string, :any},
       {0xA20B, :flash_energy, :unsigned_rational, :any},
       {0xA20C, :spatial_frequency_response, :undefined, :any},
       {0xA20E, :focal_plane_x_resolution, :unsigned_rational, :any},
       {0xA20F, :focal_plane_y_resolution, :unsigned_rational, :any},
       {0xA210, :focal_plane_resolution_unit, :unsigned_short, :any},
       {0xA214, :subject_location, :unsigned_short, 2},
       {0xA215, :exposure_index, :unsigned_rational, :any},
       {0xA217, :sensing_method, :unsigned_short, :any},
       {0xA300, :file_source, :undefined, :any},
       {0xA301, :scene_type, :undefined, :any},
       {0xA401, :custom_rendered, :unsigned_short, :any},
       {0xA402, :exposure_mode, :unsigned_short, :any},
       {0xA403, :white_balance, :unsigned_short, :any},
       {0xA404, :digital_zoom_ratio, :unsigned_rational, :any},
       {0xA405, :focal_length_in_35mm_film, :unsigned_short, :any},
       {0xA406, :scene_capture_type, :unsigned_short, :any},
       {0xA407, :gain_control, :unsigned_short, :any},
       {0xA408, :contrast, :unsigned_short, :any},
       {0xA409, :saturation, :unsigned_short, :any},
       {0xA40A, :sharpness, :unsigned_short, :any},
       {0xA40B, :device_setting_description, :undefined, :any},
       {0xA40C, :subject_distance_range, :unsigned_short, :any},
       {0xA420, :image_unique_id, :ascii_string, :any},
       {0xA430, :camera_owner_name, :ascii_string, :any},
       {0xA431, :body_serial_number, :ascii_string, :any},
       {0xA432, :lens_specification, :unsigned_rational, 4},
       {0xA433, :lens_make, :ascii_string, :any},
       {0xA434, :lens_model, :ascii_string, :any},
       {0xA435, :lens_serial_number, :ascii_string, :any},
       {0xA460, :composite_image, :unsigned_short, :any},
       {0xA500, :gamma, :unsigned_rational, :any}
     ]},
    {[:gps],
     [
       {0x0000, :version_id, :unsigned_byte, 4},
       {0x0001, :latitude_ref, :ascii_string, 2},
       {0x0002, :latitude, :unsigned_rational, 3},
       {0x0003, :longitude_ref, :ascii_string, 2},
       {0x0004, :longitude, :unsigned_rational, 3},
       {0x0005, :altitude_ref, :unsigned_byte, 1},
       {0x0006, :altitude, :unsigned_rational, :any},
       {0x0007, :time_stamp, :unsigned_rational, 3},
       {0x0008, :satellites, :ascii_string, :any},
       {0x0009, :status, :ascii_string, :any},
       {0x000A, :measure_mode, :ascii_string, :any},
       {0x000B, :dop, :unsigned_rational, :any},
       {0x000C, :speed_ref, :ascii_string, :any},
       {0x000D, :speed, :unsigned_rational, :any},
       {0x000E, :track_ref, :ascii_string, :any},
       {0x000F, :track, :unsigned_rational, :any},
       {0x0010, :img_direction_ref, :ascii_string, :any},
       {0x0011, :img_direction, :unsigned_rational, :any},
       {0x0012, :map_datum, :ascii_string, :any},
       {0x0013, :dest_latitude_ref, :ascii_string, :any},
       {0x0014, :dest_latitude, :unsigned_rational, :any},
       {0x0015, :dest_longitude_ref, :ascii_string, :any},
       {0x0016, :dest_longitude, :unsigned_rational, :any},
       {0x0017, :dest_bearing_ref, :ascii_string, :any},
       {0x0018, :dest_bearing, :unsigned_rational, :any},
       {0x0019, :dest_distance_ref, :ascii_string, :any},
       {0x001A, :dest_distance, :unsigned_rational, :any},
       {0x001B, :processing_method, :undefined, :any},
       {0x001C, :area_information, :undefined, :any},
       {0x001D, :date_stamp, :ascii_string, :any},
       {0x001E, :differential, :unsigned_short, :any},
       {0x001F, :h_positioning_error, :unsigned_rational, :any}
     ]},
    {[:interoperability],
     [
       {0x0001, :interoperability_index, :ascii_string, 4},
       {0x0002, :interoperability_version, :undefined, 4},
       {0x1000, :related_image_file_format, :ascii_string, :any},
       {0x1001, :related_image_width, :unsigned_long, :any},
       {0x1002, :related_image_length, :unsigned_long, :any}
     ]}
  ]

  @tag_schemas (for {locations, rows} <- @tags, {id, name, type, count} <- rows, into: %{} do
                  {name, %{locations: locations, id: id, type: type, count: count}}
                end)

  # Sub-IFD pointers and thumbnail offsets are synthesized by the encoder, so they are not writable tags.
  @pointer_tag_ids %{exif: 0x8769, gps: 0x8825, interoperability: 0xA005}
  @thumbnail_offset_tag_ids %{strip_offsets: 0x0111, jpeg_interchange_format: 0x0201}
  @child_ifds %{ifd0: [:exif, :gps], ifd1: [], exif: [:interoperability], gps: [], interoperability: []}

  # Decoding names the writable tags, IFD1's thumbnail offsets, and the pointers to the sub-IFDs the
  # encoder writes; following only those also rules out pointer cycles.
  tag_names =
    for {locations, rows} <- @tags, location <- locations, {id, name, _type, _count} <- rows, into: %{} do
      {{location, id}, name}
    end

  pointer_names =
    for {parent, children} <- @child_ifds, child <- children, into: %{} do
      {{parent, Map.fetch!(@pointer_tag_ids, child)}, child}
    end

  thumbnail_offset_names = Map.new(@thumbnail_offset_tag_ids, fn {name, id} -> {{:ifd1, id}, name} end)
  @tag_names tag_names |> Map.merge(pointer_names) |> Map.merge(thumbnail_offset_names)

  @tiff_types %{
    1 => {:unsigned_byte, 1},
    2 => {:ascii_string, 1},
    3 => {:unsigned_short, 2},
    4 => {:unsigned_long, 4},
    5 => {:unsigned_rational, 8},
    6 => {:signed_byte, 1},
    7 => {:undefined, 1},
    8 => {:signed_short, 2},
    9 => {:signed_long, 4},
    10 => {:signed_rational, 8}
  }

  @tiff_type_ids Map.new(@tiff_types, fn {id, {type, _bytes_per_component}} -> {type, id} end)

  @thumbnail_related_tags MapSet.new([
                            :thumbnail_data,
                            :jpeg_interchange_format,
                            :jpeg_interchange_format_length,
                            :strip_offsets,
                            :strip_byte_counts
                          ])

  @spec encode_exif(map()) :: {:ok, binary()} | {:error, String.t()}
  def encode_exif(exif) when is_map(exif) do
    with {:ok, ifds} <- extract_ifds(exif),
         {:ok, nodes} <- collect_ok(Enum.zip_with(ifds, [:ifd0, :ifd1], &build_ifd_node/2)) do
      {:ok, IO.iodata_to_binary([<<"II", 0x2A::16-little, 8::32-little>> | render_chain(nodes, 8)])}
    end
  end

  # Parses a TIFF-structured EXIF block. Malformed data yields no EXIF, and only what the encoder
  # accepts is kept, so decoded EXIF can always be written back.
  def read_exif_from_tiff(<<"II", 0x2A::16-little, offset::32-little, _::binary>> = data),
    do: read_exif(data, :little, offset)

  def read_exif_from_tiff(<<"MM", 0x2A::16-big, offset::32-big, _::binary>> = data),
    do: read_exif(data, :big, offset)

  def read_exif_from_tiff(_data), do: %{}

  # Numeric arrays decode to lists, so all IFDs share one budget of decoded numeric values; this bounds
  # the work crafted EXIF can cause, including IFDs that point at the same entries.
  @numeric_value_budget 65_536

  defp read_exif(data, endian, offset) do
    case parse_ifd(data, endian, offset, :ifd0, @numeric_value_budget) do
      {:ok, ifd0, ifd1_offset, budget} ->
        case parse_ifd(data, endian, ifd1_offset, :ifd1, budget) do
          {:ok, ifd1, _next_offset, _budget} -> %{exif: %{ifd0: ifd0, ifd1: extract_thumbnail(ifd1, data)}}
          :error -> %{exif: %{ifd0: ifd0}}
        end

      :error ->
        %{}
    end
  end

  # Replaces the thumbnail's offset tags with its bytes; the encoder recomputes the offsets.
  defp extract_thumbnail(ifd, data) do
    strips =
      case ifd do
        %{jpeg_interchange_format: offset, jpeg_interchange_format_length: length} -> [{offset, length}]
        %{strip_offsets: offsets, strip_byte_counts: counts} -> Enum.zip(List.wrap(offsets), List.wrap(counts))
        _ -> []
      end

    ifd = Map.drop(ifd, Enum.to_list(@thumbnail_related_tags))

    in_bounds? = fn {offset, length} ->
      is_integer(offset) and is_integer(length) and offset >= 0 and length >= 0 and offset + length <= byte_size(data)
    end

    # Strips may overlap, so their total is also bounded, or a small block could repeat itself into a huge thumbnail.
    with true <- strips != [] and Enum.all?(strips, in_bounds?),
         true <- Enum.sum_by(strips, &elem(&1, 1)) <= byte_size(data),
         thumbnail_data = Enum.map_join(strips, fn {offset, length} -> binary_part(data, offset, length) end),
         thumbnail_ifd = Map.put(ifd, :thumbnail_data, thumbnail_data),
         {:ok, _normalized} <- normalize_thumbnail_ifd(thumbnail_ifd, :ifd1) do
      thumbnail_ifd
    else
      _ -> ifd
    end
  end

  defp extract_ifds(exif) do
    with :ok <- validate_top_level_ifds(exif),
         {:ok, ifd0} <- normalize_ifd(Map.fetch!(exif, :ifd0), :ifd0) do
      case Map.fetch(exif, :ifd1) do
        {:ok, ifd1} -> with {:ok, ifd1} <- normalize_ifd(ifd1, :ifd1), do: {:ok, [ifd0, ifd1]}
        :error -> {:ok, [ifd0]}
      end
    end
  end

  defp validate_top_level_ifds(exif) do
    cond do
      not Map.has_key?(exif, :ifd0) ->
        {:error, "EXIF metadata must contain ifd0"}

      invalid_key = Enum.find(Map.keys(exif), &(&1 not in [:ifd0, :ifd1])) ->
        {:error, "unsupported EXIF container #{inspect(invalid_key)}"}

      true ->
        :ok
    end
  end

  defp normalize_ifd(ifd, location) when is_map(ifd), do: normalize_thumbnail_ifd(ifd, location)

  defp normalize_ifd(other, location) do
    {:error, "expected #{inspect(location)} to be a map, got: #{inspect(other)}"}
  end

  defp normalize_thumbnail_ifd(ifd, :ifd1) do
    thumbnail_data = Map.get(ifd, :thumbnail_data)
    compression = Map.get(ifd, :compression)

    cond do
      is_nil(thumbnail_data) ->
        case find_present_key(ifd, @thumbnail_related_tags) do
          nil -> {:ok, ifd}
          tag -> {:error, "thumbnail tag #{inspect(tag)} requires :thumbnail_data"}
        end

      not is_binary(thumbnail_data) ->
        {:error, ":thumbnail_data must be a binary"}

      # An explicit compression tag wins; the data is only sniffed when it is missing.
      compression == 6 or (is_nil(compression) and jpeg_thumbnail?(thumbnail_data)) ->
        {:ok,
         ifd
         |> Map.drop([:jpeg_interchange_format, :strip_offsets, :strip_byte_counts])
         |> Map.merge(%{compression: 6, jpeg_interchange_format_length: byte_size(thumbnail_data)})}

      compression in [nil, 1] ->
        # Uncompressed thumbnails are written as a single strip.
        {:ok,
         ifd
         |> Map.drop([:jpeg_interchange_format, :jpeg_interchange_format_length, :strip_offsets])
         |> Map.merge(%{compression: 1, strip_byte_counts: byte_size(thumbnail_data)})
         |> Map.replace(:rows_per_strip, Map.get(ifd, :image_length, 0xFFFFFFFF))}

      true ->
        {:error, "EXIF thumbnails must use compression 6 (JPEG) or 1 (uncompressed)"}
    end
  end

  defp normalize_thumbnail_ifd(ifd, location) do
    case find_present_key(ifd, @thumbnail_related_tags) do
      nil -> {:ok, ifd}
      tag -> {:error, "thumbnail tag #{inspect(tag)} is only supported in ifd1, got #{inspect(location)}"}
    end
  end

  defp jpeg_thumbnail?(<<0xFF, 0xD8, _::binary>>), do: true
  defp jpeg_thumbnail?(_), do: false

  defp find_present_key(ifd, keys) do
    Enum.find(keys, &Map.has_key?(ifd, &1))
  end

  defp render_chain([node], offset) do
    {table, body, _end_offset} = render_ifd(node, offset)
    [table, <<0::32>>, body]
  end

  defp render_chain([node | rest], offset) do
    {table, body, next_offset} = render_ifd(node, offset)
    [table, <<next_offset::32-little>>, body | render_chain(rest, next_offset)]
  end

  # Returns the entry count and table, the bytes after the next-IFD pointer (out-of-line values,
  # then child IFDs), and the offset where those bytes end. The caller writes the next-IFD pointer.
  defp render_ifd(%{entries: entries}, offset) do
    data_offset = offset + 2 + length(entries) * 12 + 4

    {fields, {data, children_offset}} =
      Enum.map_reduce(entries, {[], data_offset}, fn
        %{kind: :child} = entry, acc -> {entry, acc}
        %{kind: :value, data: data}, acc when byte_size(data) <= 4 -> {pad_to_four(data), acc}
        %{data: data}, {out, at} -> {<<at::32-little>>, {[out, pad_to_even(data)], align_even(at + byte_size(data))}}
      end)

    {fields, {children, end_offset}} =
      Enum.map_reduce(fields, {[], children_offset}, fn
        %{child: child}, {out, at} ->
          {table, body, child_end} = render_ifd(child, at)
          {<<at::32-little>>, {[out, table, <<0::32>>, body], child_end}}

        field, acc ->
          {field, acc}
      end)

    table =
      Enum.zip_with(entries, fields, fn entry, field ->
        <<entry.tag_id::16-little, entry.type_id::16-little, entry.count::32-little, field::binary>>
      end)

    {[<<length(entries)::16-little>> | table], [data, children], end_offset}
  end

  defp build_ifd_node(ifd, location) do
    child_keys = Map.fetch!(@child_ifds, location)
    {thumbnail_data, ifd} = Map.pop(ifd, :thumbnail_data)

    entries =
      ifd
      |> Map.drop(child_keys)
      |> Enum.map(&build_value_entry(&1, location))

    entries =
      if thumbnail_data do
        pointer_tag = if ifd.compression == 6, do: :jpeg_interchange_format, else: :strip_offsets
        [{:ok, build_data_pointer_entry(pointer_tag, thumbnail_data)} | entries]
      else
        entries
      end

    with {:ok, entries} <- collect_ok(entries),
         {:ok, entries} <- add_pointer_entries(entries, ifd, location) do
      {:ok, %{entries: Enum.sort_by(entries, & &1.tag_id)}}
    end
  end

  defp add_pointer_entries(entries, ifd, location) do
    Map.fetch!(@child_ifds, location)
    |> Enum.reduce_while({:ok, entries}, fn child_key, {:ok, acc} ->
      case Map.get(ifd, child_key) do
        nil ->
          {:cont, {:ok, acc}}

        child_ifd ->
          with {:ok, child_ifd} <- normalize_ifd(child_ifd, child_key),
               {:ok, child_node} <- build_ifd_node(child_ifd, child_key) do
            entry = %{
              tag_id: Map.fetch!(@pointer_tag_ids, child_key),
              kind: :child,
              child: child_node,
              type_id: Map.fetch!(@tiff_type_ids, :unsigned_long),
              count: 1
            }

            {:cont, {:ok, [entry | acc]}}
          else
            error -> {:halt, error}
          end
      end
    end)
  end

  defp build_value_entry({tag_name, value}, location) do
    with {:ok, schema} <- fetch_tag_schema(tag_name, location),
         {:ok, {count, data}} <- encode_tiff_value(schema.type, value),
         :ok <- validate_count(tag_name, schema.count, count) do
      {:ok,
       %{tag_id: schema.id, kind: :value, type_id: Map.fetch!(@tiff_type_ids, schema.type), count: count, data: data}}
    else
      {:error, reason} -> {:error, "unsupported EXIF value for #{inspect(tag_name)}: #{reason}"}
    end
  end

  defp build_data_pointer_entry(tag_name, data) do
    %{
      tag_id: Map.fetch!(@thumbnail_offset_tag_ids, tag_name),
      kind: :data_pointer,
      type_id: Map.fetch!(@tiff_type_ids, :unsigned_long),
      count: 1,
      data: data
    }
  end

  defp collect_ok(results) do
    results
    |> Enum.reduce_while([], fn
      {:ok, value}, acc -> {:cont, [value | acc]}
      {:error, _} = error, _acc -> {:halt, error}
    end)
    |> case do
      {:error, _} = error -> error
      values -> {:ok, Enum.reverse(values)}
    end
  end

  defp fetch_tag_schema(tag_name, location) do
    case Map.fetch(@tag_schemas, tag_name) do
      {:ok, schema} ->
        if location in schema.locations,
          do: {:ok, schema},
          else: {:error, "EXIF tag #{inspect(tag_name)} is not valid in #{inspect(location)}"}

      :error ->
        {:error, "unsupported EXIF tag #{inspect(tag_name)}"}
    end
  end

  defp validate_count(_tag_name, :any, _count), do: :ok
  defp validate_count(_tag_name, count, count), do: :ok

  defp validate_count(tag_name, expected, actual) do
    {:error, "EXIF tag #{inspect(tag_name)} expects #{expected} value(s), got #{actual}"}
  end

  defp encode_tiff_value(:ascii_string, value) when is_binary(value), do: {:ok, {byte_size(value) + 1, value <> <<0>>}}
  defp encode_tiff_value(:ascii_string, value), do: {:error, "cannot encode #{inspect(value)} as :ascii_string"}

  defp encode_tiff_value(type, value) when type in [:undefined, :unsigned_byte, :signed_byte] and is_binary(value),
    do: {:ok, {byte_size(value), value}}

  defp encode_tiff_value(type, value) when type in [:undefined, :unsigned_byte, :signed_byte],
    do: encode_sequence(value, &encode_integer(&1, 8, type == :signed_byte))

  defp encode_tiff_value(type, value) when type in [:unsigned_short, :signed_short],
    do: encode_sequence(value, &encode_integer(&1, 16, type == :signed_short))

  defp encode_tiff_value(type, value) when type in [:unsigned_long, :signed_long],
    do: encode_sequence(value, &encode_integer(&1, 32, type == :signed_long))

  defp encode_tiff_value(type, value) when type in [:unsigned_rational, :signed_rational],
    do: encode_sequence(value, &encode_rational(&1, type == :signed_rational))

  defp encode_sequence(value, encoder) do
    values = List.wrap(value)

    with {:ok, parts} <- collect_ok(Enum.map(values, encoder)) do
      {:ok, {length(values), IO.iodata_to_binary(parts)}}
    end
  end

  defp encode_rational({numerator, denominator}, signed) do
    with {:ok, numerator} <- encode_integer(numerator, 32, signed),
         {:ok, denominator} <- encode_integer(denominator, 32, signed) do
      {:ok, [numerator, denominator]}
    end
  end

  defp encode_rational(other, _signed), do: {:error, "cannot encode #{inspect(other)} as a rational"}

  defp encode_integer(value, bits, signed) when is_integer(value) do
    {min, max} =
      if signed, do: {-Bitwise.bsl(1, bits - 1), Bitwise.bsl(1, bits - 1) - 1}, else: {0, Bitwise.bsl(1, bits) - 1}

    if value in min..max do
      {:ok, <<value::integer-size(bits)-little>>}
    else
      {:error,
       "integer #{inspect(value)} is out of range for #{bits}-bit #{if signed, do: "signed", else: "unsigned"} integer"}
    end
  end

  defp encode_integer(value, _bits, _signed) do
    {:error, "expected integer EXIF value, got: #{inspect(value)}"}
  end

  defp align_even(value) when rem(value, 2) == 0, do: value
  defp align_even(value), do: value + 1

  defp pad_to_even(data) do
    if rem(byte_size(data), 2) == 0, do: data, else: [data, <<0>>]
  end

  defp pad_to_four(data), do: data <> :binary.copy(<<0>>, 4 - byte_size(data))

  defp parse_ifd(data, endian, offset, location, budget) when offset > 0 do
    with <<_::binary-size(^offset), count::binary-size(2), rest::binary>> <- data,
         entries_size = :binary.decode_unsigned(count, endian) * 12,
         <<entries::binary-size(^entries_size), next_offset::binary-size(4), _::binary>> <- rest do
      # The first entry for a tag wins; repeats are skipped before their values are decoded.
      {tags, budget} =
        for <<entry::binary-size(12) <- entries>>, reduce: {%{}, budget} do
          {tags, budget} ->
            case parse_tag(entry, endian, data, location, tags, budget) do
              {{name, value}, budget} -> {Map.put(tags, name, value), budget}
              {nil, budget} -> {tags, budget}
            end
        end

      {:ok, tags, :binary.decode_unsigned(next_offset, endian), budget}
    else
      _ -> :error
    end
  end

  defp parse_ifd(_data, _endian, _offset, _location, _budget), do: :error

  # Returns the tag (or nil for tags that cannot be named, decoded or written back, so they are skipped)
  # and the remaining numeric value budget.
  defp parse_tag(entry, endian, data, location, seen_tags, budget) do
    <<tag_id::binary-size(2), data_format::binary-size(2), num_components::binary-size(4), data_value::binary-size(4)>> =
      entry

    tag_name = Map.get(@tag_names, {location, :binary.decode_unsigned(tag_id, endian)})
    format = Map.get(@tiff_types, :binary.decode_unsigned(data_format, endian))
    num_components = :binary.decode_unsigned(num_components, endian)

    with true <- tag_name != nil and not Map.has_key?(seen_tags, tag_name),
         {data_format, bytes_per_component} <- format,
         cost = if(data_format in [:ascii_string, :undefined], do: 0, else: num_components),
         true <- cost <= budget,
         {:ok, data_value} <- tag_data(data_value, num_components * bytes_per_component, endian, data) do
      value = decode_value(data_format, bytes_per_component, num_components, data_value, endian)
      budget = budget - cost

      cond do
        Map.has_key?(@pointer_tag_ids, tag_name) -> parse_child_ifd(data, endian, value, tag_name, budget)
        MapSet.member?(@thumbnail_related_tags, tag_name) -> {if(location == :ifd1, do: {tag_name, value}), budget}
        match?({:ok, _}, build_value_entry({tag_name, value}, location)) -> {{tag_name, value}, budget}
        true -> {nil, budget}
      end
    else
      _ -> {nil, budget}
    end
  end

  defp parse_child_ifd(data, endian, offset, child, budget) do
    with true <- is_integer(offset),
         {:ok, tags, _next_offset, budget} <- parse_ifd(data, endian, offset, child, budget) do
      {{child, tags}, budget}
    else
      _ -> {nil, budget}
    end
  end

  # The data is either the value itself if the size <= 4, or it is an offset to the value.
  defp tag_data(data_value, total_bytes_size, _endian, _data) when total_bytes_size <= 4,
    do: {:ok, binary_part(data_value, 0, total_bytes_size)}

  defp tag_data(data_value, total_bytes_size, endian, data) do
    value_offset = :binary.decode_unsigned(data_value, endian)

    case data do
      <<_::binary-size(^value_offset), value::binary-size(^total_bytes_size), _::binary>> -> {:ok, value}
      _ -> :error
    end
  end

  defp decode_value(:ascii_string, _bytes_per_component, _count, data_value, _endian),
    do: String.trim_trailing(data_value, "\0")

  defp decode_value(:undefined, _bytes_per_component, _count, data_value, _endian), do: data_value

  defp decode_value(data_format, bytes_per_component, count, data_value, endian) do
    decode =
      case data_format do
        :unsigned_rational -> &decode_rational(&1, false, endian)
        :signed_rational -> &decode_rational(&1, true, endian)
        type -> &decode_integer(&1, bytes_per_component, type in [:signed_byte, :signed_short, :signed_long], endian)
      end

    if count == 1 do
      decode.(data_value)
    else
      for <<chunk::binary-size(^bytes_per_component) <- data_value>>, do: decode.(chunk)
    end
  end

  defp decode_integer(buffer, num_bytes, signed, endian) do
    value = :binary.decode_unsigned(binary_part(buffer, 0, num_bytes), endian)
    range = Bitwise.bsl(1, num_bytes * 8)
    if signed and value >= div(range, 2), do: value - range, else: value
  end

  defp decode_rational(buffer, signed, endian) do
    <<numerator::binary-size(4), denominator::binary-size(4)>> = buffer
    {decode_integer(numerator, 4, signed, endian), decode_integer(denominator, 4, signed, endian)}
  end
end
