defmodule Imagex.Jxl do
  def transcode_jpeg(jpeg_bytes, options \\ []) do
    effort =
      case Keyword.get(options, :effort, 7) do
        value when value in 3..9 -> value
        :falcon -> 3
        :cheetah -> 4
        :hare -> 5
        :wombat -> 6
        :squirrel -> 7
        :kitten -> 8
        :tortoise -> 9
      end

    Imagex.C.jxl_transcode_jpeg_impl(jpeg_bytes, effort)
  end
end
