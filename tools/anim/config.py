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

def times(clip, ts, k, fps, yaw=0):
    return {"yaw": yaw, "clip": clip, "from": 0.0, "to": 1.0, "frames": len(ts), "times": ts, "fps": fps, "loop": False, "events": ({"hit": k} if k >= 0 else {})}

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
    "up_axis": 2, "cell": 256, "ss": 2, "cam_size": 2.7, "center_y": 0.9, "elev": 40, "height_m": 1.72,
    "props": [
        {"type": "crescent", "bone": "RightHand", "pos": [0, 0.08, 0], "rot": [0, 0, 0], "curve": 1},
        {"type": "crescent", "bone": "LeftHand", "pos": [0, 0.08, 0], "rot": [0, 0, 0], "curve": -1},
    ],
    "anims": {
        "idle": dict(lin("Combat_Stance", 0, 1, 10, 6, True), yaw=40),
        "run": lin("running", 0, 1, 8, 13, True, {"step": [0, 4]}),
        "attack1": seg("Triple_Combo", 0.03, 0.18, 0.225, 8, 3, 18, 1.3, yaw=40),
        "attack2": seg("Triple_Combo", 0.215, 0.352, 0.40, 8, 3, 18, 1.3, yaw=40),
        "attack3": seg("Triple_Combo", 0.40, 0.522, 0.62, 10, 4, 16, 1.3, yaw=40),
        "dash": lin("Quick_Step", 0.05, 0.95, 7, 16),
        "special": seg("Double_Blade_Spin", 0.04, 0.28, 0.34, 12, 8, 16, 1.0),
        "hurt": lin("Hit_Reaction", 0.0, 0.45, 5, 14),
        "death": lin("Shot_and_Fall", 0.12, 0.95, 12, 14),
    },
}

C["kaela"] = {
    "model": FB + "k_a0.fbx",
    "clip_files": [FB + "k_%s.fbx" % x for x in ["a0", "a1", "a2", "a3", "a5", "a7", "a8", "run"]] + [FB + "l_a6.fbx"],
    "up_axis": 2, "cell": 352, "ss": 2, "cam_size": 3.5, "center_y": 0.9, "elev": 40, "height_m": 1.75,
    "props": [{"type": "spear", "bone": "RightHand", "pos": [0, 0.08, 0], "rot": [90, 0, 0]}],
    "anims": {
        "idle": dict(lin("Combat_Stance", 0, 1, 10, 6, True), yaw=0),
        "run": lin("running", 0, 1, 8, 13, True, {"step": [0, 4]}),
        "attack1": seg("Thrust_Slash", 0.10, 0.25, 0.31, 8, 3, 18, 1.3),
        "attack2": seg("Weapon_Combo_2", 0.06, 0.255, 0.30, 8, 4, 18, 1.3),
        "attack3": seg("Charged_Slash", 0.25, 0.53, 0.70, 11, 5, 16, 1.3),
        "special": times("Charged_Ground_Slam", [0.06, 0.10, 0.13, 0.17, 0.30, 0.45, 0.50, 0.53, 0.56, 0.59, 0.62, 0.66, 0.72], 9, 16),
        "dash": lin("Quick_Step", 0.05, 0.95, 7, 16),
        "hurt": lin("Hit_Reaction", 0.0, 0.4, 5, 14),
        "death": lin("Dead", 0.0, 0.7, 12, 14),
    },
}

C["shade"] = {
    "model": "shade/model.glb", "procedural": "res://tools/anim/proc_shade.gd", "height_m": 1.8,
    "cell": 256, "ss": 2, "cam_size": 3.0, "center_y": 0.9, "elev": 40, "weight_sharp": 4.0,
    "anims": {
        "idle": {"frames": 10, "fps": 10, "loop": True},
        "move": {"frames": 8, "fps": 12, "loop": True},
        "windup": {"frames": 6, "fps": 12},
        "attack": {"frames": 8, "fps": 16, "events": {"hit": 2}},
        "hurt": {"frames": 5, "fps": 14},
        "death": {"frames": 10, "fps": 12},
    },
}

C["spitter"] = {
    "model": "spitter/model.glb", "procedural": "res://tools/anim/proc_spitter.gd", "height_m": 1.1,
    "cell": 224, "ss": 2, "cam_size": 2.6, "center_y": 0.5, "elev": 40, "weight_sharp": 4.0,
    "anims": {
        "idle": {"frames": 10, "fps": 10, "loop": True},
        "move": {"frames": 8, "fps": 14, "loop": True},
        "windup": {"frames": 6, "fps": 12},
        "attack": {"frames": 7, "fps": 16, "events": {"hit": 2}},
        "hurt": {"frames": 5, "fps": 14},
        "death": {"frames": 10, "fps": 12},
    },
}

C["brute"] = {
    "model": FB + "b_a0.fbx",
    "clip_files": [FB + "b_a%d.fbx" % i for i in range(5)],
    "up_axis": 2, "cell": 352, "ss": 2, "cam_size": 3.6, "center_y": 1.0, "elev": 40, "height_m": 2.1,
    "anims": {
        "idle": lin("Idle", 0, 1, 10, 8, True),
        "move": lin("Slow_Orc_Walk", 0, 1, 8, 10, True, {"step": [0, 4]}),
        # telegraph: hammer/fists rise overhead and hold (hold the last frame until attack)
        "windup": times("Charged_Ground_Slam", [0.03, 0.07, 0.09, 0.11, 0.13, 0.17, 0.30, 0.40], -1, 12),
        "attack": seg("Charged_Ground_Slam", 0.40, 0.59, 0.95, 9, 3, 16, 1.4),
        "hurt": lin("Hit_Reaction", 0.0, 0.45, 5, 14),
        "death": lin("Dead", 0.0, 0.75, 12, 13),
    },
}

C["regent"] = {
    "model": "regent/r_a0.glb",
    "clip_files": ["regent/r_a%d.glb" % i for i in range(5)] + ["regent/r_walk.glb"],
    "up_axis": 1, "cell": 384, "ss": 2, "cam_size": 4.0, "center_y": 1.1, "elev": 40, "height_m": 2.4,
    "anims": {
        "idle": lin("Idle_02", 0, 1, 12, 8, True),
        "move": lin("r_walk", 0, 1, 8, 11, True, {"step": [0, 4]}),
        "charge": lin("RunFast", 0, 1, 8, 16, True, {"step": [0, 4]}),
        "windup": times("Charged_Spell_Cast", [0.0, 0.04, 0.08, 0.11, 0.14, 0.17], -1, 10),
        "attack": seg("Charged_Spell_Cast", 0.17, 0.26, 0.45, 8, 2, 16, 1.0),
        # full two-phase cast: gather (0..0.26, release "hit"), then raise both arms (summon "cast" ~0.67)
        "cast": dict(times("Charged_Spell_Cast", [0.0, 0.05, 0.10, 0.14, 0.18, 0.22, 0.26, 0.32, 0.45, 0.58, 0.62, 0.66, 0.70, 0.80, 0.92], 6, 14), events={"hit": 6, "cast": 12}),
        "hurt": lin("Hit_Reaction", 0.0, 0.45, 5, 14),
        "death": lin("dying_backwards", 0.0, 0.92, 12, 12),
    },
}

json.dump(C, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "chars.json"), "w"), indent=1)
print("ok", list(C))
