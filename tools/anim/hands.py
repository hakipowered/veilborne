"""Weapons in hand: turns the per-frame hand-bone data that render.gd exports (cfg "export_hands") into per-weapon 2D
sprite transforms, so the equipped weapon's painted sprite (art/weapons/) follows the heroine's hand in every frame.

python3 tools/anim/hands.py <char> [--preview out.png [anim ...]]
Reads tools/anim/out/<char>/<anim>/d<dir>_<i>.json, writes art/anim/<char>/hands.gd:
  DATA = {"art": {weapon: [texture path per grip]},
          "anims": {anim: {weapon: [dir][frame] -> [[xx, xy, yx, yy, ox, oy, front], ...one per grip]}}}
Each grip is a Transform2D (columns x, y, origin) from the weapon image's pixels to the frame's pivot-relative pixels
(the same space as the atlas offsets in data.gd; AnimSprite applies its scale and mirroring); front = 1 when the
weapon is drawn over the body, 0 behind it.
"""
import sys, os, json, glob, math
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(ROOT, "..", ".."))

# weapon sprite (tools/anim/weapons.py prints these): (res path, image w, h, grip px (x, y), real length in metres of
# the painted weapon, its height in px without the halo)
ART = {
    "spear": ("res://art/weapons/spear.png", 142, 562, (70.8, 369.4), 1.85, 520),
    "twin": ("res://art/weapons/twin.png", 95, 402, (44.0, 306.5), 0.95, 360),
    "bow": ("res://art/weapons/bow.png", 144, 462, (94.7, 234.1), 1.3, 420),
    "scythe": ("res://art/weapons/scythe.png", 248, 482, (66.1, 299.0), 1.45, 440),
    "shield": ("res://art/weapons/shield.png", 294, 298, (147.0, 149.0), 0.62, 256),
}

# grips per weapon: bone, offset (bone space, m), rot (deg, Godot YXZ euler, applied in bone space), flip (mirror the
# art across its long axis), lock {anim: [rx, ry, rz(, "chest")]} = hold this orientation in character space (+Z forward, +Y up)
# instead of following the hand (a steady weapon while sprinting).
FIST = [90, 0, 0]          # weapon +Y runs through the closed fist (the old 3D spear prop's grip)
GRIPS = {
    "spear": [{"bone": "RightHand", "pos": [0, 0.08, 0], "rot": FIST,
               "lock": {"idle": [60, 0, 10, "chest"], "run": [110, 0, 10], "run_stop": [110, 0, 10]}}],
    "twin": [{"bone": "RightHand", "pos": [0, 0.08, 0], "rot": FIST, "lock": {"idle": [62, 0, 22, "chest"]}},
             {"bone": "LeftHand", "pos": [0, 0.08, 0], "rot": FIST, "flip": True, "lock": {"idle": [62, 0, -22, "chest"]}}],
    "bow": [{"bone": "RightHand", "pos": [0, 0.08, 0], "rot": FIST, "lock": {"idle": [60, 45, 0], "run": [60, 90, 0], "run_stop": [60, 90, 0]}}],
    "scythe": [{"bone": "RightHand", "pos": [0, 0.08, 0], "rot": FIST, "lock": {"idle": [55, -90, 10, "chest"], "run": [-30, -90, 14], "run_stop": [-30, -90, 14]}}],
    "shield": [{"bone": "LeftForeArm", "pos": [0, 0.16, 0], "rot": [0, 90, 0], "lock": {"idle": [20, -25, 0], "run": [20, -25, 0], "run_stop": [20, -25, 0]}}],
}
OVERRIDES = {}   # char -> {weapon: grips}
MIN_WIDTH = 0.55   # flat weapons seen edge-on keep at least this fraction of their width


def euler(r):
    x, y, z = (math.radians(v) for v in r)
    rx = np.array([[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]])
    ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    rz = np.array([[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]])
    return ry @ rx @ rz


def bone(d, name):
    v = d[name]
    o = np.array(v[0:3])
    b = np.array([v[3:6], v[6:9], v[9:12]]).T   # columns x, y, z
    return o, b


def grip_xf(d, g, art, an, ppm, pivot_y):
    path, w, h, (gx, gy), length, art_h = art
    o, b = bone(d, g["bone"])
    hold = o + b @ np.array(g.get("pos", [0, 0, 0]), float)
    lock = g.get("lock", {}).get(an)
    if lock is not None:
        # locks hold an orientation relative to the character root, or to the chest ("space": "chest") so a
        # stance's torso twist carries the weapon round with it
        _, rb = bone(d, "Spine02" if len(lock) > 3 and lock[3] == "chest" else "root")
        basis = rb @ euler(lock[:3])
    else:
        basis = b @ euler(g.get("rot", [0, 0, 0]))
    m = length / art_h
    fx = -1.0 if g.get("flip") else 1.0

    def scr(p):
        return np.array([p[0] * ppm, -(p[1] - pivot_y) * ppm])

    cu = np.array([basis[0, 0], -basis[1, 0]]) * m * fx * ppm
    cv = np.array([-basis[0, 1], basis[1, 1]]) * m * ppm
    nom = m * ppm
    lu = np.linalg.norm(cu)
    if lu < MIN_WIDTH * nom:
        perp = np.array([-cv[1], cv[0]])
        pn = np.linalg.norm(perp)
        if pn > 1e-6:
            perp = perp / pn
            if lu > 1e-6 and np.dot(perp, cu) < 0:
                perp = -perp
            cu = perp * MIN_WIDTH * nom
    hs = scr(hold)
    org = hs - cu * gx - cv * gy
    # in front of the body when the weapon's middle is nearer the camera than the chest
    mid = hold + basis @ np.array([0, (gy - h * 0.5) * m, 0])
    chest = d.get("Spine02", d.get("Spine"))[2]
    # a locked (carried) weapon is drawn over the body unless the hand is well behind it
    front = 1 if (hold[2] * 0.6 + mid[2] * 0.4) > chest - (0.25 if lock is not None else 0.1) else 0
    return [round(cu[0], 4), round(cu[1], 4), round(cv[0], 4), round(cv[1], 4), round(org[0], 1), round(org[1], 1), front]


