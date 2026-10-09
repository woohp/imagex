defmodule Imagex.Webp do
  @moduledoc false
  import Bitwise

  def prepare_tensor(%Nx.Tensor{type: {:u, 8}, shape: shape} = tensor) do
    case shape do
      {h, w} ->
        prepare_tensor(Nx.reshape(tensor, {h, w, 1}))

      {_, _, 1} ->
        {:ok, Nx.concatenate([tensor, tensor, tensor], axis: 2)}

      {_, _, 2} ->
        gray = Nx.slice_along_axis(tensor, 0, 1, axis: 2)
        alpha = Nx.slice_along_axis(tensor, 1, 1, axis: 2)
        {:ok, Nx.concatenate([gray, gray, gray, alpha], axis: 2)}

      {_, _, c} when c in [3, 4] ->
        {:ok, tensor}

      _ ->
        {:error, "WebP requires 1–4 image channels"}
    end
  end

  def prepare_tensor(_), do: {:error, "WebP requires unsigned 8-bit pixels"}

  def validate_options(options) do
    cond do
      not is_number(options[:quality]) or options[:quality] < 0 or options[:quality] > 100 ->
        {:error, "WebP quality must be between 0 and 100"}

      not is_boolean(options[:lossless]) ->
        {:error, "WebP lossless must be a boolean"}

      not is_integer(options[:effort]) or options[:effort] not in 0..6 ->
        {:error, "WebP effort must be an integer between 0 and 6"}

      true ->
        :ok
    end
  end

  def put_metadata(bytes, _w, _h, _alpha, nil, nil), do: {:ok, bytes}

  def put_metadata(bytes, w, h, alpha, exif, xmp) do
    with {:ok, chunks} <- chunks(bytes) do
      flags =
        if(alpha, do: 0x10, else: 0) |||
          if(exif, do: 0x08, else: 0) ||| if xmp, do: 0x04, else: 0

      header = <<flags, 0::24, w - 1::little-24, h - 1::little-24>>
      image_chunks = Enum.reject(chunks, fn {tag, _} -> tag in ["VP8X", "EXIF", "XMP "] end)

      metadata =
        if(exif, do: [{"EXIF", exif}], else: []) ++
          if xmp, do: [{"XMP ", xmp}], else: []

      body = IO.iodata_to_binary(["WEBP" | Enum.map([{"VP8X", header} | image_chunks ++ metadata], &encode_chunk/1)])
      {:ok, <<"RIFF", byte_size(body)::little-32, body::binary>>}
    end
  end

  def read_metadata(_bytes, false), do: {:ok, nil}

  def read_metadata(bytes, true) do
    with {:ok, chunks} <- chunks(bytes) do
      metadata =
        Enum.reduce(chunks, %{}, fn
          {"EXIF", <<"Exif", 0, 0, tiff::binary>>}, acc ->
            Map.merge(acc, Imagex.Exif.read_exif_from_tiff(tiff))

          {"EXIF", tiff}, acc ->
            Map.merge(acc, Imagex.Exif.read_exif_from_tiff(tiff))

          {"XMP ", xmp}, acc ->
            Map.put(acc, :xmp, xmp)

          _, acc ->
            acc
        end)

      {:ok, if(metadata == %{}, do: nil, else: metadata)}
    end
  end

  defp chunks(<<"RIFF", size::little-32, "WEBP", rest::binary>>)
       when size >= 4 and size - 4 <= byte_size(rest),
       do: parse_chunks(binary_part(rest, 0, size - 4), [])

  defp chunks(_), do: {:error, "invalid WebP container"}

  defp parse_chunks(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_chunks(<<tag::binary-size(4), size::little-32, rest::binary>>, acc)
       when byte_size(rest) >= size + rem(size, 2) do
    case rest do
      <<data::binary-size(^size), 0::size(rem(^size, 2) * 8), tail::binary>> ->
        parse_chunks(tail, [{tag, data} | acc])

      _ ->
        {:error, "invalid WebP chunk padding"}
    end
  end

  defp parse_chunks(_, _), do: {:error, "invalid WebP chunk"}

  defp encode_chunk({tag, data}) do
    [tag, <<byte_size(data)::little-32>>, data, if(rem(byte_size(data), 2) == 1, do: <<0>>, else: <<>>)]
  end
end
