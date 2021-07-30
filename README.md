# Imagex

Provides NIF wrappers for loading and saving common images (jpeg, png, jpeg-xl, and ppm for now).

## Usage

To load an image file (as an Nx.Tensor)

```elixir
{:ok, %Nx.Tensor{} = image} = Imagex.open("lena.jpg")
```

or load from memory

```elixir
bytes = File.read!("test/lena.jpg")
{:ok, image} = Imagex.decode(bytes)
```

Decode as a specific format

```elixir
bytes = File.read!("lena.png")
{:ok, image} = Imagex.decode(bytes, format: :png)

# or explicitly try multiple formats
{:ok, image} = Imagex.decode(bytes, format: [:png, :ppm])
```

Save an image as a file

```elixir
image = Nx.tensor(...)
Imagex.save(image, "foo.png")  # the format is inferred from the file extension
```

or save to memory

```elixir
compressed = Imagex.encode(image, :jpeg)
```

To work with pdf files

```elixir
bytes = File.read!("lena.pdf")
{:ok, pdf_document} = Imagex.decode(bytes, format: pdf)
for i <- 0..pdf_document.num_pages-1 do
  {:ok, image} = Imagex.Pdf.render_page(pdf_document, i, dpi: 150)
end
```
