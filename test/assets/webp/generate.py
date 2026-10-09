"""Regenerate Pillow fixtures and decoded-pixel expectations; not needed by tests.
Run from the repository root with Python and Pillow installed.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent
XMP = b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><fixture>imagex-webp</fixture></x:xmpmeta>'
source = Image.open('test/assets/exif/exif-jpeg-thumbnail-sony-dsc-p150-inverted-colors.jpg')
exif = source.info['exif']
rgb = Image.new('RGB', (32, 24))
rgba = Image.new('RGBA', rgb.size)
for y in range(24):
    for x in range(32):
        color = (x * 7, y * 9, (x * 11 + y * 13) % 256)
        rgb.putpixel((x, y), color)
        rgba.putpixel((x, y), color + ((x * 17 + y * 19) % 256,))
rgb.save(ROOT / 'lossy-exif.webp', quality=85, exif=exif)
rgba.save(ROOT / 'lossless-xmp.webp', lossless=True, exact=True, xmp=XMP)
rgba.save(ROOT / 'lossy-alpha-exif-xmp.webp', quality=85, exif=exif, xmp=XMP)
expectations = {}
for path in sorted(ROOT.glob('*.webp')):
    image = Image.open(path)
    expectations[path.name] = {
        'width': image.width, 'height': image.height,
        'channels': len(image.getbands()),
        'sha256': hashlib.sha256(image.tobytes()).hexdigest(),
    }
(ROOT / 'pixels.json').write_text(json.dumps(expectations, indent=2) + '\n')
print('Pillow', __import__('PIL').__version__)
print('source EXIF:', len(exif), 'bytes')
