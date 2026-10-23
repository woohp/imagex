defmodule DetectorTest do
  use ExUnit.Case

  defp load_bytes(path), do: path |> File.read!() |> binary_part(0, 100)

  test "detect jpeg" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena.jpg")) == :jpeg
  end

  test "detect png" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena.png")) == :png
  end

  test "detect jpeg-xl - container" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena.jxl")) == :jxl
  end

  test "detect jpeg-xl - naked codestream" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena-grayscale.jxl")) == :jxl
  end

  test "detect bmp" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena-rgb-pos-height.bmp")) == :bmp
  end

  test "detect ppm" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena.ppm")) == :ppm
  end

  test "detect tiff" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena.tiff")) == :tiff
  end

  test "detect pdf" do
    assert Imagex.Detect.detect(load_bytes("test/assets/lena.pdf")) == :pdf
    assert Imagex.Detect.detect("%PDF-2.0\r\n%\xE2\xE3") == :pdf
  end

  test "detect garbage" do
    assert Imagex.Detect.detect("some random string") == nil
  end

  test "decoding an unrecognized format returns an error" do
    assert Imagex.decode(<<0, 1, 2>>) == {:error, "unrecognized image format"}
  end
end
