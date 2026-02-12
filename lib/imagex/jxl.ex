defmodule Imagex.Jxl do
  @dialyzer {:nowarn_function, transcode_from_jpeg: 1}
  @dialyzer {:nowarn_function, transcode_from_jpeg: 2}
  @dialyzer {:nowarn_function, transcode_to_jpeg: 1}
  @dialyzer {:nowarn_function, read_metadata_from_jxl: 1}

  @spec transcode_from_jpeg(binary(), keyword()) :: binary() | {:error, String.t()}
  def transcode_from_jpeg(jpeg_bytes, options \\ []) do
    with {:ok, options} <- Keyword.validate(options, effort: 7, store_jpeg_metadata: 1) do
      effort =
        case Keyword.get(options, :effort) do
          value when value in 1..9 -> value
          :lightning -> 1
          :thunder -> 2
          :falcon -> 3
          :cheetah -> 4
          :hare -> 5
          :wombat -> 6
          :squirrel -> 7
          :kitten -> 8
          :tortoise -> 9
        end

      store_jpeg_metadata =
        case Keyword.get(options, :store_jpeg_metadata) do
          0 -> 0
          false -> 0
          1 -> 1
          true -> 1
        end

      Imagex.C.jxl_transcode_from_jpeg(jpeg_bytes, effort, store_jpeg_metadata)
    else
      error -> error
    end
  end

  @spec transcode_to_jpeg(binary()) :: binary()
  def transcode_to_jpeg(jxl_bytes) do
    Imagex.C.jxl_transcode_to_jpeg(jxl_bytes)
  end

  @spec read_metadata_from_jxl(binary()) :: map() | nil | {:error, String.t()}
  def read_metadata_from_jxl(jxl_bytes) do
    with {:ok, app1_data} <- Imagex.C.jxl_read_exif(jxl_bytes) do
      Imagex.Exif.read_exif_from_tiff(app1_data)
    else
      {:error, _} = error -> error
    end
  end
end
