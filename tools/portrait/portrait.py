"""Turns a screenshot of the scraper's `/sg portrait` window into a boss portrait texture.

    python tools/portrait/portrait.py <screenshot> <name> [--preview <png>]

The window draws the boss twice, on black and on white, each inside a magenta frame. The pair
gives the transparency back (alpha = 1 - (white - black)); the result is scaled to 128x64 and
written as Spyglass/assets/bosses/<name>.blp (or to <name> itself when it ends in .blp) in the
format of the client's own boss art: BLP2, uncompressed BGRA, 8-bit alpha, no mipmaps.
See README.md next to this file.
"""

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops

WIDTH, HEIGHT = 128, 64
ASSETS = Path(__file__).resolve().parents[2] / "Spyglass" / "assets" / "bosses"


def magenta_mask(shot: Image.Image) -> Image.Image:
    r, g, b = shot.split()
    high = lambda v: 255 if v > 200 else 0
    low = lambda v: 255 if v < 60 else 0
    return ImageChops.multiply(ImageChops.multiply(r.point(high), g.point(low)), b.point(high))


def find_frames(mask: Image.Image) -> list[tuple[int, int, int, int]]:
    """The areas inside the two magenta frames, left (black) first."""
    width, height = mask.size
    count = lambda box: mask.crop(box).histogram()[255]

    # The frames' top edge: the first row with long magenta runs, one run per frame.
    top = next((y for y in range(height) if count((0, y, width, y + 1)) > 400), None)
    if top is None:
        sys.exit("no magenta frames found; is this a screenshot of the /sg portrait window?")
    row = mask.crop((0, top, width, top + 1)).tobytes()
    runs, start = [], None
    for x in range(width + 1):
        on = x < width and row[x]
        if on and start is None:
            start = x
        elif not on and start is not None:
            if x - start > 200:
                runs.append((start, x))
            start = None
    if len(runs) != 2:
        sys.exit(f"expected two magenta frames side by side, found {len(runs)}")

    frames = []
    for x0, x1 in runs:
        # Down through the top edge (magenta rows), the inside and the bottom edge (magenta again).
        full = lambda y: count((x0, y, x1, y + 1)) > 0.9 * (x1 - x0)
        y = top
        for edge in (True, False, True):
            while y < height and full(y) == edge:
                y += 1
        y1 = y
        # Then inward from each side until the ring is left behind (checked on the middle half).
        w, h = x1 - x0, y1 - top
        has = lambda box: mask.crop(box).getbbox() is not None
        t, b, l, r = top, y1, x0, x1
        while has((x0 + w // 4, t, x1 - w // 4, t + 1)):
            t += 1
        while has((x0 + w // 4, b - 1, x1 - w // 4, b)):
            b -= 1
        while has((l, top + h // 4, l + 1, y1 - h // 4)):
            l += 1
        while has((r - 1, top + h // 4, r, y1 - h // 4)):
            r -= 1
        frames.append((l, t, r, b))
    return frames


def portrait(shot: Image.Image) -> Image.Image:
    """The 128x64 RGBA portrait from the black/white pair in the screenshot."""
    black_box, white_box = find_frames(magenta_mask(shot))
    w = min(black_box[2] - black_box[0], white_box[2] - white_box[0])
    h = min(black_box[3] - black_box[1], white_box[3] - white_box[1])
    # The largest 2:1 area, centered in what the frames enclose.
    cw, ch = (2 * h, h) if w >= 2 * h else (w, w // 2)
    dx, dy = (w - cw) // 2, (h - ch) // 2
    crop = lambda box: shot.crop((box[0] + dx, box[1] + dy, box[0] + dx + cw, box[1] + dy + ch)).tobytes()
    black, white = crop(black_box), crop(white_box)
    print(f"frames {black_box} and {white_box}, using {cw}x{ch}")

    # The shot on black is the color already multiplied by alpha: keep it premultiplied for the
    # downscale (no dark fringes), Pillow divides it out in the conversion to RGBA.
    premultiplied = bytearray()
    for i in range(0, len(black), 3):
        br, bg, bb = black[i : i + 3]
        wr, wg, wb = white[i : i + 3]
        a = max(0, min(255, round(255 - ((wr - br) + (wg - bg) + (wb - bb)) / 3)))
        premultiplied += bytes((min(br, a), min(bg, a), min(bb, a), a))
    big = Image.frombytes("RGBa", (cw, ch), bytes(premultiplied))
    return big.resize((WIDTH, HEIGHT), Image.LANCZOS).convert("RGBA")


def write_blp(image: Image.Image, path: Path) -> None:
    """BLP2, encoding 3 (uncompressed BGRA), 8-bit alpha, no mipmaps; the palette is unused."""
    data = image.tobytes("raw", "BGRA")
    header = struct.pack("<4sIBBBBII", b"BLP2", 1, 3, 8, 8, 0, image.width, image.height)
    offsets = struct.pack("<16I", 148 + 1024, *[0] * 15)
    sizes = struct.pack("<16I", len(data), *[0] * 15)
    path.write_bytes(header + offsets + sizes + bytes(1024) + data)


def main() -> None:
    parser = argparse.ArgumentParser(description="Screenshot of /sg portrait -> boss portrait .blp")
    parser.add_argument("screenshot", type=Path)
    parser.add_argument("name", help="file name in Spyglass/assets/bosses (e.g. magmatus), or a path ending in .blp")
    parser.add_argument("--preview", type=Path, help="also write a 4x PNG on grey, to check the result")
    args = parser.parse_args()

    image = portrait(Image.open(args.screenshot).convert("RGB"))
    out = Path(args.name) if args.name.endswith(".blp") else ASSETS / f"{args.name}.blp"
    write_blp(image, out)
    print(f"wrote {out}")
    if args.preview:
        grey = Image.new("RGBA", image.size, (60, 60, 60, 255))
        Image.alpha_composite(grey, image).convert("RGB").resize((WIDTH * 4, HEIGHT * 4), Image.NEAREST).save(args.preview)
        print(f"wrote {args.preview}")
    if out.parent == ASSETS:
        print(f'"portrait": "Interface\\\\AddOns\\\\Spyglass\\\\assets\\\\bosses\\\\{out.name}"')


if __name__ == "__main__":
    main()
