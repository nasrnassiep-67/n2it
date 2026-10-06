#!/usr/bin/env python3
"""Generate every app icon from the N2IT "2" (branding/N-2-Icon.png, the same mark as the PBX favicon).
Run from the repo root: python3 tools/make-icons.py   (needs Pillow)"""
from pathlib import Path
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = Image.open(ROOT / "branding/N-2-Icon.png").convert("RGBA")
MARK = SRC.crop(SRC.getbbox())                      # the "2" without padding
WHITE = (255, 255, 255, 255)

def mark(height: int) -> Image.Image:
    """The "2" scaled to `height` px, lightly sharpened (the source is only ~315 px tall)."""
    w = round(MARK.width * height / MARK.height)
    im = MARK.resize((w, height), Image.LANCZOS)
    return im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2)) if height > MARK.height else im

def tile(size: int, fill: float, bg=WHITE) -> Image.Image:
    """Square icon: the "2" centred at `fill` of the height on `bg`."""
    out = Image.new("RGBA", (size, size), bg)
    m = mark(round(size * fill))
    out.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return out

def save(im: Image.Image, path: str, rgb: bool = False):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    (im.convert("RGB") if rgb else im).save(p, optimize=True)
    print("wrote", path, im.size)

# iOS: one opaque 1024 px icon (iOS rounds the corners itself).
save(tile(1024, 0.66), "N2IT/Assets.xcassets/AppIcon.appiconset/icon.png", rgb=True)

# Android: legacy launcher icons (48 dp), adaptive foreground (108 dp, mark inside the 66 dp safe zone),
# and the status-bar icon (24 dp, white silhouette of the "2" on transparent).
RES = "android/app/src/main/res"
for d, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    save(tile(round(48 * scale), 0.70), f"{RES}/mipmap-{d}/ic_launcher.png")
    fg = Image.new("RGBA", (round(108 * scale),) * 2, (0, 0, 0, 0))
    m = mark(round(108 * scale * 0.50))
    fg.alpha_composite(m, ((fg.width - m.width) // 2, (fg.height - m.height) // 2))
    save(fg, f"{RES}/mipmap-{d}/ic_launcher_foreground.png")
    s = round(24 * scale)
    sil = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    m = mark(round(s * 0.92))
    white = Image.new("RGBA", m.size, WHITE); white.putalpha(m.getchannel("A"))
    sil.alpha_composite(white, ((s - m.width) // 2, (s - m.height) // 2))
    save(sil, f"{RES}/drawable-{d}/ic_stat_n2it.png")

# Desktop (Electron): electron-builder turns build/icon.png (>= 512 px) into the Windows .ico and Linux icons.
save(tile(512, 0.70), "windows/build/icon.png")
save(tile(256, 0.70), "windows/src/assets/icon.png")
logo = Image.open(ROOT / "branding/n2it-logo.png").convert("RGBA")
save(logo.resize((300, round(logo.height * 300 / logo.width)), Image.LANCZOS), "windows/src/assets/logo.png")
