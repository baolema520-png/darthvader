#!/usr/bin/env python3
"""Generate DMG background (English only)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 600
HEIGHT = 400
DIST = Path(__file__).resolve().parent.parent / "Distribution"
SUBTITLE = "Drag 520CAM to Applications"


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def draw_arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int], color: str) -> None:
    draw.line([start, end], fill=color, width=3)
    ex, ey = end
    draw.polygon([(ex, ey), (ex - 14, ey - 7), (ex - 14, ey + 7)], fill=color)


def make_background() -> Image.Image:
    img = Image.new("RGB", (WIDTH, HEIGHT), "#eef2f7")
    draw = ImageDraw.Draw(img)

    for y in range(HEIGHT):
        t = y / HEIGHT
        r = int(238 + (226 - 238) * t)
        g = int(242 + (232 - 242) * t)
        b = int(247 + (240 - 247) * t)
        draw.line([(0, y), (WIDTH, y)], fill=(r, g, b))

    title_font = load_font(34, bold=True)
    sub_font = load_font(15, bold=False)
    hint_font = load_font(12)

    title = "520CAM"
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_w = title_bbox[2] - title_bbox[0]
    draw.text(((WIDTH - title_w) // 2, 36), title, fill="#1e3a5f", font=title_font)

    sub_bbox = draw.textbbox((0, 0), SUBTITLE, font=sub_font)
    sub_w = sub_bbox[2] - sub_bbox[0]
    draw.text(((WIDTH - sub_w) // 2, 82), SUBTITLE, fill="#64748b", font=sub_font)

    draw_arrow(draw, (250, 318), (395, 318), "#3b82f6")
    draw.text((58, 352), "1. Start here", fill="#94a3b8", font=hint_font)

    return img


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    path = DIST / "dmg-background.png"
    make_background().save(path)
    print(f"Wrote {path}")


if __name__ == "__main__":
    main()
