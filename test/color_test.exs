defmodule Imagex.ColorTest do
  use ExUnit.Case
  alias Imagex.Image

  describe "convert/2" do
    test "RGB to L" do
      # Pure Red: 0.299 * 255 = 76.245 -> 76
      # Pure Green: 0.587 * 255 = 149.685 -> 150
      # Pure Blue: 0.114 * 255 = 29.07 -> 29
      tensor = Nx.tensor([[[255, 0, 0], [0, 255, 0]], [[0, 0, 255], [255, 255, 255]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :L)
      assert converted.tensor.shape == {2, 2, 1}
      assert Nx.to_flat_list(converted.tensor) == [76, 150, 29, 255]
    end

    test "L to RGB" do
      tensor = Nx.tensor([[[10], [20]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :RGB)
      assert converted.tensor.shape == {1, 2, 3}
      assert Nx.to_flat_list(converted.tensor) == [10, 10, 10, 20, 20, 20]
    end

    test "RGB to RGBA (add alpha)" do
      tensor = Nx.tensor([[[10, 20, 30]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :RGBA)
      assert converted.tensor.shape == {1, 1, 4}
      assert Nx.to_flat_list(converted.tensor) == [10, 20, 30, 255]
    end

    test "RGBA to RGB (merge alpha onto black)" do
      # 50% opacity red (128 on 255 scale)
      # 255 * 0.5 = 127.5 -> 128
      tensor = Nx.tensor([[[255, 0, 0, 128]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :RGB)
      assert converted.tensor.shape == {1, 1, 3}
      assert Nx.to_flat_list(converted.tensor) == [128, 0, 0]
    end

    test "RGBA to L" do
      # 50% opacity red -> merged to black -> [128, 0, 0]
      # [128, 0, 0] to L -> 128 * 0.299 = 38.272 -> 38
      tensor = Nx.tensor([[[255, 0, 0, 128]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :L)
      assert converted.tensor.shape == {1, 1, 1}
      assert Nx.to_flat_list(converted.tensor) == [38]
    end

    test "L to LA" do
      tensor = Nx.tensor([[[128]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :LA)
      assert converted.tensor.shape == {1, 1, 2}
      assert Nx.to_flat_list(converted.tensor) == [128, 255]
    end

    test "LA to L" do
      # 50% opacity gray (128) -> merged to black -> 128 * 0.5 = 64
      tensor = Nx.tensor([[[128, 128]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :L)
      assert converted.tensor.shape == {1, 1, 1}
      assert Nx.to_flat_list(converted.tensor) == [64]
    end

    test "RGBA to LA" do
      # Red (255, 0, 0) with 50% alpha (128)
      # RGB to L -> 76
      # Result -> (76, 128)
      tensor = Nx.tensor([[[255, 0, 0, 128]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :LA)
      assert converted.tensor.shape == {1, 1, 2}
      assert Nx.to_flat_list(converted.tensor) == [76, 128]
    end

    test "LA to RGBA" do
      # Gray (128) with 50% alpha (128)
      # L to RGB -> (128, 128, 128)
      # Result -> (128, 128, 128, 128)
      tensor = Nx.tensor([[[128, 128]]], type: :u8)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :RGBA)
      assert converted.tensor.shape == {1, 1, 4}
      assert Nx.to_flat_list(converted.tensor) == [128, 128, 128, 128]
    end

    test "different bit depths (u16)" do
      # max u16 is 65535
      tensor = Nx.tensor([[[65535, 0, 0]]], type: :u16)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :RGBA)
      assert converted.tensor.type == {:u, 16}
      assert Nx.to_flat_list(converted.tensor) == [65535, 0, 0, 65535]
    end

    test "different bit depths (f32)" do
      tensor = Nx.tensor([[[1.0, 0.0, 0.0]]], type: :f32)
      image = %Image{tensor: tensor}

      converted = Imagex.convert(image, :RGBA)
      assert converted.tensor.type == {:f, 32}
      assert Nx.to_flat_list(converted.tensor) == [1.0, 0.0, 0.0, 1.0]
    end
  end

  describe "Real Image Samples (Verified with Pillow)" do
    test "RGB -> L (lena.png)" do
      {:ok, image} = Imagex.open("test/assets/lena.png")
      gray = Imagex.convert(image, :L)
      # Pillow convert("L") (0,0) gives 114
      assert Nx.to_flat_list(Nx.slice(gray.tensor, [0, 0, 0], [1, 1, 1])) == [114]
    end

    test "RGBA -> RGB (lena-rgba.png, merge onto black)" do
      {:ok, image} = Imagex.open("test/assets/lena-rgba.png")
      rgb = Imagex.convert(image, :RGB)
      # Pillow manual merge onto black (0,0) gives [118, 77, 41]
      assert Nx.to_flat_list(Nx.slice(rgb.tensor, [0, 0, 0], [1, 1, 3])) == [118, 77, 41]
    end

    test "RGBA -> L (lena-rgba.png, merge onto black then to L)" do
      {:ok, image} = Imagex.open("test/assets/lena-rgba.png")
      gray = Imagex.convert(image, :L)
      # Pillow manual merge onto black then to L (0,0) gives 85
      assert Nx.to_flat_list(Nx.slice(gray.tensor, [0, 0, 0], [1, 1, 1])) == [85]
    end
  end
end
