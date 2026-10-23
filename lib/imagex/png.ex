defmodule Imagex.Png do
  @moduledoc false

  @type png_text_t :: {binary(), binary(), binary(), binary()}
  @xmp_keyword "XML:com.adobe.xmp"

  # Compressed text may inflate to at most this much in total, so a small file cannot expand into huge metadata.
  @max_inflated_text 16 * 1024 * 1024

  # The NIF returns tEXt, zTXt and iTXt chunks unparsed, so `parse_metadata: false` skips this. A malformed chunk, or
  # one that could not be written back, is dropped, and so is all text if it inflates past the limit. A single XMP
  # chunk is surfaced as metadata.xmp instead of a png_chunks entry, so it is stored once.
  @spec metadata_from_texts([{binary(), binary()}]) :: map()
  def metadata_from_texts(text_chunks) do
    png_chunks =
      for {keyword, text, language_tag, translated_keyword} <- parse_texts(text_chunks, @max_inflated_text, []),
          chunk = %{keyword: keyword, text: text, language_tag: language_tag, translated_keyword: translated_keyword},
          chunk_error(chunk) == nil,
          do: chunk

    {xmp, png_chunks} =
      case Enum.split_with(png_chunks, &(&1.keyword == @xmp_keyword)) do
        {[%{text: xmp}], other_chunks} -> {xmp, other_chunks}
        _ -> {nil, png_chunks}
      end

    Map.reject(%{xmp: xmp, png_chunks: png_chunks}, fn {_key, value} -> value in [nil, []] end)
  end

  defp parse_texts([], _budget, texts), do: Enum.reverse(texts)

  defp parse_texts([chunk | chunks], budget, texts) do
    case parse_text(chunk, budget) do
      {:ok, text, budget} -> parse_texts(chunks, budget, [text | texts])
      :error -> parse_texts(chunks, budget, texts)
      :too_large -> []
    end
  end

  # Keywords, and tEXt and zTXt text, are Latin-1; iTXt text is UTF-8.
  defp parse_text({"tEXt", data}, budget) do
    case :binary.split(data, <<0>>) do
      [keyword, text] -> {:ok, {latin1_to_utf8(keyword), latin1_to_utf8(text), "", ""}, budget}
      _ -> :error
    end
  end

  defp parse_text({"zTXt", data}, budget) do
    with [keyword, <<0, compressed::binary>>] <- :binary.split(data, <<0>>),
         {:ok, text, budget} <- inflate(compressed, budget) do
      {:ok, {latin1_to_utf8(keyword), latin1_to_utf8(text), "", ""}, budget}
    else
      :too_large -> :too_large
      _ -> :error
    end
  end

  defp parse_text({"iTXt", data}, budget) do
    with [keyword, <<compressed, 0, rest::binary>>] when compressed in [0, 1] <- :binary.split(data, <<0>>),
         [language_tag, rest] <- :binary.split(rest, <<0>>),
         [translated_keyword, text] <- :binary.split(rest, <<0>>),
         {:ok, text, budget} <- if(compressed == 1, do: inflate(text, budget), else: {:ok, text, budget}) do
      {:ok, {latin1_to_utf8(keyword), text, language_tag, translated_keyword}, budget}
    else
      :too_large -> :too_large
      _ -> :error
    end
  end

  defp inflate(compressed, budget) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z)
      inflate(z, :zlib.safeInflate(z, compressed), budget, [])
    rescue
      # corrupt or truncated data
      ErlangError -> :error
    after
      :zlib.close(z)
    end
  end

  # Inflates in steps, so the output is never larger than the budget allows.
  defp inflate(z, {status, output}, budget, acc) do
    budget = budget - IO.iodata_length(output)

    cond do
      budget < 0 ->
        :too_large

      status == :continue ->
        inflate(z, :zlib.safeInflate(z, []), budget, [acc | output])

      true ->
        # safeInflate also finishes on a truncated stream; inflateEnd is what rejects it.
        :zlib.inflateEnd(z)
        {:ok, IO.iodata_to_binary([acc | output]), budget}
    end
  end

  defp latin1_to_utf8(latin1), do: :unicode.characters_to_binary(latin1, :latin1)

  @spec texts_from_metadata(list() | nil, binary() | nil) :: {:ok, list(png_text_t)} | {:error, String.t()}
  def texts_from_metadata(nil, xmp), do: texts_from_metadata([], xmp)

  def texts_from_metadata(png_chunks, xmp) when is_list(png_chunks) do
    with :ok <- Enum.find_value(png_chunks, :ok, &chunk_error/1) do
      png_texts = Enum.map(png_chunks, &text_from_chunk/1)

      cond do
        # PNG text is UTF-8 without NUL bytes, so other XMP is dropped, like XMP too large for a JPEG segment.
        is_nil(xmp) or String.contains?(xmp, <<0>>) or not String.valid?(xmp) ->
          {:ok, png_texts}

        Enum.any?(png_texts, &(elem(&1, 0) == @xmp_keyword)) ->
          {:error, "metadata.xmp cannot be combined with PNG XMP chunks in metadata.png_chunks"}

        true ->
          {:ok, [{@xmp_keyword, xmp, "", ""} | png_texts]}
      end
    end
  end

  def texts_from_metadata(png_chunks, _xmp),
    do: {:error, "PNG metadata must be a list, got: #{inspect(png_chunks)}"}

  defp text_from_chunk(chunk) do
    {:unicode.characters_to_binary(chunk.keyword, :utf8, :latin1), chunk.text, Map.get(chunk, :language_tag, ""),
     Map.get(chunk, :translated_keyword, "")}
  end

  # Returns nil for a valid chunk, or the error describing why it is invalid.
  defp chunk_error(%{keyword: keyword, text: text} = chunk) do
    extra_keys = Map.keys(Map.drop(chunk, [:keyword, :text, :language_tag, :translated_keyword]))

    cond do
      extra_keys != [] ->
        {:error, "unsupported PNG text metadata keys: #{inspect(extra_keys)}"}

      not is_binary(keyword) ->
        {:error, "PNG text keywords must be binaries, got: #{inspect(keyword)}"}

      not valid_keyword?(keyword) ->
        {:error,
         "PNG text keywords must be 1 to 79 printable Latin-1 characters, without leading, trailing or consecutive spaces, got: #{inspect(keyword)}"}

      true ->
        [
          {text, "text values"},
          {Map.get(chunk, :language_tag, ""), "language tags"},
          {Map.get(chunk, :translated_keyword, ""), "translated keywords"}
        ]
        |> Enum.find_value(fn {value, name} -> string_error(value, name) end)
    end
  end

  defp chunk_error(chunk) do
    {:error,
     "PNG metadata entries must be maps with :keyword and :text, optionally :language_tag and :translated_keyword, got: #{inspect(chunk)}"}
  end

  # The PNG spec's keyword rules, which libpng would otherwise enforce by rewriting the keyword.
  defp valid_keyword?(keyword) do
    case :unicode.characters_to_binary(keyword, :utf8, :latin1) do
      latin1 when is_binary(latin1) ->
        latin1 =~ ~r/\A[\x20-\x7e\xa1-\xff]{1,79}\z/ and not String.starts_with?(latin1, " ") and
          not String.ends_with?(latin1, " ") and not String.contains?(latin1, "  ")

      _not_latin1 ->
        false
    end
  end

  defp string_error(value, name) do
    cond do
      not is_binary(value) -> {:error, "PNG #{name} must be binaries, got: #{inspect(value)}"}
      not String.valid?(value) -> {:error, "PNG #{name} must be UTF-8"}
      String.contains?(value, <<0>>) -> {:error, "PNG #{name} must not contain NUL bytes"}
      true -> nil
    end
  end
end
