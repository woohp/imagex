defmodule Imagex.Detect do
  def detect(<<0xFFD8::size(16), _rest::binary>>), do: :jpeg

  def detect(<<0x89, "PNG\r\n", 0x1A, 0x0A, _rest::binary>>), do: :png

  def detect(<<0xFF, 0x0A, _rest::binary>>), do: :jxl

  def detect(<<0x00, 0x00, 0x00, 0x0C, "JXL ", 0x0D, 0x0A, 0x87, 0x0A, _rest::binary>>), do: :jxl

  def detect(<<"BM", _rest::binary>>), do: :bmp

  def detect(<<"P", n::size(8), "\n", _rest::binary>>) when n == ?5 or n == ?6, do: :ppm

  def detect(<<"II", 0x2A00::size(16), _rest::binary>>), do: :tiff

  def detect(<<"MM", 0x002A::size(16), _rest::binary>>), do: :tiff

  def detect(<<"%PDF-1.", n::size(8), "\n%", _rest::binary>>) when n in ?0..?9, do: :pdf

  # we don't recognize anything else at this time
  def detect(_), do: nil
end
