defmodule DetectorTest do
  use ExUnit.Case

  test "detect" do
    for {path, format} <- [
          {"lena.jpg", :jpeg},
          {"lena.png", :png},
          {"lena.jxl", :jxl},
          {"lena-grayscale.jxl", :jxl},
          {"lena-rgb-pos-height.bmp", :bmp},
          {"lena.ppm", :ppm},
          {"lena.tiff", :tiff},
          {"lena.pdf", :pdf}
        ] do
      bytes = "test/assets/#{path}" |> File.read!() |> binary_part(0, 100)
      assert Imagex.Detect.detect(bytes) == format, path
    end

    assert Imagex.Detect.detect("%PDF-2.0\r\n%\xE2\xE3") == :pdf
    assert Imagex.Detect.detect("some random string") == nil
  end
end
