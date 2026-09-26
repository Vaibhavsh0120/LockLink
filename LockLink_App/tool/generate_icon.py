"""Regenerate the LockLink padlock and adaptive foreground (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

size = 1024
scale = 4
s = size * scale
charcoal = (32, 32, 32, 255)
white = (250, 250, 250, 255)

mask = Image.new("L", (s, s), 0)
draw = ImageDraw.Draw(mask)

def box(coords):
    return tuple(int(v * scale) for v in coords)

# One strong padlock silhouette. The shackle remains distinct at launcher sizes;
# the keyhole is a true cutout so the adaptive foreground can use any background.
draw.rounded_rectangle(box((350, 224, 674, 608)), radius=162 * scale,
                       outline=255, width=64 * scale)
draw.rounded_rectangle(box((276, 432, 748, 800)), radius=84 * scale, fill=255)
draw.ellipse(box((468, 536, 556, 624)), fill=0)
draw.rounded_rectangle(box((491, 594, 533, 688)), radius=20 * scale, fill=0)

foreground = Image.new("RGBA", (s, s), white)
foreground.putalpha(mask)
image = Image.new("RGBA", (s, s), charcoal)
image.alpha_composite(foreground)

output = Path(__file__).resolve().parents[1] / "assets" / "icon"
output.mkdir(parents=True, exist_ok=True)
image.resize((size, size), Image.Resampling.LANCZOS).save(output / "locklink.png")
foreground.resize((size, size), Image.Resampling.LANCZOS).save(
    output / "locklink_foreground.png"
)
