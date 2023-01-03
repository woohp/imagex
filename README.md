# Imagex

Load and save images, using libjpeg, libpng, libjxl, libtiff, and poppler as backends.
Formats supported include: jpeg, png, bmp, jpeg-xl, ppm, tiff, pdf.

Where possible, yielding NIFs are used so that it plays nice with BEAM VM's scheduler (WIP).


## Install

Please ensure that libjpeg, libpng, libjxl, libtiff, and libpoppler are installed.

```elixir
defp deps do
  [
    {:imagex, "~> 0.1.0", github: "woohp/imagex", branch: "master"}
  ]
end
```


## Usage

To load an image file (as an Nx.Tensor)

```elixir
{:ok, image} = Imagex.open("lena.jpg")
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
{:ok, pdf_document} = Imagex.decode(bytes, format: :pdf)
for i <- 0..pdf_document.num_pages-1 do
  {:ok, image} = Imagex.Pdf.render_page(pdf_document, i, dpi: 150)
end
```

and similarly, work with tiff files

```elixir
bytes = File.read!("lena.tiff")
{:ok, tiff_document} = Imagex.decode(bytes, format: :tiff)
for i <- 0..tiff_document.num_pages-1 do
  {:ok, image} = Imagex.Tiff.render_page(tiff_document, i)
end
```
