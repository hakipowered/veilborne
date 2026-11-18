#!/usr/bin/env python3
"""Adds the VeilRestart plugin to an exported (unsigned) Godot 4.3 APK.

  patch_apk.py in.apk out.apk

* adds tools/android/classes2.dex (built by build_dex.sh)
* registers it in the binary AndroidManifest.xml with
  <meta-data android:name="org.godotengine.plugin.v2.VeilRestart"
             android:value="com.veilborne.VeilRestart"/>
  (a copy of the existing org.godotengine.editor.version meta-data element)
Every other zip entry is copied byte for byte with its original compression.
Sign (and zipalign) afterwards, as tools/release.sh does.
"""
import os, struct, sys, zipfile

PLUGIN_KEY = "org.godotengine.plugin.v2.VeilRestart"
PLUGIN_CLASS = "com.veilborne.VeilRestart"
START_TAG, END_TAG, STRINGS = 0x0102, 0x0103, 0x0001


def read_pool(d, o):
    _t, hs, size, count, styles, flags, sstart, _sty = struct.unpack_from("<HHIIIIII", d, o)
    if styles or flags & 0x100:
        raise SystemExit("unexpected string pool format (styles or UTF-8)")
    offs = struct.unpack_from("<%dI" % count, d, o + hs)
    out = []
    for so in offs:
        p = o + sstart + so
        n = struct.unpack_from("<H", d, p)[0]
        out.append(d[p + 2:p + 2 + 2 * n].decode("utf-16-le"))
    return out, size


def build_pool(strings):
    data, offs = bytearray(), []
    for s in strings:
        offs.append(len(data))
        data += struct.pack("<H", len(s)) + s.encode("utf-16-le") + b"\0\0"
    while len(data) % 4:
        data += b"\0"
    hs = 28
    sstart = hs + 4 * len(strings)
    body = struct.pack("<%dI" % len(strings), *offs) + bytes(data)
    return struct.pack("<HHIIIIII", STRINGS, hs, hs + len(body), len(strings), 0, 0, sstart, 0) + body


def patch_manifest(d):
    strings, pool_size = read_pool(d, 8)
    if PLUGIN_KEY in strings:
        return d  # already patched
    idx_key, idx_cls = len(strings), len(strings) + 1
    rest = d[8 + pool_size:]
    # Find the editor.version meta-data element (start + end tag) in the node stream.
    o, found = 0, None
    while o < len(rest):
        t, _hs, sz = struct.unpack_from("<HHI", rest, o)
        if t == START_TAG:
            name = struct.unpack_from("<I", rest, o + 20)[0]
            astart, asize, acount = struct.unpack_from("<HHH", rest, o + 24)
            if strings[name] == "meta-data":
                attrs = [(o + 16 + astart + i * asize) for i in range(acount)]
                vals = {strings[struct.unpack_from("<I", rest, a + 4)[0]]: a for a in attrs}
                if "name" in vals and "value" in vals:
                    raw = struct.unpack_from("<I", rest, vals["name"] + 8)[0]
                    if raw != 0xFFFFFFFF and strings[raw] == "org.godotengine.editor.version":
                        end = o + sz
                        et, _ehs, esz = struct.unpack_from("<HHI", rest, end)
                        assert et == END_TAG
                        found = (o, sz, end, esz, vals["name"] - o, vals["value"] - o)
                        break
        o += sz
    if not found:
        raise SystemExit("meta-data org.godotengine.editor.version not found in the manifest")
    so, ssz, eo, esz, name_at, value_at = found
    start = bytearray(rest[so:so + ssz])
    for at, idx in ((name_at, idx_key), (value_at, idx_cls)):
        struct.pack_into("<I", start, at + 8, idx)    # raw value
        struct.pack_into("<I", start, at + 16, idx)   # typed value data (type 0x03 string)
        start[at + 15] = 0x03
    copy = bytes(start) + rest[eo:eo + esz]
    rest = rest[:eo + esz] + copy + rest[eo + esz:]
    pool = build_pool(strings + [PLUGIN_KEY, PLUGIN_CLASS])
    body = pool + rest
    return struct.pack("<HHI", 0x0003, 8, 8 + len(body)) + body


def main(src, dst):
    dex = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "classes2.dex"), "rb").read()
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
        names = zin.namelist()
        if "classes2.dex" in names:
            raise SystemExit("APK already has classes2.dex")
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename == "AndroidManifest.xml":
                data = patch_manifest(data)
            zout.writestr(info, data, compress_type=info.compress_type)
            if info.filename == "classes.dex":
                zi = zipfile.ZipInfo("classes2.dex", date_time=info.date_time)
                zout.writestr(zi, dex, compress_type=zipfile.ZIP_DEFLATED)
    print("patched", dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