def build(char):
    cfg = json.load(open(os.path.join(ROOT, "chars.json")))[char]
    cell = int(cfg.get("cell", 256))
    cam = float(cfg.get("cam_size", 2.6))
    out_scale = float(cfg.get("out_scale", 1.0))
    ppm = cell / cam * out_scale
    pivot_y = -float(cfg.get("center_y", 0.85)) * math.cos(math.radians(float(cfg.get("elev", 40))))
    grips = dict(GRIPS)
    grips.update(OVERRIDES.get(char, {}))
    data = {"art": {w: [ART[w][0]] * len(gl) for w, gl in grips.items()}, "anims": {}}
    for an in cfg["anims"]:
        per = {}
        for wid, gl in grips.items():
            dirs = []
            for dd in range(5):
                fl = sorted(glob.glob(os.path.join(ROOT, "out", char, an, "d%d_*.json" % dd)))
                frames = []
                for f in fl:
                    d = json.load(open(f))
                    frames.append([grip_xf(d, g, ART[wid], an, ppm, pivot_y) for g in gl])
                dirs.append(frames)
            per[wid] = dirs
        data["anims"][an] = per
    dst = os.path.join(PROJ, "art", "anim", char, "hands.gd")
    with open(dst, "w") as f:
        f.write("# Generated by tools/anim/hands.py — do not edit.\nextends RefCounted\nconst DATA := ")
        f.write(json.dumps(data, separators=(",", ":")))
        f.write("\n")
    print(char, "hands.gd", os.path.getsize(dst), "bytes")
    return data


def preview(char, data, dst, anims, weapons=None):
    """contact sheet: rows = weapon x anim, columns = dirs x sampled frames, weapon composited like the game does"""
    from PIL import Image
    sys.path.insert(0, ROOT)
    from post import process
    cfg = json.load(open(os.path.join(ROOT, "chars.json")))[char]
    cell = int(cfg.get("cell", 256))
    ss = int(cfg.get("ss", 2))
    cam = float(cfg.get("cam_size", 2.6))
    cy = float(cfg.get("center_y", 0.85))
    piv = (cell / 2.0, cell / 2.0 + cy * math.cos(math.radians(float(cfg.get("elev", 40)))) / cam * cell)
    weapons = weapons or list(data["art"].keys())
    S = float(os.environ.get("PS", "0.5"))
    crop = (int(cell * 0.16), int(cell * 0.12), int(cell * 0.9), int(cell * 0.94))
    cw, chh = int((crop[2] - crop[0]) * S), int((crop[3] - crop[1]) * S)
    tex = {w: Image.open(os.path.join(PROJ, data["art"][w][0][6:])).convert("RGBA") for w in weapons}
    rows = []
    for w in weapons:
        for an in anims:
            row = []
            for dd in range(5):
                fl = sorted(glob.glob(os.path.join(ROOT, "out", char, an, "d%d_*.png" % dd)))
                if not fl:
                    continue
                n = len(fl)
                picks = sorted(set([0, n // 3, (2 * n) // 3])) if n > 2 else [0]
                ev = cfg["anims"][an].get("events", {}).get("hit")
                if isinstance(ev, int) and ev < n:
                    picks = sorted(set([0, ev, min(n - 1, ev + 2)]))
                for i in picks:
                    body = process(fl[i], ss, int(cfg.get("ink_px", 2)))
                    canvas = Image.new("RGBA", body.size, (70, 62, 66, 255))
                    xfs = data["anims"][an][w][dd][i]
                    layers = []
                    for gi, xf in enumerate(xfs):
                        a, b, c, d_, ox, oy, front = xf
                        # image px (u,v) -> frame px: x = a*u + c*v + ox + piv.x ; inverse for PIL
                        M = np.array([[a, c], [b, d_]])
                        Mi = np.linalg.inv(M)
                        t = np.array([ox + piv[0], oy + piv[1]])
                        coeffs = (Mi[0, 0], Mi[0, 1], -(Mi[0] @ t), Mi[1, 0], Mi[1, 1], -(Mi[1] @ t))
                        wl = tex[w].transform(body.size, Image.AFFINE, coeffs, resample=Image.BILINEAR)
                        layers.append((front, wl))
                    for front, wl in layers:
                        if not front:
                            canvas.alpha_composite(wl)
                    canvas.alpha_composite(body)
                    for front, wl in layers:
                        if front:
                            canvas.alpha_composite(wl)
                    row.append(canvas.crop(crop).resize((cw, chh)))
            rows.append(row)
    ncol = max(len(r) for r in rows)
    sheet = Image.new("RGB", (cw * ncol, chh * len(rows)), (40, 36, 40))
    for r, row in enumerate(rows):
        for c, im in enumerate(row):
            sheet.paste(im.convert("RGB"), (c * cw, r * chh))
    sheet.save(dst)
    print(dst, sheet.size)


if __name__ == "__main__":
    ch = sys.argv[1]
    dat = build(ch)
    if "--preview" in sys.argv:
        k = sys.argv.index("--preview")
        rest = sys.argv[k + 2:]
        ws = [x[2:] for x in rest if x.startswith("w:")]
        ans = [x for x in rest if not x.startswith("w:")] or ["idle"]
        preview(ch, dat, sys.argv[k + 1], ans, ws or None)
