"""Post-process raw supersampled renders: downsample, bold ink silhouette, painterly grade.
Used by pack.py and for quick contact sheets:  python3 post.py contact <char> <out.png> [anim ...]"""
import sys, os, glob
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
INK = (22, 12, 18)


def process(path, ss=2, ink_px=2, ink=INK):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    # un-premultiply safety: transparent viewport gives straight alpha in Godot
    im = im.resize((w // ss, h // ss), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    alpha = a[..., 3] / 255.0
    # silhouette ink: dilate alpha
    al = Image.fromarray((alpha * 255).astype(np.uint8))
    dil = al.filter(ImageFilter.MaxFilter(ink_px * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
    d = np.asarray(dil).astype(np.float32) / 255.0
    out = np.zeros_like(a)
    # composite character over ink
    rgb = a[..., :3]
    out[..., 0] = rgb[..., 0] * alpha + ink[0] * (1 - alpha)
    out[..., 1] = rgb[..., 1] * alpha + ink[1] * (1 - alpha)
    out[..., 2] = rgb[..., 2] * alpha + ink[2] * (1 - alpha)
    out[..., 3] = np.maximum(alpha, d) * 255
    # where alpha is tiny, rgb must be ink
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def contact(char, dst, anims=None, scale=1.0, bg=(70, 62, 66)):
    base = os.path.join(ROOT, "out", char)
    anims = anims or sorted(os.listdir(base))
    rows = []
    for an in anims:
        files = sorted(glob.glob(os.path.join(base, an, os.environ.get("DIRGLOB", "*") + ".png")))
        if not files:
            continue
        ims = [process(f) for f in files]
        rows.append((an, ims))
    cw, chh = rows[0][1][0].size
    ncol = max(len(r[1]) for r in rows)
    ncol = min(ncol, 16)
    lines = []
    for an, ims in rows:
        for i in range(0, len(ims), ncol):
            lines.append(ims[i:i + ncol])
    W, H = int(cw * scale) * ncol, int(chh * scale) * len(lines)
    sheet = Image.new("RGBA", (W, H), bg + (255,))
    for r, line in enumerate(lines):
        for c, im in enumerate(line):
            if scale != 1.0:
                im = im.resize((int(cw * scale), int(chh * scale)), Image.LANCZOS)
            sheet.alpha_composite(im, (c * int(cw * scale), r * int(chh * scale)))
    sheet.convert("RGB").save(dst)
    print(dst, sheet.size)


if __name__ == "__main__":
    if sys.argv[1] == "contact":
        sc = float(os.environ.get("SCALE", "1"))
        contact(sys.argv[2], sys.argv[3], sys.argv[4:] or None, sc)
