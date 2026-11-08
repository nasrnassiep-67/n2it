#!/usr/bin/env python3
"""Desktop and Microsoft Store icons for Novamo (the signal N, 2026-11-06). Run from the repo root (needs Pillow)."""
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
TEAL, NAVY = (22, 199, 183, 255), (10, 35, 66, 255)
SS = 4

def stroke(d, pts, w, col):
    d.line(pts, fill=col, width=round(w), joint="curve")
    for x, y in pts:
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=col)

def tile(w, h=None, scale=1.0):
    """The mark on teal, centred; scale 1 fills the square as the icon does."""
    h = h or w
    W, H = w * SS, h * SS
    im = Image.new("RGBA", (W, H), TEAL)
    d = ImageDraw.Draw(im)
    u = min(W, H) / 100 * scale
    ox, oy = (W - 100 * u) / 2, (H - 100 * u) / 2
    p = lambda x, y: (ox + x * u, oy + y * u)
    stroke(d, [p(28, 74), p(28, 36), p(62, 74), p(62, 50)], 11 * u, NAVY)
    for r in (11, 26):
        stroke(d, [p(62 + r * math.sin(math.radians(a)), 48 - r * math.cos(math.radians(a))) for a in range(0, 91, 3)], 6.5 * u, NAVY)
    return im.resize((w, h), Image.LANCZOS)

def save(im, path):
    im.save(ROOT / path, optimize=True); print("wrote", path, im.size)

save(tile(512), "windows/build/icon.png")
save(tile(256), "windows/src/assets/icon.png")
A = "windows/build/appx"
save(tile(50), f"{A}/StoreLogo.png"); save(tile(44), f"{A}/Square44x44Logo.png"); save(tile(150, scale=.9), f"{A}/Square150x150Logo.png")
save(tile(310, scale=.9), f"{A}/LargeTile.png"); save(tile(71), f"{A}/SmallTile.png"); save(tile(310, 150, .9), f"{A}/Wide310x150Logo.png")
