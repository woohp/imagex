# WebP fixtures

## Upstream libwebp test vectors

Downloaded unchanged from the WebM project's libwebp-test-data repository:
https://chromium.googlesource.com/webm/libwebp-test-data/+/06ddd96e276c2c638a72d39d3c0f340afd61978c/

Pinned commit: `06ddd96e276c2c638a72d39d3c0f340afd61978c`.

| File | Container / coverage |
| --- | --- |
| `test.webp` | Lossy RGB (`VP8 `), plus unknown ancillary chunks |
| `lossless_color_transform.webp` | Lossless RGB (`VP8L`), color transform |
| `near_lossless_75.webp` | Near-lossless RGB, stored as `VP8L` |
| `lossless1.webp` | Lossless RGBA (`VP8L`) |
| `lossy_alpha1.webp` | Extended lossy RGBA (`VP8X`, compressed `ALPH`, `VP8 `) |
| `alpha_no_compression.webp` | Extended lossy RGBA, uncompressed alpha |
| `alpha_filter_3.webp` | Extended lossy RGBA, filtered/compressed alpha |

Individual files can be fetched with:

```sh
curl -fsSL 'https://chromium.googlesource.com/webm/libwebp-test-data/+/06ddd96e276c2c638a72d39d3c0f340afd61978c/test.webp?format=TEXT' | base64 --decode > test.webp
```

## Independently generated metadata fixtures

Generated using Pillow 12.3.0, not Imagex. `generate.py` reproduces these
files and the pixel expectations. It requires Pillow only for regeneration;
normal tests have no Python dependency or network access.

- `lossy-exif.webp`: lossy RGB, EXIF only.
- `lossless-xmp.webp`: lossless RGBA, XMP only.
- `lossy-alpha-exif-xmp.webp`: lossy RGBA, EXIF and XMP together.

Pixels are nonuniform color/alpha gradients. EXIF is copied unchanged from
our existing Sony DSC-P150 JPEG fixture, including its 7,935-byte JPEG
thumbnail. XMP is a small XML packet.

`pixels.json` records shape and SHA-256 of decoded RGB/RGBA bytes from Pillow
for every fixture. Tests compare Imagex output to these independently obtained
expectations, not to bytes produced by Imagex's encoder. Encoding tests also
check exact nonuniform lossless round trips and preservation of EXIF, thumbnail,
and XMP data.

The tiny animated fixture in the parent directory covers animation rejection. Grayscale and grayscale-alpha input expansion remains
covered by tensor tests; WebP decoding returns RGB/RGBA.
