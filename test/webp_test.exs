defmodule Imagex.WebpTest do
  use ExUnit.Case, async: true
  alias Imagex.Image

  @fixtures "test/assets/webp/pixels.json" |> File.read!() |> JSON.decode!()
  @xmp ~s(<x:xmpmeta xmlns:x="adobe:ns:meta/"><fixture>imagex-webp</fixture></x:xmpmeta>)

  for {filename, expected} <- @fixtures do
    test "decodes independent fixture #{filename} with expected pixels" do
      bytes = File.read!("test/assets/webp/#{unquote(filename)}")
      assert Imagex.Detect.detect(bytes) == :webp
      assert {:ok, image} = Imagex.decode(bytes)
      assert image.tensor.type == {:u, 8}
      assert image.tensor.shape == unquote(Macro.escape({expected["height"], expected["width"], expected["channels"]}))
      hash = :crypto.hash(:sha256, Nx.to_binary(image.tensor)) |> Base.encode16(case: :lower)
      assert hash == unquote(expected["sha256"])
    end
  end

  test "reads independent EXIF with a JPEG thumbnail and optional XMP" do
    source = File.read!("test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg")
    assert {:ok, source_image} = Imagex.decode(source)

    for name <- ["lossy-exif.webp", "lossy-alpha-exif-xmp.webp"] do
      bytes = File.read!("test/assets/webp/#{name}")
      assert {:ok, image} = Imagex.decode(bytes)
      assert image.metadata.exif == source_image.metadata.exif
      assert byte_size(image.metadata.exif.ifd1.thumbnail_data) == 7935
      assert {:ok, %Image{}} = Imagex.decode(image.metadata.exif.ifd1.thumbnail_data)
      assert Map.get(image.metadata, :xmp) == if(name == "lossy-exif.webp", do: nil, else: @xmp)
      assert {:ok, skipped} = Imagex.decode(bytes, parse_metadata: false)
      assert skipped.metadata == nil
      assert Nx.to_binary(skipped.tensor) == Nx.to_binary(image.tensor)

      assert {:ok, encoded} = Imagex.encode(image, :webp, lossless: true)
      assert {:ok, decoded} = Imagex.decode(encoded)
      # Re-encoding relocates the thumbnail; its offset is not semantic metadata.
      {_, decoded_exif} = pop_in(decoded.metadata.exif, [:ifd1, :jpeg_interchange_format])
      {_, source_exif} = pop_in(image.metadata.exif, [:ifd1, :jpeg_interchange_format])
      assert decoded_exif == source_exif
      assert Map.get(decoded.metadata, :xmp) == Map.get(image.metadata, :xmp)
      assert Nx.to_binary(decoded.tensor) == Nx.to_binary(image.tensor)
    end
  end

  test "reads and preserves independent XMP without EXIF" do
    assert {:ok, image} = Imagex.open("test/assets/webp/lossless-xmp.webp")
    assert image.metadata == %{xmp: @xmp}
    assert {:ok, encoded} = Imagex.encode(image, :webp, lossless: true)
    assert {:ok, decoded} = Imagex.decode(encoded)
    assert decoded.metadata == image.metadata
    assert Nx.to_binary(decoded.tensor) == Nx.to_binary(image.tensor)
  end

  test "lossless encoding preserves nonuniform RGB and RGBA fixtures" do
    for filename <- ["lossless_color_transform.webp", "lossless1.webp", "lossy_alpha1.webp"] do
      assert {:ok, source} = Imagex.open("test/assets/webp/#{filename}")
      assert {:ok, encoded} = Imagex.encode(source, :webp, lossless: true)
      assert byte_size(encoded) < Nx.size(source.tensor)
      assert {:ok, decoded} = Imagex.decode(encoded)
      assert decoded.tensor.shape == source.tensor.shape
      assert Nx.to_binary(decoded.tensor) == Nx.to_binary(source.tensor)
    end
  end

  test "ignores bytes outside the declared RIFF extent without losing metadata" do
    bytes = File.read!("test/assets/webp/lossy-alpha-exif-xmp.webp")
    assert {:ok, expected} = Imagex.decode(bytes)
    assert {:ok, image} = Imagex.decode(bytes <> "trailing bytes")
    assert image.metadata == expected.metadata
    assert Nx.to_binary(image.tensor) == Nx.to_binary(expected.tensor)
  end

  test "rejects a truncated container rather than discarding malformed metadata" do
    bytes = File.read!("test/assets/webp/lossy-alpha-exif-xmp.webp")
    truncated = binary_part(bytes, 0, byte_size(bytes) - 1)
    assert {:error, _} = Imagex.decode(truncated)
  end

  test "lossless RGB and RGBA preserve pixels, including invisible colors" do
    for pixel <- [[20, 80, 140], [20, 80, 140, 0], [20, 80, 140, 128]] do
      tensor = Nx.broadcast(Nx.tensor(pixel, type: :u8), {3, 4, length(pixel)})
      assert {:ok, bytes} = Imagex.encode(tensor, :webp, lossless: true)
      assert {:ok, image} = Imagex.decode(bytes, format: :webp)
      assert Nx.to_binary(image.tensor) == Nx.to_binary(tensor)
    end
  end

  test "grayscale and grayscale-alpha expand to RGB and RGBA" do
    for {pixel, expected} <- [{[70], [70, 70, 70]}, {[70, 128], [70, 70, 70, 128]}] do
      tensor = Nx.tensor([[pixel]], type: :u8)
      assert {:ok, bytes} = Imagex.encode(tensor, :webp, lossless: true)
      assert {:ok, image} = Imagex.decode(bytes)
      assert Nx.to_flat_list(image.tensor) == expected
    end
  end

  test "lossy encoding retains dimensions and approximate colors" do
    tensor = Nx.broadcast(Nx.tensor([20, 80, 140], type: :u8), {16, 16, 3})
    assert {:ok, bytes} = Imagex.encode(tensor, :webp, quality: 90)
    assert {:ok, image} = Imagex.decode(bytes)
    assert image.tensor.shape == tensor.shape

    assert Enum.zip(Nx.to_flat_list(tensor), Nx.to_flat_list(image.tensor))
           |> Enum.all?(fn {a, b} -> abs(a - b) < 10 end)
  end

  test "EXIF and odd-sized XMP round trip with and without alpha" do
    metadata = %{exif: %{ifd0: %{orientation: 1}}, xmp: "odd"}

    for pixel <- [[1, 2, 3], [1, 2, 3, 128]] do
      tensor = Nx.tensor([[pixel]], type: :u8)
      assert {:ok, bytes} = Imagex.encode(%Image{tensor: tensor, metadata: metadata}, :webp, lossless: true)
      assert {:ok, image} = Imagex.decode(bytes)
      assert image.metadata.xmp == "odd"
      assert image.metadata.exif.ifd0.orientation == 1
      assert {:ok, %Image{metadata: nil}} = Imagex.decode(bytes, parse_metadata: false)
      assert Nx.to_binary(image.tensor) == Nx.to_binary(tensor)
    end
  end

  test "save and open use the WebP extension" do
    image = %Image{tensor: Nx.tensor([[[10, 20, 30]]], type: :u8)}
    path = Path.join(System.tmp_dir!(), "imagex-webp-#{System.unique_integer([:positive])}.webp")
    on_exit(fn -> File.rm!(path) end)
    assert :ok = Imagex.save(image, path, lossless: true)
    assert {:ok, decoded} = Imagex.open(path)
    assert Nx.to_binary(decoded.tensor) == Nx.to_binary(image.tensor)
  end

  test "rejects animation rather than dropping frames" do
    assert {:error, "animated WebP is not supported"} =
             Imagex.decode(File.read!("test/assets/animated.webp"))
  end

  test "rejects malformed data, unsupported pixels, and invalid options" do
    assert {:error, _} = Imagex.decode("bad", format: :webp)
    assert {:error, _} = Imagex.encode(Nx.tensor([[[1, 2, 3]]], type: :u16), :webp)
    tensor = Nx.tensor([[[1, 2, 3]]], type: :u8)
    assert {:error, _} = Imagex.encode(tensor, :webp, effort: 7)
    assert {:error, _} = Imagex.encode(tensor, :webp, quality: :bad)
    assert {:error, _} = Imagex.encode(tensor, :webp, metadata: %{xmp: 123})
  end
end
