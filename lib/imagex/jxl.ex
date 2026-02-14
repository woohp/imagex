defmodule Imagex.Jxl do
  @moduledoc """
  JPEG XL (JXL) codec functions for transcoding and metadata extraction.
  """

  # Suppress dialyzer warnings for functions that call NIFs
  @dialyzer {:nowarn_function, transcode_from_jpeg: 2}
  @dialyzer {:nowarn_function, transcode_to_jpeg: 1}
  @dialyzer {:nowarn_function, read_metadata_from_jxl: 1}

  @typedoc """
  Effort level for JXL encoding.
  Can be 1-9 or named presets.
  """
  @type effort ::
          1..9
          | :lightning
          | :thunder
          | :falcon
          | :cheetah
          | :hare
          | :wombat
          | :squirrel
          | :kitten
          | :tortoise

  @spec transcode_from_jpeg(binary(), keyword()) ::
          {:ok, binary()} | {:error, String.t() | [atom()]}
  def transcode_from_jpeg(jpeg_bytes, options \\ []) when is_binary(jpeg_bytes) do
    with {:ok, options} <- Keyword.validate(options, effort: 7, store_jpeg_metadata: 1),
         effort <- parse_effort(Keyword.get(options, :effort)),
         store_jpeg_metadata <- parse_boolean(Keyword.get(options, :store_jpeg_metadata)) do
      Imagex.C.jxl_transcode_from_jpeg(jpeg_bytes, effort, store_jpeg_metadata)
    end
  end

  @spec transcode_to_jpeg(binary()) :: {:ok, binary()} | {:error, String.t()}
  def transcode_to_jpeg(jxl_bytes) when is_binary(jxl_bytes) do
    Imagex.C.jxl_transcode_to_jpeg(jxl_bytes)
  end

  @spec read_metadata_from_jxl(binary()) :: {:ok, map() | nil} | {:error, String.t()}
  def read_metadata_from_jxl(jxl_bytes) when is_binary(jxl_bytes) do
    case Imagex.C.jxl_read_exif(jxl_bytes) do
      nil ->
        {:ok, nil}

      {:ok, app1_data} when is_binary(app1_data) ->
        {:ok, Imagex.Exif.read_exif_from_tiff(app1_data)}

      {:error, _} = error ->
        error
    end
  end

  # Private helper functions

  defp parse_effort(value) when value in 1..9, do: value
  defp parse_effort(:lightning), do: 1
  defp parse_effort(:thunder), do: 2
  defp parse_effort(:falcon), do: 3
  defp parse_effort(:cheetah), do: 4
  defp parse_effort(:hare), do: 5
  defp parse_effort(:wombat), do: 6
  defp parse_effort(:squirrel), do: 7
  defp parse_effort(:kitten), do: 8
  defp parse_effort(:tortoise), do: 9

  defp parse_boolean(value) when value in [0, false], do: 0
  defp parse_boolean(value) when value in [1, true], do: 1
end
