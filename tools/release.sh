#!/usr/bin/env bash
# Publish a Veilborne release. Installed games see it on their next launch.
#
#   tools/release.sh "What changed"          content pack (default): only the files changed
#                                             since the installed APK, usually a few MB
#   tools/release.sh --base "What changed"   full APK (needed when project.godot, boot.gd or
#                                             class_name scripts change, or the pack gets big)
#
# Before running: bump VERSION_CODE/VERSION_NAME in autoload/updater.gd (and for --base also
# BASE_CODE in autoload/boot.gd to the same code) and COMMIT. The release is built from HEAD.
#
# After running: write build/manifest.json to Workers KV key "pending" (namespace
# veilborne-builds). The Worker's cron copies the files into KV and then makes the release
# live by itself, usually within a few minutes (watch /status).
#
# Needs: Godot 4.3 + Android export templates, java, $KEYSTORE (same key every time, or
#        Android refuses the update), $SIGNER (uber-apk-signer jar), git push access.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=pack
if [ "${1:-}" = "--base" ]; then MODE=base; shift; fi
NOTES="${1:-Improvements and fixes.}"
GODOT="${GODOT:-/tmp/Godot_v4.3-stable_linux.x86_64}"
KEYSTORE="${KEYSTORE:-/mnt/project-files/veilborne/keys/veilborne-debug.keystore}"
SIGNER="${SIGNER:-/mnt/project-files/veilborne/keys/uber-apk-signer.jar}"
REPO=$(grep -oP 'const REPO := "\K[^"]+' autoload/updater.gd)
CODE=$(grep -oP 'const VERSION_CODE := \K[0-9]+' autoload/updater.gd)
NAME=$(grep -oP 'const VERSION_NAME := "\K[^"]+' autoload/updater.gd)
BASE=$(grep -oP 'const BASE_CODE := \K[0-9]+' autoload/boot.gd)
RAW="https://raw.githubusercontent.com/$REPO/downloads"
DL="https://veilborne-download.hakipowered.workers.dev"

if ! git diff --quiet HEAD -- . ':!export_presets.cfg'; then
  echo "Commit your changes first: the release is built from HEAD." >&2; exit 1
fi
rm -rf build && mkdir -p build
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

