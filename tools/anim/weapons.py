"""Weapon-in-hand sprites: chroma-keys the painted weapon sources (tools/anim/weapon_src/<id>.jpg, plain #00FF00
background, weapon vertical with its tip/head up) into art/weapons/<id>.png and prints the grip pivot that
entities/anim_sprite.gd (WEAPON_ART) needs.   python3 tools/anim/weapons.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
# id: (output height px, grip point in the source image (x, y), halo colour)
W = {
    "spear": (520, (384, 905), (255, 140, 50)),
    "twin": (360, (385, 1035), (150, 220, 255)),
    "bow": (420, (458, 700), (255, 225, 130)),
    "scythe": (440, (280, 880), (200, 130, 255)),
    "shield": (256, None, (255, 205, 100)),   # source: the armory icon (art/ui/weapon_shield.png), held at its centre
}
HALO_PX = 7          # soft light around the weapon so it reads against the heroine's dark armour
HALO_ALPHA = 0.55


def halo(im, col):
    a = im.getchannel("A")
    pad = HALO_PX * 3
    big = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
    big.paste(im, (pad, pad))
    ab = big.getchannel("A").filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(HALO_PX))
    glow = Image.new("RGBA", big.size, col + (0,))
    glow.putalpha(ab.point(lambda v: int(v * HALO_ALPHA)))
    glow.alpha_composite(big)
    return glow, pad


def key(src):
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = np.maximum(r, b)
    spill = g - mx                                  # how "green screen" a pixel is
    alpha = 1.0 - np.clip((spill - 25.0) / 70.0, 0.0, 1.0)
    # despill: green never exceeds the other channels on the weapon
    g2 = np.minimum(g, mx + 8.0)
    out = np.dstack([r, g2, b, alpha * 255.0])
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    # shave the 1px fringe
    al = im.getchannel("A").filter(ImageFilter.MinFilter(3))
    im.putalpha(al)
    return im


def main():
    dst = os.path.join(PROJ, "art", "weapons")
    os.makedirs(dst, exist_ok=True)
    for wid, (h, grip, col) in W.items():
        if grip is None:
            im = Image.open(os.path.join(PROJ, "art", "ui", "weapon_%s.png" % wid)).convert("RGBA")
            grip = (im.width * 0.5, im.height * 0.5)
        else:
            im = key(os.path.join(ROOT, "weapon_src", wid + ".jpg"))
        bb = im.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
        bb = (max(bb[0] - 4, 0), max(bb[1] - 4, 0), min(bb[2] + 4, im.width), min(bb[3] + 4, im.height))
        im = im.crop(bb)
        s = h / im.height
        im = im.resize((round(im.width * s), h), Image.LANCZOS)
        gx, gy = (grip[0] - bb[0]) * s, (grip[1] - bb[1]) * s
        im, pad = halo(im, col)
        gx, gy = gx + pad, gy + pad
        im.save(os.path.join(dst, wid + ".png"), optimize=True)
        print('"%s": size %dx%d grip (%.1f, %.1f) art_h %d bytes %d' % (wid, im.width, im.height, gx, gy, h, os.path.getsize(os.path.join(dst, wid + ".png"))))


if __name__ == "__main__":
    main()
