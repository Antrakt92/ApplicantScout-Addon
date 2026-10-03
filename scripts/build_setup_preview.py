"""Convert the public overlay example to a square, uncompressed WoW texture.

Run with the Companion Python environment, which already provides Pillow.
"""

from __future__ import annotations

import argparse
from io import BytesIO
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "media/setup-preview.tga"


def preview_bytes() -> bytes:
    with Image.open(ROOT / "docs/visual/applicantscout-overlay-alpha.png") as source:
        # The full example remains visible; padding makes both dimensions powers of two.
        resized = source.convert("RGBA").resize((512, 412), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.paste(resized, (0, 0))
    output = BytesIO()
    canvas.save(output, format="TGA")
    return output.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = preview_bytes()
    if args.check:
        if not TARGET.is_file() or TARGET.read_bytes() != expected:
            raise SystemExit("Setup preview is stale; run scripts/build_setup_preview.py")
        print("Setup preview matches the public overlay example.")
    else:
        TARGET.write_bytes(expected)
        print("Created media/setup-preview.tga")


if __name__ == "__main__":
    main()
