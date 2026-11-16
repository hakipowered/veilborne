"""Pack rendered frames into trimmed atlas pages + metadata for entities/anim_sprite.gd.

python3 tools/anim/pack.py <char>
Reads tools/anim/chars.json and tools/anim/out/<char>/<anim>/d<dir>_<i>.png.
Writes art/anim/<char>/<char>_<page>.webp, art/anim/<char>/data.gd (runtime) and meta.json (human readable).
"""
import sys, os, json, glob, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from post import process

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))
PAGE_W = 2048
PAGE_H = 2048


def main(char):
    cfg = json.load(open(os.path.join(ROOT, "chars.json")))[char]
    ss = int(cfg.get("ss", 2))
    cell = int(cfg.get("cell", 256))
    elev = math.radians(float(cfg.get("elev", 40)))
    cam = float(cfg.get("cam_size", 2.6))
    cy = float(cfg.get("center_y", 0.85))
    pivot = (cell / 2.0, cell / 2.0 + cy * math.cos(elev) / cam * cell)
    out_scale = float(cfg.get("out_scale", 1.0))   # extra downscale of final frames
    ink = int(cfg.get("ink_px", 2))
    anims = cfg["anims"]
    frames = []   # (anim, dir, idx, img trimmed, ox, oy)
    for an, ad in anims.items():
        if ad.get("clip", "") == "" and "retarget" not in ad and "procedural" not in cfg:
            continue
        for d in range(5):
            fl = sorted(glob.glob(os.path.join(ROOT, "out", char, an, "d%d_*.png" % d)))
            if not fl:
                print("missing", an, d)
                continue
            for i, f in enumerate(fl):
                im = process(f, ss, ink)
                px, py = pivot
                if out_scale != 1.0:
                    im = im.resize((round(im.width * out_scale), round(im.height * out_scale)), Image.LANCZOS)
                    px, py = px * out_scale, py * out_scale
                bb = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
                if bb is None:
                    bb = (0, 0, 1, 1)
                bb = (max(bb[0] - 1, 0), max(bb[1] - 1, 0), min(bb[2] + 1, im.width), min(bb[3] + 1, im.height))
                t = im.crop(bb)
                frames.append([an, d, i, t, bb[0] - px, bb[1] - py])
    # reference height = the character's nominal standing height in px (world metres * px per metre),
    # so target_height_px in AnimSprite.setup() means "standing height on screen" for every anim.
    ppm = cell / cam * out_scale
    ref_h = float(cfg.get("height_m", 1.75)) * ppm * math.cos(elev) ** 0.0
    # shelf pack, tallest first
    order = sorted(range(len(frames)), key=lambda k: -frames[k][3].height)
    pages = []
    place = {}
    x = y = shelf_h = 0
    page = 0
    pages_used_h = [0]
    for k in order:
        im = frames[k][3]
        w, h = im.size
        if x + w > PAGE_W:
            x = 0
            y += shelf_h
            shelf_h = 0
        if y + h > PAGE_H:
            page += 1
            pages_used_h.append(0)
            x = y = shelf_h = 0
        place[k] = (page, x, y)
        x += w
        shelf_h = max(shelf_h, h)
        pages_used_h[page] = max(pages_used_h[page], y + h)
    imgs = [Image.new("RGBA", (PAGE_W, ((pages_used_h[p] + 3) // 4) * 4), (0, 0, 0, 0)) for p in range(page + 1)]
    for k, (p, px, py) in place.items():
        imgs[p].paste(frames[k][3], (px, py))
    dst = os.path.join(PROJ, "art", "anim", char)
    os.makedirs(dst, exist_ok=True)
    for old in glob.glob(os.path.join(dst, "%s_*.webp" % char)):
        os.remove(old)
    total = 0
    vram = 0
    for p, im in enumerate(imgs):
        # trim page width too
        bb = im.getbbox()
        if bb:
            im = im.crop((0, 0, min(PAGE_W, ((bb[2] + 3) // 4) * 4), im.height))
        fn = os.path.join(dst, "%s_%d.webp" % (char, p))
        im.save(fn, "WEBP", quality=int(cfg.get("webp_q", 90)), method=6, alpha_quality=100)
        imp = fn + ".import"
        if not os.path.exists(imp):
            # VRAM compressed (ETC2/ASTC on Android, S3TC/BPTC on desktop): ~4x less GPU memory than lossless
            open(imp, "w").write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                                 'compress/mode=2\ncompress/high_quality=false\nmipmaps/generate=false\n'
                                 'process/fix_alpha_border=true\nprocess/premult_alpha=false\ndetect_3d/compress_to=0\n')
        total += os.path.getsize(fn)
        vram += im.width * im.height * 4
    data = {"id": char, "ref_h": ref_h, "pages": len(imgs), "anims": {}}
    for an, ad in anims.items():
        if ad.get("clip", "") == "" and "retarget" not in ad and "procedural" not in cfg:
            continue
        dirs = []
        for d in range(5):
            fl = [k for k in range(len(frames)) if frames[k][0] == an and frames[k][1] == d]
            fl.sort(key=lambda k: frames[k][2])
            arr = []
            for k in fl:
                p, px, py = place[k]
                im = frames[k][3]
                arr.append([p, px, py, im.width, im.height, round(frames[k][4], 1), round(frames[k][5], 1)])
            dirs.append(arr)
        data["anims"][an] = {"fps": float(ad.get("fps", 12)), "loop": bool(ad.get("loop", False)),
                             "events": ad.get("events", {}), "dirs": dirs}
    json.dump(data, open(os.path.join(dst, "meta.json"), "w"))
    with open(os.path.join(dst, "data.gd"), "w") as f:
        f.write("# Generated by tools/anim/pack.py — do not edit.\nextends RefCounted\nconst DATA := ")
        f.write(json.dumps(data, separators=(",", ":")))
        f.write("\n")
    print(char, "frames", len(frames), "pages", len(imgs), "bytes", total, "vram MB (uncompressed) %.1f, ETC2 ~%.1f" % (vram / 1e6, vram / 4e6), "ref_h", ref_h)


if __name__ == "__main__":
    for c in sys.argv[1:]:
        main(c)
