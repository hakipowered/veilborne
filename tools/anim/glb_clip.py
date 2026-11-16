"""Meshy rig jobs return one full GLB per clip (~6 MB: mesh + texture + anim). The skin's inverse bind matrices and
the animation live at the END of the binary chunk, so a clip only needs part 0 (JSON header) plus the last part(s).

  python3 glb_clip.py grab <dir> <dump...>    move job_part dumps (exact tool-result paths or their numeric ids) into <dir>/p<part>.json
                                              (never "newest": other agents share the tool-results folder)
  python3 glb_clip.py need <dir>              print which parts (besides 0) hold the skin + animation
  python3 glb_clip.py build <dir> <out.glb>   write an armature-only GLB (skeleton + skin + animation, no mesh)
  python3 glb_clip.py full <dir> <out.glb>    join every part into the original file (for the mesh)
"""
import sys, os, json, glob, base64, struct

PART = 1000000
D = "/root/.claude/projects/-home-claude/60ccb364-bc23-5aec-8751-13c38b9b3b3b/tool-results/"


def grab(dst, files):
    os.makedirs(dst, exist_ok=True)
    for f in files:
        if f.isdigit():
            f = D + "mcp-Whiteboard_Images-job_part-%s.txt" % f
        d = json.load(open(f))
        os.replace(f, os.path.join(dst, "p%d.json" % d["part"]))
        print("grabbed part", d["part"], "->", dst)


def parts(dirn):
    out = {}
    for f in glob.glob(os.path.join(dirn, "p*.json")):
        d = json.load(open(f))
        out[d["part"]] = base64.b64decode(d["data"])
    return out


def header(p0):
    jl, = struct.unpack("<I", p0[12:16])
    j = json.loads(p0[20:20 + jl])
    return j, 20 + jl + 8


def needed_views(j):
    acc = set()
    for a in j.get("animations", []):
        for s in a["samplers"]:
            acc.add(s["input"])
            acc.add(s["output"])
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            acc.add(s["inverseBindMatrices"])
    return acc


def need(dirn):
    ps = parts(dirn)
    j, bin0 = header(ps[0])
    acc = needed_views(j)
    want = set()
    for a in acc:
        bv = j["bufferViews"][j["accessors"][a]["bufferView"]]
        lo = bin0 + bv.get("byteOffset", 0)
        hi = lo + bv["byteLength"]
        for p in range(lo // PART, (hi - 1) // PART + 1):
            want.add(p)
    return sorted(want)


def build(dirn, out):
    ps = parts(dirn)
    j, bin0 = header(ps[0])
    miss = [p for p in need(dirn) if p not in ps]
    if miss:
        raise SystemExit("missing parts %s" % miss)

    def read(lo, n):
        b = bytearray()
        while n > 0:
            p = lo // PART
            off = lo - p * PART
            chunk = ps[p][off:off + n]
            if not chunk:
                raise SystemExit("short data at %d (part %d)" % (lo, p))
            b += chunk
            lo += len(chunk)
            n -= len(chunk)
        return bytes(b)

    acc_ids = sorted(needed_views(j))
    new_acc, new_bv, blob = [], [], bytearray()
    remap = {}
    for a in acc_ids:
        ac = dict(j["accessors"][a])
        bv = j["bufferViews"][ac["bufferView"]]
        data = read(bin0 + bv.get("byteOffset", 0), bv["byteLength"])
        while len(blob) % 4:
            blob += b"\0"
        nb = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        blob += data
        ac["bufferView"] = len(new_bv)
        new_bv.append(nb)
        remap[a] = len(new_acc)
        new_acc.append(ac)
    nodes = []
    for n in j["nodes"]:
        n = dict(n)
        n.pop("mesh", None)
        n.pop("skin", None)
        nodes.append(n)
    skins = []
    for s in j.get("skins", []):
        s = dict(s)
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = remap[s["inverseBindMatrices"]]
        skins.append(s)
    anims = []
    for a in j.get("animations", []):
        a = json.loads(json.dumps(a))
        for s in a["samplers"]:
            s["input"] = remap[s["input"]]
            s["output"] = remap[s["output"]]
        anims.append(a)
    while len(blob) % 4:
        blob += b"\0"
    nj = {"asset": j["asset"], "scene": j.get("scene", 0), "scenes": j["scenes"], "nodes": nodes, "skins": skins,
          "accessors": new_acc, "bufferViews": new_bv, "buffers": [{"byteLength": len(blob)}], "animations": anims}
    js = json.dumps(nj, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(out, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0") + blob)
    print(out, total, "bytes;", [a.get("name") for a in anims])


def full(dirn, out):
    ps = parts(dirn)
    keys = sorted(ps)
    assert keys == list(range(len(keys))), keys
    data = b"".join(ps[k] for k in keys)
    open(out, "wb").write(data)
    print(out, len(data))


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "grab":
        grab(sys.argv[2], sys.argv[3:])
    elif cmd == "need":
        print(" ".join(str(p) for p in need(sys.argv[2]) if p != 0))
    elif cmd == "build":
        build(sys.argv[2], sys.argv[3])
    elif cmd == "full":
        full(sys.argv[2], sys.argv[3])


def clip(char, idx, dumps):
    d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", "_dl", "%s_a%s" % (char, idx))
    grab(d, dumps)
    miss = [p for p in need(d) if p not in parts(d)]
    if miss:
        print("NEED parts", miss, "for", char, idx)
        return
    os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", char), exist_ok=True)
    build(d, os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", char, "a%s.glb" % idx))


if __name__ == "__main__" and sys.argv[1] == "clip":
    clip(sys.argv[2], sys.argv[3], sys.argv[4:])
