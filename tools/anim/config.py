"""Builds chars.json (render + pack config). Edit here, then: python3 config.py
Anim helpers:
  seg(clip, a, h, b, n, k, fps): n frames over normalized clip time [a,b]; frames 0..k cover [a,h] (anticipation),
     frames k..n-1 cover [h,b] (strike + follow-through). Event "hit" fires on frame k.
  lin(clip, a, b, n, fps, loop): uniform sampling.
"""
import json, os

def seg(clip, a, h, b, n, k, fps, ease_in=1.0, extra_events=None, yaw=0):
    t = []
    for i in range(n):
        if i <= k:
            u = (i / k) if k > 0 else 1.0
            u = u ** ease_in   # >1 = slow start (hold anticipation), fast into hit
            t.append(a + (h - a) * u)
        else:
            u = (i - k) / max(n - 1 - k, 1)
            u = 1 - (1 - u) ** 1.6   # fast out then settle (follow-through)
            t.append(h + (b - h) * u)
    ev = {"hit": k}
    if extra_events:
        ev.update(extra_events)
    return {"yaw": yaw, "clip": clip, "from": 0.0, "to": 1.0, "frames": n, "times": [round(x, 4) for x in t], "fps": fps, "loop": False, "events": ev}

def lin(clip, a, b, n, fps, loop=False, events=None):
    d = {"clip": clip, "from": a, "to": b, "frames": n, "fps": fps, "loop": loop}
    if events:
        d["events"] = events
    return d

C = {}
FB = "res://tools/anim/fbx_tmp/"

C["liora"] = {
    "model": FB + "l_a0.fbx",
    "clip_files": [FB + "l_%s.fbx" % x for x in ["a0", "a1", "a5", "a6", "a7", "a8", "run"]],
    "up_axis": 2, "cell": 256, "ss": 2, "cam_size": 2.7, "center_y": 0.9, "elev": 40,
    "props": [
        {"type": "crescent", "bone": "RightHand", "pos": [0, 0.08, 0], "rot": [0, 0, 0], "curve": 1},
        {"type": "crescent", "bone": "LeftHand", "pos": [0, 0.08, 0], "rot": [0, 0, 0], "curve": -1},
    ],
    "anims": {
        "idle": dict(lin("Combat_Stance", 0, 1, 10, 6, True), yaw=40),
        "run": lin("running", 0, 1, 8, 13, True, {"step": 0, "step2": 4}),
        "attack1": seg("Triple_Combo", 0.03, 0.18, 0.225, 8, 3, 18, 1.3, yaw=40),
        "attack2": seg("Triple_Combo", 0.215, 0.352, 0.40, 8, 3, 18, 1.3, yaw=40),
        "attack3": seg("Triple_Combo", 0.40, 0.522, 0.62, 10, 4, 16, 1.3, yaw=40),
        "dash": lin("Quick_Step", 0.05, 0.95, 7, 16),
        "special": seg("Double_Blade_Spin", 0.04, 0.28, 0.34, 12, 8, 16, 1.0),
        "hurt": lin("Hit_Reaction", 0.0, 0.45, 5, 14),
        "death": lin("Shot_and_Fall", 0.12, 0.95, 12, 14),
    },
}

json.dump(C, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "chars.json"), "w"), indent=1)
print("ok", list(C))
