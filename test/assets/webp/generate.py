"""Regenerate Pillow fixtures and decoded-pixel expectations; not needed by tests.

Run from the repository root with Python and Pillow installed.
"""

import hashlib
import json
from pathlib import Path

from PIL import Image, __version__ as pillow_version

ROOT = Path(__file__).parent
XMP = b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><fixture>imagex-webp</fixture></x:xmpmeta>'


def main():
    generate_metadata_fixtures()
    record_pixel_expectations()
    print("Pillow", pillow_version)


def generate_metadata_fixtures():
    # Reuse real EXIF, including its JPEG thumbnail, from the existing fixture.
    with Image.open(
        "test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg"
    ) as source:
        exif = source.info["exif"]

    # Nonuniform colors and alpha exercise more than a solid-color round trip.
    rgb = Image.new("RGB", (32, 24))
    rgba = Image.new("RGBA", rgb.size)
    for y in range(24):
        for x in range(32):
            color = (x * 7, y * 9, (x * 11 + y * 13) % 256)
            rgb.putpixel((x, y), color)
            rgba.putpixel((x, y), color + ((x * 17 + y * 19) % 256,))

    # Cover metadata separately and together, across lossy/lossless and alpha.
    rgb.save(ROOT / "lossy-exif.webp", quality=85, exif=exif)
    rgba.save(ROOT / "lossless-xmp.webp", lossless=True, exact=True, xmp=XMP)
    rgba.save(ROOT / "lossy-alpha-exif-xmp.webp", quality=85, exif=exif, xmp=XMP)
    print("source EXIF:", len(exif), "bytes")


def record_pixel_expectations():
    # Decode every fixture independently of Imagex, including upstream vectors.
    expectations = {}
    for path in sorted(ROOT.glob("*.webp")):
        with Image.open(path) as image:
            expectations[path.name] = {
                "width": image.width,
                "height": image.height,
                "channels": len(image.getbands()),
                "sha256": hashlib.sha256(image.tobytes()).hexdigest(),
            }

    (ROOT / "pixels.json").write_text(json.dumps(expectations, indent=2) + "\n")


if __name__ == "__main__":
    main()
