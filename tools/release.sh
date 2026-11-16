#!/usr/bin/env bash
# Build, sign and publish a Veilborne release to GitHub so installed copies get the in-game update prompt.
# Usage: tools/release.sh "What changed in this version"
# Needs: Godot 4.3 + Android export templates, java, $KEYSTORE (same key every time, or Android refuses the update),
#        $SIGNER (uber-apk-signer jar), gh CLI with push access to $REPO.
set -euo pipefail
cd "$(dirname "$0")/.."
NOTES="${1:-Improvements and fixes.}"
GODOT="${GODOT:-/tmp/Godot_v4.3-stable_linux.x86_64}"
KEYSTORE="${KEYSTORE:-/mnt/project-files/veilborne/keys/veilborne-debug.keystore}"
SIGNER="${SIGNER:-/mnt/project-files/veilborne/keys/uber-apk-signer.jar}"
REPO=$(grep -oP 'const REPO := "\K[^"]+' autoload/updater.gd)
CODE=$(grep -oP 'const VERSION_CODE := \K[0-9]+' autoload/updater.gd)
NAME=$(grep -oP 'const VERSION_NAME := "\K[^"]+' autoload/updater.gd)
sed -i "s/^version\/code=.*/version\/code=$CODE/; s/^version\/name=.*/version\/name=\"$NAME\"/" export_presets.cfg
echo "Releasing $REPO v$NAME (code $CODE)"
rm -rf build && mkdir -p build
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Android" build/unsigned.apk 2>&1 | grep -E "export: end|ERROR" || true
java -jar "$SIGNER" -a build/unsigned.apk --ks "$KEYSTORE" --ksAlias veilborne --ksPass android --ksKeyPass android -o build/signed >/dev/null
mv build/signed/*.apk build/Veilborne.apk
DL="https://veilborne-download.hakipowered.workers.dev"
APK_URL="$DL/Veilborne.apk"
RAW="https://raw.githubusercontent.com/$REPO/downloads"
# GitHub caps files at 100 MB, so the APK is split into parts; the Cloudflare Worker streams them back as one file.
PUB=$(mktemp -d)
split -b 45m -d -a 3 build/Veilborne.apk "$PUB/Veilborne-$CODE.part"
SIZE=$(stat -c %s build/Veilborne.apk)
python3 - "$CODE" "$NAME" "$NOTES" "$APK_URL" "$SIZE" "$RAW" "$PUB" > build/manifest.json <<'PY'
import json, sys, os
code, name, notes, apk, size, raw, pub = sys.argv[1:]
parts = sorted(f for f in os.listdir(pub) if ".part" in f)
print(json.dumps({"version_code": int(code), "version_name": name, "notes": notes, "size": int(size),
                  "parts": [raw + "/" + f for f in parts]}))
PY
python3 - "$CODE" "$NAME" "$NOTES" "$APK_URL" > build/version.json <<'PY'
import json, sys
print(json.dumps({"version_code": int(sys.argv[1]), "version_name": sys.argv[2], "notes": sys.argv[3], "apk_url": sys.argv[4]}))
PY
# Publish to the single-commit "downloads" branch (replaced each release, so the repo stays small).
cp build/version.json build/manifest.json "$PUB/"
cat > "$PUB/README.md" <<MD
# Veilborne v$NAME

**Download (always the newest version):** $APK_URL

$NOTES

Installed copies check for updates on launch and update from inside the game.
MD
git -C "$PUB" init -q -b downloads
git -C "$PUB" add -A
git -C "$PUB" -c user.name="$(git config user.name || echo hakipowered)" -c user.email="$(git config user.email || echo noreply@github.com)" commit -qm "Veilborne v$NAME"
git -C "$PUB" push -f "$(git remote get-url origin)" downloads
rm -rf "$PUB"
echo "Pushed parts for v$NAME. NEXT: write build/manifest.json to Workers KV key 'manifest' (namespace veilborne-builds) to make it live at $APK_URL"
