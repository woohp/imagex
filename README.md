# Imagex

Load and save images, using libjpeg, libpng, libjxl, libtiff, and poppler as backends.
Formats supported include: jpeg, png, bmp, jpeg-xl, ppm, tiff, pdf.

Where possible, yielding NIFs are used so that it plays nice with BEAM VM's scheduler (WIP).


## Install

Please ensure that libjpeg, libpng, libjxl, libtiff, and libpoppler are installed.

```elixir
defp deps do
  [
    {:imagex, "~> 0.2.0", github: "woohp/imagex", branch: "master"}
  ]
end
```


## Usage

To load an image file (as an Imagex.Image struct)

```elixir
{:ok, image} = Imagex.open("lena.jpg")
image.tensor  # gets the Nx.Tensor
image.metadata  # gets the metadata, such as Exif data, or nil if there isn't any
```

or load from memory

```elixir
bytes = File.read!("lena.jpg")
{:ok, image} = Imagex.decode(bytes)
```

Decode as a specific format

```elixir
bytes = File.read!("lena.png")
{:ok, image} = Imagex.decode(bytes, format: :png)
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

## Metadata

`Imagex.decode/2` returns `%Imagex.Image{metadata: ...}` when metadata is present.

Supported metadata today:

- JPEG: EXIF read/write
- PNG: EXIF read, text chunk read/write
- JXL: EXIF read/write, XML and JUMBF box read/write

### Reading metadata

Metadata is parsed by default during `decode/2` and `open/2`.

```elixir
{:ok, image} = Imagex.open("lena.jpg")

image.metadata
#=> %{exif: %{ifd0: %{orientation: 1, ...}}}
```

You can skip metadata parsing with `parse_metadata: false`.

```elixir
{:ok, image} = Imagex.decode(File.read!("lena.jxl"), format: :jxl, parse_metadata: false)
image.metadata
#=> nil
```

### Writing metadata

Metadata is written from `%Imagex.Image{metadata: ...}`.

```elixir
image = %Imagex.Image{
  tensor: Nx.broadcast(Nx.tensor([0, 0, 0], type: {:u, 8}), {16, 16, 3}),
  metadata: %{
    exif: %{
      ifd0: %{
        orientation: 1,
        x_resolution: {72, 1},
        y_resolution: {72, 1},
        resolution_unit: 2,
        exif: %{
          pixel_x_dimension: 16,
          pixel_y_dimension: 16,
          color_space: 1
        }
      }
    }
  }
}

{:ok, jpeg_bytes} = Imagex.encode(image, :jpeg)
{:ok, jxl_bytes} = Imagex.encode(image, :jxl, lossless: true)
```

You can also pass metadata directly when encoding a tensor:

```elixir
tensor = Nx.broadcast(Nx.tensor([0, 0, 0], type: {:u, 8}), {16, 16, 3})

{:ok, png_bytes} =
  Imagex.encode(tensor, :png,
    metadata: %{
      png_chunks: [
        %{keyword: "Author", text: "Imagex"},
        %{
          keyword: "Comment",
          text: "Hello from Imagex",
          language_tag: "en",
          translated_keyword: "Comment"
        }
      ]
    }
  )
```

### Metadata shapes

EXIF uses the common `metadata.exif` shape across formats:

```elixir
%{
  exif: %{
    ifd0: %{
      orientation: 1,
      x_resolution: {72, 1},
      y_resolution: {72, 1},
      resolution_unit: 2
    }
  }
}
```

PNG text metadata uses `metadata.png_chunks`:

```elixir
%{
  png_chunks: [
    %{keyword: "Author", text: "Imagex"},
    %{
      keyword: "Comment",
      text: "Hello from Imagex",
      language_tag: "en",
      translated_keyword: "Comment"
    }
  ]
}
```

JXL container metadata uses `metadata.jxl_boxes` with atom box types:

```elixir
%{
  jxl_boxes: [
    %{type: :xml, contents: "<x:xmpmeta>...</x:xmpmeta>"},
    %{type: :jumb, contents: <<1, 2, 3>>}
  ]
}
```

Notes:

- `metadata.exif` is used for JPEG and JXL writing.
- `metadata.png_chunks` accepts `%{keyword, text}` and optional `:language_tag` / `:translated_keyword`.
- PNG text metadata is normalized on decode and written as `iTXt` chunks.
- `metadata.jxl_boxes` currently supports `:xml` and `:jumb`.
- Unsupported or malformed metadata returns `{:error, reason}` during encode.

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
