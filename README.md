# Imagex

Provides NIF wrappers for loading and saving common images (jpeg, png, and jpeg-xl for now).

## Usage

To load a jpeg image

```elixir
{:ok, jpeg_bytes} = File.read("test/lena.jpg")
{:ok, %Nx.Tensor{} = image} = Imagex.jpeg_decompress(jpeg_bytes)
```

To load any image

```elixir
{:ok, png_bytes} = File.read("lena.png")
{:ok, {:png, %Nx.Tensor{} = image}} = Imagex.decode(png_bytes)

# or directly from a file

{:ok, {:png, %Nx.Tensor{} = image}} = Imagex.open("lena.png")
```
