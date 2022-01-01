defmodule Imagex.Jxl do
  def transcode_from_jpeg(jpeg_bytes, options \\ []) do
    with {:ok, options} <- Keyword.validate(options, effort: 7) do
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

      Imagex.C.jxl_transcode_from_jpeg(jpeg_bytes, effort)
    else
      error -> error
    end
  end
end
