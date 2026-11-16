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
APK_URL="https://github.com/$REPO/releases/latest/download/Veilborne.apk"
python3 - "$CODE" "$NAME" "$NOTES" "$APK_URL" > build/version.json <<'PY'
import json, sys
print(json.dumps({"version_code": int(sys.argv[1]), "version_name": sys.argv[2], "notes": sys.argv[3], "apk_url": sys.argv[4]}))
PY
BODY=$(python3 -c 'import json,sys; print(json.dumps({"tag_name":"v"+sys.argv[1],"name":"Veilborne v"+sys.argv[1],"body":sys.argv[2]+"\n\nDownload: https://github.com/"+sys.argv[3]+"/releases/latest/download/Veilborne.apk","make_latest":"true"}))' "$NAME" "$NOTES" "$REPO")
REL_ID=$(echo "$BODY" | gh api -X POST "repos/$REPO/releases" --input - --jq .id)
for f in Veilborne.apk version.json; do
  ct=$([ "$f" = version.json ] && echo application/json || echo application/vnd.android.package-archive)
  gh api -X POST -H "Content-Type: $ct" "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=$f" --input "build/$f" --jq .browser_download_url
done
echo "Published. Permanent download link: $APK_URL"
