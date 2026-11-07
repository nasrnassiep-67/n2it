#!/usr/bin/env python3
"""Android icons for Novamo (the signal N, logo option B, 2026-11-06). Run from the repo root (needs Pillow)."""
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
TEAL, NAVY, WHITE = (22, 199, 183, 255), (10, 35, 66, 255), (255, 255, 255, 255)
SS = 4   # drawn large, then reduced, for smooth edges

def stroke(d, pts, w, col):
    d.line(pts, fill=col, width=round(w), joint="curve")
    for x, y in pts:
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=col)

def art(size, unit, ox, oy, col, bg=None):
    """The mark in the 100-unit drawing space: unit = px per unit, ox/oy = where (0,0) lands."""
    s = size * SS
    im = Image.new("RGBA", (s, s), bg or (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    p = lambda x, y: ((ox + x * unit) * SS, (oy + y * unit) * SS)
    stroke(d, [p(28, 74), p(28, 36), p(62, 74), p(62, 50)], 11 * unit * SS, col)
    for r in (11, 26):
        pts = [p(62 + r * math.sin(math.radians(a)), 48 - r * math.cos(math.radians(a))) for a in range(0, 91, 3)]
        stroke(d, pts, 6.5 * unit * SS, col)
    return im.resize((size, size), Image.LANCZOS)

for name, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    n = round(48 * scale)
    art(n, n / 100, 0, 0, NAVY, TEAL).save(RES / f"mipmap-{name}/ic_launcher.png", optimize=True)
    n = round(108 * scale)                         # adaptive foreground: the mark inside the 66 dp safe zone
    u = n * 0.72 / 100
    art(n, u, (n - 100 * u) / 2, (n - 100 * u) / 2, NAVY).save(RES / f"mipmap-{name}/ic_launcher_foreground.png", optimize=True)
    n = round(24 * scale)                          # status bar: white on transparent
    u = n * 1.25 / 100
    art(n, u, -15 * u, -13 * u, WHITE).save(RES / f"drawable-{name}/ic_stat_n2it.png", optimize=True)
print("done")
