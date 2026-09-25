"""Regenerate the simple LockLink launcher artwork (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

size = 1024
scale = 4
s = size * scale
charcoal = (32, 32, 32, 255)
white = (250, 250, 250, 255)

image = Image.new("RGBA", (s, s), charcoal)
draw = ImageDraw.Draw(image)

def box(coords):
    return tuple(int(v * scale) for v in coords)

# A single door silhouette with an opening keyhole is readable at small sizes.
draw.rounded_rectangle(box((306, 180, 718, 842)), radius=90 * scale,
                       outline=white, width=48 * scale)
draw.line(box((410, 180, 410, 842)), fill=white, width=45 * scale)
draw.ellipse(box((546, 465, 622, 541)), fill=white)
draw.rounded_rectangle(box((568, 518, 600, 603)), radius=15 * scale,
                       fill=white)

output = Path(__file__).resolve().parents[1] / "assets" / "icon"
output.mkdir(parents=True, exist_ok=True)
image.resize((size, size), Image.Resampling.LANCZOS).save(output / "locklink.png")
