#!/usr/bin/env bash
# Rebuilds tools/android/classes2.dex (the VeilRestart plugin) from src/.
# The stubs only stand in for Android / Godot classes at compile time; the
# real ones are in the APK. Needs javac and dalvik-dx (Maven Central:
# com.jakewharton.android.repackaged:dalvik-dx:16.0.1) as $DX_JAR.
set -euo pipefail
cd "$(dirname "$0")"
DX_JAR="${DX_JAR:-/tmp/dalvik-dx.jar}"
[ -f "$DX_JAR" ] || curl -fsSo "$DX_JAR" https://repo1.maven.org/maven2/com/jakewharton/android/repackaged/dalvik-dx/16.0.1/dalvik-dx-16.0.1.jar
T=$(mktemp -d)
javac -nowarn --release 8 -d "$T/stubs" $(find stubs -name '*.java') 2>&1 | grep -v "^warning\|^1 warning" || true
javac -nowarn --release 8 -cp "$T/stubs" -d "$T/out" $(find src -name '*.java') 2>&1 | grep -v "^warning\|^1 warning" || true
java -cp "$DX_JAR" com.android.dx.command.Main --dex --min-sdk-version=21 --output=classes2.dex "$T/out"
rm -rf "$T"
echo "built tools/android/classes2.dex"
