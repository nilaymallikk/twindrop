#!/usr/bin/env python3
"""WCAG contrast check for the TwinDrop colour tokens (docs/13 §7, DES-006).

Every text/background pair the UI can produce is listed explicitly, so a new
token cannot slip in unchecked. Run:

    python3 tool/contrast_check.py design/tokens.json
"""
from __future__ import annotations

import json
import sys


def srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    raw = hex_color.lstrip("#")
    if len(raw) == 8:  # #RRGGBBAA — the alpha does not affect luminance
        raw = raw[:6]
    r, g, b = (int(raw[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (
        0.2126 * srgb_to_linear(r)
        + 0.7152 * srgb_to_linear(g)
        + 0.0722 * srgb_to_linear(b)
    )


def contrast(fg: str, bg: str) -> float:
    a, b = luminance(fg), luminance(bg)
    lighter, darker = max(a, b), min(a, b)
    return (lighter + 0.05) / (darker + 0.05)


# (foreground, background, minimum ratio, what it is)
PAIRS = [
    ("text", "bg", 4.5, "body text on the page"),
    ("text", "surface", 4.5, "body text on a panel"),
    ("text", "raised", 4.5, "body text on a raised control"),
    ("textSecondary", "bg", 4.5, "secondary text on the page"),
    ("textSecondary", "surface", 4.5, "secondary text on a panel"),
    ("muted", "bg", 4.5, "meta text on the page"),
    ("muted", "surface", 4.5, "meta text on a panel"),
    ("onPaper", "paper", 4.5, "text on a paper bubble"),
    ("onAccent", "accent", 4.5, "text on the accent fill"),
    ("ok", "bg", 4.5, "success text on the page"),
    ("warn", "bg", 4.5, "warning text on the page"),
    ("error", "bg", 4.5, "error text on the page"),
    ("accent", "bg", 4.5, "accent text on the page"),
]


def main(path: str) -> int:
    with open(path, encoding="utf-8") as handle:
        tokens = json.load(handle)

    failures = 0
    for theme in ("dark", "light"):
        palette = tokens["color"][theme]
        print(f"=== {theme} ===")
        for fg, bg, minimum, label in PAIRS:
            ratio = contrast(palette[fg], palette[bg])
            ok = ratio >= minimum
            if not ok:
                failures += 1
            print(
                f"  {'ok  ' if ok else 'FAIL'} {ratio:5.2f}:1  (min {minimum})  "
                f"{fg} on {bg} — {label}"
            )
    print()
    if failures:
        print(f"RESULT: {failures} pair(s) below WCAG AA")
        return 1
    print("RESULT: all text/background pairs meet WCAG AA (4.5:1)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "design/tokens.json"))
