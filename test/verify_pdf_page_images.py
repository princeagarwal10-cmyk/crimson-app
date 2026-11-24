"""Check the real Windows PDF embeds the shared renderer's complete pages."""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader

directory = Path(sys.argv[1])
reader = PdfReader(directory / 'desktop-parity.pdf')
expected_paths = sorted(directory.glob('mobile-page_page_*.png'))
assert len(reader.pages) == len(expected_paths) == 2, 'Unexpected page count'
checks = []
for index, (page, reference) in enumerate(zip(reader.pages, expected_paths), 1):
    expected = Image.open(reference).convert('RGB')
    embedded = max(page.images, key=lambda item: item.image.width * item.image.height)
    actual = embedded.image.convert('RGB')
    assert actual.size == expected.size, 'PDF image was resized or clipped'
    difference = ImageChops.difference(expected, actual)
    maximum = max(channel[1] for channel in difference.getextrema())
    average = sum(ImageStat.Stat(difference).mean) / 3
    assert maximum <= 1, f'Page {index}: PDF differs from shared page renderer'
    checks.append({'page': index, 'image_size': actual.size,
                   'max_channel_difference': maximum, 'mean_difference': average,
                   'page_size_points': [float(page.mediabox.width), float(page.mediabox.height)]})
print(json.dumps(checks, indent=2))
