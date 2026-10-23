# Imagex

Load and save images, using libjpeg, libpng, libjxl, libtiff, libwebp, and poppler as backends.
Formats supported include: jpeg, png, bmp, jpeg-xl, ppm, tiff, pdf, webp (static images).


## Install

Please ensure that libjpeg, libpng, libjxl, libtiff, libwebp, and libpoppler are installed. WebP requires only libwebp, not libwebpmux.

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

Save an image (an `Imagex.Image` or a tensor) as a file

```elixir
image = Nx.tensor(...)
:ok = Imagex.save(image, "foo.png")  # the format is inferred from the file extension
:ok = Imagex.save(image, "foo", format: :jxl, lossless: true)
```

or save to memory

```elixir
{:ok, compressed} = Imagex.encode(image, :jpeg, quality: 90)
```

See `Imagex.encode/3` for each format's options and accepted pixel types. Animated WebP is rejected,
and ICC color management is not supported.

Grayscale images are `{height, width}` tensors; other images are `{height, width, channels}`.
Alpha, if present, is the last channel and is not premultiplied.
TIFF pages are always decoded as 8-bit RGBA.
Convert between grayscale, RGB and their alpha variants with `Imagex.convert/2`:

```elixir
gray = Imagex.convert(image, :L)
```

### Orientation

Phone photos are usually stored sideways with an EXIF orientation tag. Pass `orient: true` to get
upright pixels; the tag is then reset to 1 so re-encoding doesn't rotate the image again.

```elixir
{:ok, image} = Imagex.open("photo.jpg", orient: true)
```

JXL and TIFF pixels are always decoded upright.

### Untrusted input

Decoding refuses images larger than 178,956,970 pixels (Pillow's limit) before allocating any pixel
memory, since a small file can claim a huge image. Raise or lift the limit with `max_pixels:`
(`max_pixels: :infinity` disables it) on `decode/2`, `open/2`, `Imagex.Tiff.render_page/3` and
`Imagex.Pdf.render_page/3`.

### Errors

Invalid arguments (an unknown format or option, an out-of-range option value, a file extension with
no known format) raise `ArgumentError`. Failures that depend on the data, such as corrupt files,
pixels or metadata a format cannot store, or I/O errors, return `{:error, reason}` with a string reason.

## Metadata

`Imagex.decode/2` returns `%Imagex.Image{metadata: ...}` when metadata is present.

Supported metadata, read and written:

- JPEG: EXIF, XMP, JFIF density
- PNG: EXIF, XMP, text chunks
- JXL: EXIF, XMP, XML and JUMBF boxes
- WebP: EXIF, XMP

### Reading metadata

Metadata is parsed by default during `decode/2` and `open/2`. EXIF tags that Imagex does not know, or
cannot write back, are skipped, and byte-valued tags such as `exif_version` decode as binaries.

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

Metadata is written from `%Imagex.Image{metadata: ...}`. Decoded metadata can always be written
back: re-encoding to the same format keeps it, and anything the target format cannot store is dropped
(for example EXIF or XMP larger than a JPEG's 64 KB segment limit).

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

A `:metadata` option replaces the image's metadata, and `metadata: nil` writes none.
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

XMP uses the common `metadata.xmp` shape across formats:

```elixir
%{
  xmp: "<x:xmpmeta>...</x:xmpmeta>"
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

- `metadata.exif` is used for JPEG, PNG, JXL, and WebP writing.
- `metadata.xmp` is used for JPEG APP1 XMP, PNG XMP text chunks, JXL XML boxes, and WebP XMP chunks.
- `metadata.png_chunks` accepts `%{keyword, text}` and optional `:language_tag` / `:translated_keyword`.
- PNG text is always UTF-8. Latin-1 `tEXt` and `zTXt` chunks are converted on decode, and everything is written as `iTXt`.
- When decoding PNG and JXL, a single XMP chunk or XML box is returned as `metadata.xmp` rather than in `png_chunks` or `jxl_boxes`.
- `metadata.jxl_boxes` currently supports `:xml` and `:jumb`.
- `metadata.xmp` cannot be combined with JXL XML boxes in `metadata.jxl_boxes`, or with PNG XMP chunks in `metadata.png_chunks`.
- Unsupported or malformed metadata returns `{:error, reason}` during encode.

## Documents

PDF pages are rendered at a chosen resolution:

```elixir
{:ok, pdf_document} = Imagex.Pdf.load(File.read!("lena.pdf"))
for i <- 0..pdf_document.num_pages-1 do
  {:ok, image} = Imagex.Pdf.render_page(pdf_document, i, dpi: 150)
end
```

`Imagex.decode/2` decodes the first page of a TIFF (or the one given by `page:`). To render several
pages from one load:

```elixir
{:ok, tiff_document} = Imagex.Tiff.load(File.read!("lena.tiff"))
for i <- 0..tiff_document.num_pages-1 do
  {:ok, image} = Imagex.Tiff.render_page(tiff_document, i)
end
```

## JPEG XL transcoding

JPEGs can be converted to JXL losslessly, and back to the identical JPEG:

```elixir
{:ok, jxl_bytes} = Imagex.Jxl.transcode_from_jpeg(File.read!("photo.jpg"))
{:ok, jpeg_bytes} = Imagex.Jxl.transcode_to_jpeg(jxl_bytes)
```
