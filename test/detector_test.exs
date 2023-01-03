defmodule DetectorTest do
  use ExUnit.Case
  doctest Imagex.Detect

  defp load_bytes(path) do
    {:ok, file} = File.open(path, [:read])
    IO.binread(file, 100)
  end

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
  end

  test "detect garbage" do
    assert Imagex.Detect.detect("some random string") == nil
  end
end
