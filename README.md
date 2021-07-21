# Imagex

Provides NIF wrappers for loading and saving common images (jpeg and png for now).

## Usage

To load a jpeg image

```elixir
{:ok, jpeg_bytes} = File.read("test/lena.jpg")
{:ok, {pixels, width, height, channels}} = Imagex.jpeg_decompress(jpeg_bytes)
```

To load any image

```elixir
{:ok, png_bytes} = File.read("test/lena.png")
{:ok, {pixels, width, height, channels}} = Imagex.decode(png_bytes)
```
