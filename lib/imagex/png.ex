defmodule Imagex.Png do
  @moduledoc false

  @spec metadata_from_texts(list({binary(), binary()}) | nil) :: map()
  def metadata_from_texts(nil), do: %{}

  def metadata_from_texts(png_texts) when is_list(png_texts) do
    %{
      png_chunks:
        Enum.map(png_texts, fn {keyword, text} ->
          %{keyword: keyword, text: text}
        end)
    }
  end

  @spec texts_from_metadata(map() | nil) :: {:ok, list({binary(), binary()}) | nil} | {:error, String.t()}
  def texts_from_metadata(nil), do: {:ok, nil}

  def texts_from_metadata(metadata) when is_map(metadata) do
    case Map.get(metadata, :png_chunks) do
      nil ->
        {:ok, nil}

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

  def texts_from_metadata(metadata),
    do: {:error, "image metadata must be a map or nil, got: #{inspect(metadata)}"}

  defp text_from_chunk(%{keyword: keyword, text: text} = chunk) when map_size(chunk) == 2 do
    with :ok <- validate_text_keyword(keyword),
         :ok <- validate_text_value(text) do
      {:ok, {keyword, text}}
    end
  end

  defp text_from_chunk(%{keyword: _keyword, text: _text} = chunk) do
    extra_keys = Map.keys(Map.drop(chunk, [:keyword, :text]))
    {:error, "unsupported PNG text metadata keys: #{inspect(extra_keys)}"}
  end

  defp text_from_chunk(chunk) do
    {:error, "PNG metadata entries must be maps with :keyword and :text, got: #{inspect(chunk)}"}
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
end
