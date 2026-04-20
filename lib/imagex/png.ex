defmodule Imagex.Png do
  @moduledoc false

  @type png_text_t :: {binary(), binary(), binary(), binary()}
  @xmp_keyword "XML:com.adobe.xmp"

  @spec metadata_from_texts(list(png_text_t) | nil) :: map()
  def metadata_from_texts(nil), do: %{}
  def metadata_from_texts([]), do: %{}

  def metadata_from_texts(png_texts) when is_list(png_texts) do
    png_chunks =
      Enum.map(png_texts, fn {keyword, text, language_tag, translated_keyword} ->
        %{
          keyword: keyword,
          text: text,
          language_tag: language_tag,
          translated_keyword: translated_keyword
        }
      end)

    xmp_metadata =
      case Enum.filter(png_chunks, &(&1.keyword == @xmp_keyword)) do
        [%{text: xmp}] -> %{xmp: xmp}
        _ -> %{}
      end

    %{png_chunks: png_chunks}
    |> Map.merge(xmp_metadata)
  end

  @spec texts_from_metadata(map() | nil) :: {:ok, list(png_text_t) | nil} | {:error, String.t()}
  def texts_from_metadata(nil), do: {:ok, nil}

  def texts_from_metadata(metadata) when is_map(metadata) do
    with {:ok, png_texts} <- png_texts_from_metadata(metadata),
         {:ok, xmp_text} <- xmp_text_from_metadata(metadata) do
      prepend_xmp_text(png_texts, xmp_text)
    end
  end

  def texts_from_metadata(metadata),
    do: {:error, "image metadata must be a map or nil, got: #{inspect(metadata)}"}

  defp png_texts_from_metadata(metadata) do
    case Map.get(metadata, :png_chunks) do
      nil ->
        {:ok, []}

      png_chunks when is_list(png_chunks) ->
        png_chunks
        |> Enum.map(&text_from_chunk/1)
        |> Enum.reduce_while({:ok, []}, fn
          {:ok, png_text}, {:ok, acc} -> {:cont, {:ok, [png_text | acc]}}
          {:error, _} = error, _acc -> {:halt, error}
        end)
        |> case do
          {:ok, png_texts} -> {:ok, Enum.reverse(png_texts)}
          error -> error
        end

      png_chunks ->
        {:error, "PNG metadata must be a list, got: #{inspect(png_chunks)}"}
    end
  end

  defp xmp_text_from_metadata(metadata) do
    case Map.get(metadata, :xmp) do
      nil ->
        {:ok, nil}

      xmp when is_binary(xmp) ->
        {:ok, xmp}

      xmp ->
        {:error, "XMP metadata must be a binary, got: #{inspect(xmp)}"}
    end
  end

  defp prepend_xmp_text(png_texts, nil) do
    if png_texts == [], do: {:ok, nil}, else: {:ok, png_texts}
  end

  defp prepend_xmp_text(png_texts, xmp) do
    if Enum.any?(png_texts, fn {keyword, _text, _language_tag, _translated_keyword} -> keyword == @xmp_keyword end) do
      {:error, "metadata.xmp cannot be combined with PNG XMP chunks in metadata.png_chunks"}
    else
      {:ok, [{@xmp_keyword, xmp, "", ""} | png_texts]}
    end
  end

  defp text_from_chunk(%{keyword: keyword, text: text} = chunk) do
    with :ok <- validate_chunk_keys(chunk),
         :ok <- validate_text_keyword(keyword),
         :ok <- validate_text_value(text),
         :ok <- validate_language_tag(Map.get(chunk, :language_tag, "")),
         :ok <- validate_translated_keyword(Map.get(chunk, :translated_keyword, "")) do
      {:ok, {keyword, text, Map.get(chunk, :language_tag, ""), Map.get(chunk, :translated_keyword, "")}}
    end
  end

  defp text_from_chunk(chunk) do
    {:error,
     "PNG metadata entries must be maps with :keyword and :text, optionally :language_tag and :translated_keyword, got: #{inspect(chunk)}"}
  end

  defp validate_chunk_keys(chunk) do
    extra_keys = Map.keys(Map.drop(chunk, [:keyword, :text, :language_tag, :translated_keyword]))

    if extra_keys == [] do
      :ok
    else
      {:error, "unsupported PNG text metadata keys: #{inspect(extra_keys)}"}
    end
  end

  defp validate_text_keyword(keyword) when is_binary(keyword) do
    cond do
      byte_size(keyword) == 0 -> {:error, "PNG text keywords must not be empty"}
      byte_size(keyword) > 79 -> {:error, "PNG text keywords must be at most 79 bytes"}
      String.contains?(keyword, <<0>>) -> {:error, "PNG text keywords must not contain NUL bytes"}
      true -> :ok
    end
  end

  defp validate_text_keyword(keyword),
    do: {:error, "PNG text keywords must be binaries, got: #{inspect(keyword)}"}

  defp validate_text_value(text) when is_binary(text) do
    if String.contains?(text, <<0>>) do
      {:error, "PNG text values must not contain NUL bytes"}
    else
      :ok
    end
  end

  defp validate_text_value(text),
    do: {:error, "PNG text values must be binaries, got: #{inspect(text)}"}

  defp validate_language_tag(language_tag) when is_binary(language_tag) do
    if String.contains?(language_tag, <<0>>) do
      {:error, "PNG language tags must not contain NUL bytes"}
    else
      :ok
    end
  end

  defp validate_language_tag(language_tag),
    do: {:error, "PNG language tags must be binaries, got: #{inspect(language_tag)}"}

  defp validate_translated_keyword(translated_keyword) when is_binary(translated_keyword) do
    if String.contains?(translated_keyword, <<0>>) do
      {:error, "PNG translated keywords must not contain NUL bytes"}
    else
      :ok
    end
  end

  defp validate_translated_keyword(translated_keyword),
    do: {:error, "PNG translated keywords must be binaries, got: #{inspect(translated_keyword)}"}
end
