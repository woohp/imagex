defmodule Imagex.ColorTest do
  use ExUnit.Case

  # Grayscale is 0.299R + 0.587G + 0.114B, and removing alpha composites onto black, both rounded to the nearest value.
  @cases [
    {[[[255, 0, 0], [0, 255, 0]], [[0, 0, 255], [255, 255, 255]]], :u8, :L, [[76, 150], [29, 255]]},
    {[[[10], [20]]], :u8, :RGB, [[[10, 10, 10], [20, 20, 20]]]},
    {[[10, 20]], :u8, :RGB, [[[10, 10, 10], [20, 20, 20]]]},
    {[[[10, 20, 30]]], :u8, :RGBA, [[[10, 20, 30, 255]]]},
    {[[[255, 0, 0, 128]]], :u8, :RGB, [[[128, 0, 0]]]},
    {[[[255, 0, 0, 128]]], :u8, :L, [[38]]},
    {[[[255, 0, 0, 128]]], :u8, :LA, [[[76, 128]]]},
    {[[[128]]], :u8, :LA, [[[128, 255]]]},
    {[[[128, 128]]], :u8, :L, [[64]]},
    {[[[128, 128]]], :u8, :RGBA, [[[128, 128, 128, 128]]]},
    {[[[1], [2]]], :u8, :L, [[1, 2]]},
    {[[[65535, 0, 0]]], :u16, :RGBA, [[[65535, 0, 0, 65535]]]},
    {[[[1.0, 0.0, 0.0]]], :f32, :RGBA, [[[1.0, 0.0, 0.0, 1.0]]]}
  ]

  test "convert" do
    for {input, type, colorspace, expected} <- @cases do
      assert Imagex.convert(Nx.tensor(input, type: type), colorspace) == Nx.tensor(expected, type: type)
    end
  end

  test "float conversion keeps fractional values" do
    [gray] = Nx.to_flat_list(Imagex.convert(Nx.tensor([[[1.0, 0.0, 0.0, 0.5]]], type: :f32), :L))
    assert_in_delta gray, 0.299 * 0.5, 1.0e-6
  end

  test "matches Pillow on real pixels" do
    {:ok, rgb} = Imagex.open("test/assets/lena.png")
    {:ok, rgba} = Imagex.open("test/assets/lena-rgba.png")
    rgb = Nx.slice(rgb.tensor, [0, 0, 0], [1, 1, 3])
    rgba = Nx.slice(rgba.tensor, [0, 0, 0], [1, 1, 4])

    # Pillow's convert("L"), and a manual merge onto black before convert("L") for RGBA.
    assert Nx.to_flat_list(Imagex.convert(rgb, :L)) == [114]
    assert Nx.to_flat_list(Imagex.convert(rgba, :RGB)) == [118, 77, 41]
    assert Nx.to_flat_list(Imagex.convert(rgba, :L)) == [85]
  end
end
