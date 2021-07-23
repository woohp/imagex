# Imagex

Provides NIF wrappers for loading and saving common images (jpeg, png, and jpeg-xl for now).

## Usage

To load a jpeg image

```elixir
{:ok, jpeg_bytes} = File.read("test/lena.jpg")
{:ok, %Imagex.Image{} = image} = Imagex.jpeg_decompress(jpeg_bytes)
image.pixels  # bytes containing pixels
image.width  # 512
image.height  # 512
image.channels  # 3
```

To load any image

```elixir
{:ok, png_bytes} = File.read("test/lena.png")
{:ok, %Imagex.Image{} = image} = Imagex.decode(png_bytes)
```
