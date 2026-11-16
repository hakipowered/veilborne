#!/usr/bin/env python3
"""Veilborne voice pipeline: Warden barks + narrator lines -> res://audio/voice/.

Lines come from data/story.gd (Story.BARKS and Story.NARRATION); this file never copies the text.

  python3 audio/voice/build_voice.py texts            # every line with its TTS voice + emotion tags (JSON)
  python3 audio/voice/build_voice.py process RAW_DIR  # raw takes -> mastered OGG, then rewrites index.gd
  python3 audio/voice/build_voice.py index            # only rewrite index.gd from the OGGs on disk

Raw takes (from the Whiteboard_Images start_audio / job_part tools, ElevenLabs v3) go in RAW_DIR as
either one file per line:   RAW_DIR/<speaker>/<context>_<n>.mp3   (n counts from 0, story.gd order)
or one take per context:     RAW_DIR/<speaker>/<context>.mp3      (every line of the context, read in
                             order with a [long pause] between; split at the N-1 longest silences).
Mastering: trim leading/trailing silence, two-pass loudnorm to -16 LUFS (true peak -1.5 dB), mono,
44.1 kHz, OGG Vorbis at about 64 kbps -> audio/voice/<speaker>/<context>_<n>.ogg.
index.gd lists every line in story.gd order; a line with no clip yet gets "" (Audio.voice stays silent
for it but still returns the subtitle text).
"""
import ast
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VOICE_DIR = os.path.join(ROOT, "audio", "voice")
STORY = os.path.join(ROOT, "data", "story.gd")

# One ElevenLabs voice per speaker, kept for every line of that speaker.
# NOTE: the auditions could not be run (fal.ai credit ran out); these are the planned picks and the
# audition alternates. Audition the alternates on the first line listed, then fix the choice here.
CAST = {
    "oriel":    {"voice": "Alice",   "alternates": ["Lily", "Charlotte"], "stability": 0.4,
                 "style": "[Scottish accent] [booming]", "speed": 1.0},
    "vessa":    {"voice": "Jessica", "alternates": ["Laura", "Sarah"], "stability": 0.3,
                 "style": "[Irish accent] [excited]", "speed": 1.12},
    "mireth":   {"voice": "Bill",    "alternates": ["George", "Callum"], "stability": 0.5,
                 "style": "[West Country accent] [worried]", "speed": 0.9},
    "sable":    {"voice": "Lily",    "alternates": ["Charlotte", "Alice"], "stability": 0.4,
                 "style": "[London accent] [sly]", "speed": 1.0},
    "narrator": {"voice": "Matilda", "alternates": ["Alice", "Lily"], "stability": 0.5,
                 "style": "[Yorkshire accent] [dry]", "speed": 0.95},
}
# Extra emotion tags per context (ElevenLabs v3 acts them out; they are not spoken).
CONTEXT_TAGS = {
    "greet": "", "first_meeting": "[warm]", "low_health": "[concerned]", "boss_floor": "[urgent]",
    "coop": "[delighted]", "run_start": "[fond]",
}

TARGET_LUFS = -16.0
TRUE_PEAK = -1.5
BITRATE = "64k"


def _gd_const(src: str, name: str) -> dict:
    """Parses `const NAME := { ... }` (strings, lists, nested dicts) from GDScript into Python."""
    m = re.search(r"^const %s := \{" % name, src, re.M)
    if not m:
        raise SystemExit("story.gd: const %s not found" % name)
    i = m.end() - 1
    depth, j, in_str = 0, i, False
    while j < len(src):
        c = src[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "#":
            j = src.index("\n", j) - 1
        elif c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return ast.literal_eval(src[i:j + 1])


def load_lines() -> dict:
    """{speaker: {context: [text, ...]}} in story.gd order; the narrator is speaker "narrator"."""
    src = open(STORY, encoding="utf-8").read()
    out = dict(_gd_const(src, "BARKS"))
    out["narrator"] = _gd_const(src, "NARRATION")
    return out


def tts_text(speaker: str, context: str, text: str) -> str:
    cast = CAST[speaker]
    tag = CONTEXT_TAGS.get(context, "")
    if context.startswith("death_"):
        tag = "[wry]"
    elif context.startswith("chapter_"):
        tag = "[storytelling]"
    return " ".join(t for t in (cast["style"], tag, text) if t)


def cmd_texts() -> None:
    lines = load_lines()
    jobs = []
    for spk, ctxs in lines.items():
        cast = CAST[spk]
        for ctx, arr in ctxs.items():
            for n, text in enumerate(arr):
                jobs.append({"speaker": spk, "context": ctx, "n": n, "voice": cast["voice"],
                             "model": "v3", "stability": cast["stability"], "speed": cast["speed"],
                             "text": tts_text(spk, ctx, text), "out": "%s/%s_%d.mp3" % (spk, ctx, n)})
    json.dump(jobs, sys.stdout, indent=1, ensure_ascii=False)
    print()


def _run(args: list) -> str:
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr[-2000:])
    return r.stderr


TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.04,areverse,"
        "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.04,areverse,"
        "apad=pad_dur=0.08")


def master(src: str, dst: str) -> None:
    """Trim, two-pass loudnorm, mono OGG Vorbis."""
    meas = _run(["ffmpeg", "-hide_banner", "-nostats", "-i", src, "-af",
                 TRIM + ",loudnorm=I=%g:TP=%g:LRA=11:print_format=json" % (TARGET_LUFS, TRUE_PEAK),
                 "-f", "null", "-"])
    js = json.loads(meas[meas.rindex("{"):meas.rindex("}") + 1])
    ln = ("loudnorm=I=%g:TP=%g:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:"
          "measured_thresh=%s:offset=%s:linear=true" % (TARGET_LUFS, TRUE_PEAK, js["input_i"],
          js["input_tp"], js["input_lra"], js["input_thresh"], js["target_offset"]))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    _run(["ffmpeg", "-hide_banner", "-nostats", "-y", "-i", src, "-af", TRIM + "," + ln,
          "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-b:a", BITRATE, dst])


def split_take(src: str, count: int, tmpdir: str) -> list:
    """Splits one take holding `count` lines at its count-1 longest silences."""
    if count == 1:
        return [src]
    log = _run(["ffmpeg", "-hide_banner", "-nostats", "-i", src, "-af",
                "silencedetect=noise=-40dB:d=0.25", "-f", "null", "-"])
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    gaps = sorted(zip(starts, ends), key=lambda g: g[1] - g[0], reverse=True)
    gaps = [g for g in gaps if g[0] > 0.05][:count - 1]
    if len(gaps) < count - 1:
        raise RuntimeError("%s: found %d pauses, need %d" % (src, len(gaps), count - 1))
    cuts = sorted((a + b) / 2 for a, b in gaps)
    bounds = [0.0] + cuts + [None]
    parts = []
    for k in range(count):
        out = os.path.join(tmpdir, "part_%d.wav" % k)
        args = ["ffmpeg", "-hide_banner", "-nostats", "-y", "-i", src, "-ss", "%.3f" % bounds[k]]
        if bounds[k + 1] is not None:
            args += ["-to", "%.3f" % bounds[k + 1]]
        _run(args + [out])
        parts.append(out)
    return parts


def cmd_process(raw_dir: str) -> None:
    lines = load_lines()
    done = 0
    for spk, ctxs in lines.items():
        for ctx, arr in ctxs.items():
            base = os.path.join(raw_dir, spk)
            singles = {}
            for n in range(len(arr)):
                for ext in ("mp3", "wav", "ogg"):
                    f = os.path.join(base, "%s_%d.%s" % (ctx, n, ext))
                    if os.path.exists(f):
                        singles[n] = f
                        break
            with tempfile.TemporaryDirectory() as tmp:
                if not singles:
                    for ext in ("mp3", "wav", "ogg"):
                        f = os.path.join(base, "%s.%s" % (ctx, ext))
                        if os.path.exists(f):
                            singles = dict(enumerate(split_take(f, len(arr), tmp)))
                            break
                for n, f in sorted(singles.items()):
                    master(f, os.path.join(VOICE_DIR, spk, "%s_%d.ogg" % (ctx, n)))
                    done += 1
    print("mastered %d clips" % done)
    cmd_index()


def cmd_index() -> None:
    lines = load_lines()
    out = ["# Generated by audio/voice/build_voice.py - do not edit by hand.",
           "# VOICE[speaker][context][i] is the clip for line i of Story.BARKS / Story.NARRATION",
           "# (speaker \"narrator\"). \"\" = not recorded yet.",
           "extends RefCounted", "", "const VOICE := {"]
    have = total = 0
    for spk, ctxs in lines.items():
        out.append('\t"%s": {' % spk)
        for ctx, arr in ctxs.items():
            paths = []
            for n in range(len(arr)):
                rel = "%s/%s_%d.ogg" % (spk, ctx, n)
                ok = os.path.exists(os.path.join(VOICE_DIR, rel))
                paths.append('"res://audio/voice/%s"' % rel if ok else '""')
                have += ok
                total += 1
            out.append('\t\t"%s": [%s],' % (ctx, ", ".join(paths)))
        out.append("\t},")
    out.append("}")
    with open(os.path.join(VOICE_DIR, "index.gd"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("index.gd: %d of %d lines have clips" % (have, total))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["texts"]:
        cmd_texts()
    elif a[:1] == ["process"] and len(a) == 2:
        cmd_process(a[1])
    elif a[:1] == ["index"]:
        cmd_index()
    else:
        print(__doc__)
        sys.exit(1)