if [ "$MODE" = base ]; then
  [ "$BASE" = "$CODE" ] || { echo "--base: set BASE_CODE in autoload/boot.gd to $CODE and commit." >&2; exit 1; }
  echo "Releasing full APK v$NAME (code $CODE)"
  sed -i "s/^version\/code=.*/version\/code=$CODE/; s/^version\/name=.*/version\/name=\"$NAME\"/" export_presets.cfg
  "$GODOT" --headless --path . --export-release "Android" build/unsigned.apk 2>&1 | grep -E "export: end|ERROR" || true
  java -jar "$SIGNER" -a build/unsigned.apk --ks "$KEYSTORE" --ksAlias veilborne --ksPass android --ksKeyPass android -o build/signed >/dev/null
  mv build/signed/*.apk build/Veilborne.apk
  FILE=build/Veilborne.apk; ID="apk-$CODE"
else
  # Each full release is remembered as branch apk-<code> (tag pushes are refused here).
  git fetch -q origin "refs/heads/apk-$BASE:refs/remotes/origin/apk-$BASE" \
    || { echo "No branch apk-$BASE: make a --base release first." >&2; exit 1; }
  echo "Releasing content pack v$NAME (code $CODE) on top of APK $BASE"
  CHANGED=$(git diff --name-only --diff-filter=AMR "origin/apk-$BASE" HEAD)
  # Things only a full APK can change: they are read before the pack is loaded.
  if echo "$CHANGED" | grep -qxE 'project\.godot|autoload/boot\.gd|export_presets\.cfg|icon\.(png|svg)'; then
    echo "project.godot / boot.gd / icon changed since APK $BASE: use --base." >&2; exit 1
  fi
  if git diff "origin/apk-$BASE" HEAD -- '*.gd' | grep -qE '^\+class_name '; then
    echo "A script gained a class_name since APK $BASE: use --base." >&2; exit 1
  fi
  FILES=$(echo "$CHANGED" | grep -vE '^(tools|tests|docs|build)/|\.md$|^\.git|\.gdignore$' | sed 's/\.import$//' | sort -u \
    | while read -r f; do [ -f "$f" ] && echo "res://$f"; done || true)
  [ -n "$FILES" ] || { echo "Nothing changed since APK $BASE." >&2; exit 1; }
  echo "$FILES" | sed 's/^/  /'
  # One-off export preset that contains only the changed files (plus what they depend on).
  cp export_presets.cfg build/export_presets.bak
  trap 'cp build/export_presets.bak export_presets.cfg' EXIT
  python3 - "$FILES" <<'PY'
import re, sys
files = [f for f in sys.argv[1].split("\n") if f]
src = open("export_presets.cfg").read()
m = re.search(r"\[preset\.0\]\n(.*?)\[preset\.0\.options\]\n(.*?)(?=\n\[preset\.1\]|\Z)", src, re.S)
head, opts = m.group(1), m.group(2)
head = re.sub(r'^name=.*$', 'name="Patch"', head, flags=re.M)
head = re.sub(r'^export_filter=.*$', 'export_filter="resources"', head, flags=re.M)
lst = ", ".join('"%s"' % f for f in files)
head = re.sub(r'^include_filter=.*$', 'include_filter=""\nexport_files=PackedStringArray(%s)' % lst, head, flags=re.M)
open("export_presets.cfg", "w").write(src.rstrip("\n") + "\n\n[preset.1]\n" + head + "[preset.1.options]\n" + opts.rstrip("\n") + "\n")
PY
  "$GODOT" --headless --path . --export-pack "Patch" build/content.pck 2>&1 | grep -E "export: end|ERROR" || true
  cp build/export_presets.bak export_presets.cfg; trap - EXIT
  [ -s build/content.pck ] || { echo "Pack export failed." >&2; exit 1; }
  FILE=build/content.pck; ID="pack-$CODE"
fi

SIZE=$(stat -c %s "$FILE")
SHA=$(sha256sum "$FILE" | cut -d' ' -f1)
echo "$FILE: $((SIZE / 1048576)) MB"
PUB=$(mktemp -d)
split -b 45m -d -a 3 "$FILE" "$PUB/$ID.part"
PREV=$(curl -fsS "$RAW/manifest.json" || echo '{}')
python3 - "$MODE" "$CODE" "$NAME" "$NOTES" "$ID" "$SIZE" "$SHA" "$RAW" "$PUB" "$BASE" "$PREV" > build/manifest.json <<'PY'
import json, sys, os
mode, code, name, notes, bid, size, sha, raw, pub, base, prev = sys.argv[1:]
parts = [raw + "/" + f for f in sorted(os.listdir(pub)) if f.startswith(bid + ".part")]
blob = {"id": bid, "code": int(code), "size": int(size), "sha256": sha, "parts": parts}
prev = json.loads(prev or "{}")
if mode == "base":
    apk, pack = blob, None
else:
    apk = prev.get("apk")
    if not apk or apk.get("code") != int(base):
        sys.exit("The live release is not built on APK %s; use --base." % base)
    pack = dict(blob, base_code=int(base))
print(json.dumps({"version_code": int(code), "version_name": name, "notes": notes, "apk": apk, "pack": pack}))
PY
cp build/manifest.json "$PUB/"
cat > "$PUB/README.md" <<MD
# Veilborne v$NAME

**Download (always the newest version):** $DL/Veilborne.apk

$NOTES

Installed copies check for updates on launch and update from inside the game.
MD
git -C "$PUB" init -q -b downloads
git -C "$PUB" add -A
git -C "$PUB" -c user.name="$(git config user.name || echo hakipowered)" -c user.email="$(git config user.email || echo noreply@github.com)" commit -qm "Veilborne v$NAME"
git -C "$PUB" push -q -f "$(git remote get-url origin)" downloads
rm -rf "$PUB"
if [ "$MODE" = base ]; then
  git push -q -f origin "HEAD:refs/heads/apk-$CODE"
fi
echo "Pushed $ID. NEXT: write build/manifest.json to Workers KV key 'pending'; it goes live once $DL/status shows it ready."
