defmodule Imagex.Png do
  @moduledoc false

  @type png_text_t :: {binary(), binary(), binary(), binary()}
  @xmp_keyword "XML:com.adobe.xmp"

  # A single XMP chunk is surfaced as metadata.xmp instead of a png_chunks entry, so it is stored once.
  @spec metadata_from_texts(list(png_text_t)) :: map()
  def metadata_from_texts(png_texts) do
    {xmp, png_texts} =
      case Enum.split_with(png_texts, &(elem(&1, 0) == @xmp_keyword)) do
        {[{_keyword, xmp, _language_tag, _translated_keyword}], other_texts} -> {xmp, other_texts}
        _ -> {nil, png_texts}
      end

    png_chunks =
      Enum.map(png_texts, fn {keyword, text, language_tag, translated_keyword} ->
        %{keyword: keyword, text: text, language_tag: language_tag, translated_keyword: translated_keyword}
      end)

    Map.reject(%{xmp: xmp, png_chunks: png_chunks}, fn {_key, value} -> value in [nil, []] end)
  end

  @spec texts_from_metadata(list() | nil, binary() | nil) :: {:ok, list(png_text_t)} | {:error, String.t()}
  def texts_from_metadata(nil, xmp), do: texts_from_metadata([], xmp)

  def texts_from_metadata(png_chunks, xmp) when is_list(png_chunks) do
    with :ok <- Enum.find_value(png_chunks, :ok, &chunk_error/1) do
      png_texts = Enum.map(png_chunks, &text_from_chunk/1)

      cond do
        is_nil(xmp) ->
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
    {chunk.keyword, chunk.text, Map.get(chunk, :language_tag, ""), Map.get(chunk, :translated_keyword, "")}
  end

  # Returns nil for a valid chunk, or the error describing why it is invalid.
  defp chunk_error(%{keyword: keyword, text: text} = chunk) do
    extra_keys = Map.keys(Map.drop(chunk, [:keyword, :text, :language_tag, :translated_keyword]))

    cond do
      extra_keys != [] ->
        {:error, "unsupported PNG text metadata keys: #{inspect(extra_keys)}"}

      not is_binary(keyword) ->
        {:error, "PNG text keywords must be binaries, got: #{inspect(keyword)}"}

      byte_size(keyword) == 0 ->
        {:error, "PNG text keywords must not be empty"}

      byte_size(keyword) > 79 ->
        {:error, "PNG text keywords must be at most 79 bytes"}

      true ->
        [
          {keyword, "text keywords"},
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

  defp string_error(value, name) do
    cond do
      not is_binary(value) -> {:error, "PNG #{name} must be binaries, got: #{inspect(value)}"}
      String.contains?(value, <<0>>) -> {:error, "PNG #{name} must not contain NUL bytes"}
      true -> nil
    end
  end
end
