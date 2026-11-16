#!/bin/bash
# Render + pack characters: tools/anim/build.sh kaela liora ...
# Sources: Meshy FBX clips in tools/anim/fbx_tmp (heroes, brute), GLBs in tools/anim/src (regent, shade, spitter).
# fbx_tmp is kept hidden from Godot with a .gdignore (otherwise ~220 MB of FBX would be exported into the APK);
# this script lifts it, imports, renders, packs, then restores it.
cd "$(dirname "$0")/../.."
G=${G:-/tmp/Godot_v4.3-stable_linux.x86_64}
python3 tools/anim/config.py
HID=0
if [ -f tools/anim/fbx_tmp/.gdignore ]; then
  HID=1
  rm tools/anim/fbx_tmp/.gdignore
  $G --headless --import --path . >/dev/null 2>&1
fi
for c in "$@"; do
  rm -rf tools/anim/out/$c
  xvfb-run -a -s "-screen 0 1280x1024x24" $G --rendering-driver opengl3 --path . res://tools/anim/render.tscn -- --char=$c 2>&1 | grep -E "rendered|SCRIPT ERROR|clip not found"
  python3 tools/anim/pack.py $c
done
if [ $HID = 1 ]; then
  touch tools/anim/fbx_tmp/.gdignore
fi
# (re)import the atlas pages so the game sees the new frames
$G --headless --import --path . >/dev/null 2>&1
