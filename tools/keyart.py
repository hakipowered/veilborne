"""Chroma-keys a painted prop / character on a plain #00FF00 background into a trimmed RGBA png.
   python3 tools/keyart.py <src.jpg> <dst.png> <max height px> [--nogreen]
Only green connected to the image border (plus strongly green pixels) is removed, so mossy or green
details inside the figure survive. Edges are despilled and the 1px fringe shaved."""
import sys
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage


def key(src, nogreen=False):
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = np.maximum(r, b)
    spill = g - mx
    hard = (spill > 70) & (g > 120)                       # surely background
    lab, _ = ndimage.label(hard)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]).tolist())) - {0}
    bg = np.isin(lab, list(border)) | ((spill > 130) & (g > 170))
    # soft edge: pixels next to the background fade by how green they are
    if nogreen:                                       # art with no green in it: drop any green haze
        bg = bg | (spill > 6)
    near = ndimage.binary_dilation(bg, iterations=3)
    soft = 1.0 - np.clip((spill - 30.0) / 60.0, 0.0, 1.0)
    alpha = np.where(bg, 0.0, np.where(near, soft, 1.0))
    g2 = np.where(near, np.minimum(g, mx + 6.0), g)
    out = np.dstack([r, g2, b, alpha * 255.0])
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    im.putalpha(im.getchannel("A").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6)))
    return im


def main():
    src, dst, h = sys.argv[1], sys.argv[2], int(sys.argv[3])
    im = key(src, "--nogreen" in sys.argv)
    bb = im.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
    im = im.crop((max(bb[0] - 3, 0), max(bb[1] - 3, 0), min(bb[2] + 3, im.width), min(bb[3] + 3, im.height)))
    if h > 0 and im.height > h:
        im = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
    im.save(dst, optimize=True)
    print(dst, im.size)


if __name__ == "__main__":
    main()
