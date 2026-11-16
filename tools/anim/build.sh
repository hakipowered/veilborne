#!/bin/bash
# Render + pack characters: tools/anim/build.sh kaela liora ...
# Requires the Meshy FBX sources in tools/anim/fbx_tmp (imported) and GLBs in tools/anim/src.
cd "$(dirname "$0")/../.."
G=${G:-/tmp/Godot_v4.3-stable_linux.x86_64}
python3 tools/anim/config.py
for c in "$@"; do
  rm -rf tools/anim/out/$c
  xvfb-run -a -s "-screen 0 1280x1024x24" $G --rendering-driver opengl3 --path . res://tools/anim/render.tscn -- --char=$c 2>&1 | grep -E "rendered|SCRIPT ERROR|clip not found"
  python3 tools/anim/pack.py $c
done
