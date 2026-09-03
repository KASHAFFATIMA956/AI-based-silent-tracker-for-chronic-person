"""
Generates the RozNoor launcher-icon assets: a stylized heartbeat/pulse line
on a rounded teal square, in the app's own brand palette (see
lib/core/theme.dart — RnColors.accent/accentDark/surface/accent400). No
design asset existed for this app yet, so this is a simple, clean geometric
icon produced programmatically (Python + Pillow) rather than invented by
hand — see context/decisions-log.md (2026-08-27) for the full rationale and
the leaf/care alternative concept that was considered and not chosen.

Run from mobile_app/:
    python3 scripts/gen_app_icon.py
Then regenerate every platform size with:
    dart run flutter_launcher_icons

Outputs (both consumed by the `flutter_launcher_icons` config in pubspec.yaml):
  assets/icon/app_icon.png             — 1024x1024 master (teal bg + glyph),
                                          used directly for iOS.
  assets/icon/app_icon_foreground.png  — transparent-bg glyph only, used as
                                          the Android adaptive-icon foreground
                                          (adaptive_icon_background in
                                          pubspec.yaml supplies the teal
                                          background layer separately).
"""
from PIL import Image, ImageDraw

SIZE = 1024
ACCENT = (15, 107, 104, 255)       # RnColors.accent  #0F6B68
ACCENT_DARK = (12, 91, 84, 255)    # RnColors.accentDark #0C5B54
SURFACE = (247, 248, 245, 255)     # RnColors.surface #F7F8F5
ACCENT_400 = (143, 192, 184, 255)  # RnColors.accent400 #8FC0B8


def pulse_points(size, margin_frac, cy):
    """The ECG-style pulse path, as fractions of the drawable width."""
    margin = int(size * margin_frac)
    w = size - 2 * margin
    fracs_y = [
        (0.00, cy), (0.16, cy),
        (0.22, cy + size * 0.03), (0.27, cy),
        (0.34, cy), (0.385, cy + size * 0.09),
        (0.44, cy - size * 0.22),
        (0.50, cy + size * 0.10),
        (0.555, cy),
        (0.63, cy), (0.70, cy - size * 0.06), (0.77, cy),
        (0.84, cy), (1.00, cy),
    ]
    return [(margin + f * w, y) for f, y in fracs_y], margin, w


def draw_pulse(draw, size, margin_frac, color, stroke_frac=0.045):
    cy = size // 2
    stroke = int(size * stroke_frac)
    pts, margin, w = pulse_points(size, margin_frac, cy)
    draw.line(pts, fill=color, width=stroke, joint="curve")
    r = stroke // 2
    for (x, y) in pts:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return margin, w, cy


def make_master(path):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    grad = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(SIZE):
        t = y / SIZE
        r = round(ACCENT[0] + (ACCENT_DARK[0] - ACCENT[0]) * t)
        g = round(ACCENT[1] + (ACCENT_DARK[1] - ACCENT[1]) * t)
        b = round(ACCENT[2] + (ACCENT_DARK[2] - ACCENT[2]) * t)
        gdraw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    mask = Image.new("L", (SIZE, SIZE), 0)
    mdraw = ImageDraw.Draw(mask)
    radius = int(SIZE * 0.225)
    mdraw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(img)
    margin, w, cy = draw_pulse(draw, SIZE, 0.14, SURFACE)
    dot_r = int(SIZE * 0.035)
    dot_x, dot_y = margin + 0.16 * w, cy
    draw.ellipse([dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r], fill=ACCENT_400)

    img.save(path)
    print(f"saved {path}")


def make_foreground(path):
    # Transparent background, glyph pulled further inward (0.22 margin vs
    # 0.14 on the master) since Android's adaptive-icon mask crops roughly
    # the outer third of a foreground layer.
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin, w, cy = draw_pulse(draw, SIZE, 0.22, SURFACE)
    dot_r = int(SIZE * 0.035)
    dot_x, dot_y = margin + 0.16 * w, cy
    draw.ellipse([dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r], fill=ACCENT_400)
    img.save(path)
    print(f"saved {path}")


if __name__ == "__main__":
    make_master("assets/icon/app_icon.png")
    make_foreground("assets/icon/app_icon_foreground.png")
