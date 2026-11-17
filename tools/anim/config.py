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

def rt(file, clip, a, b, n, fps, loop=False, events=None):
    """clip from another Meshy rig, moved onto this skeleton by render.gd's world-space retargeting"""
    d = {"retarget": {"file": file, "clip": clip}, "from": a, "to": b, "frames": n, "fps": fps, "loop": loop}
    if events:
        d["events"] = events
    return d

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
    "up_axis": 2, "cell": 288, "ss": 2, "cam_size": 3.04, "center_y": 0.9, "elev": 40, "height_m": 1.72,
    "props": [
        {"type": "crescent", "bone": "RightHand", "pos": [0, 0.08, 0], "rot": [0, 0, 0], "curve": 1},
        {"type": "crescent", "bone": "LeftHand", "pos": [0, 0.08, 0], "rot": [0, 0, 0], "curve": -1},
    ],
    "anims": {
        "idle": dict(lin("Combat_Stance", 0, 1, 10, 6, True), yaw=40),
        "run": dict(rt("voidcaster/a6.glb", "Lean_Forward_Sprint", 0, 1, 12, 12.5, True, {"step": [0, 6]}), prop_lock=[[-115, 0, 15], [-115, 0, -15]]),
        "run_stop": dict(rt("voidcaster/a7.glb", "Sprint_and_Sudden_Stop", 0.25, 0.72, 8, 18), prop_lock=[[-115, 0, 15], [-115, 0, -15]]),
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
    "up_axis": 2, "cell": 480, "ss": 2, "cam_size": 4.78, "center_y": 0.9, "elev": 40, "height_m": 1.75,
    "props": [{"type": "spear", "bone": "RightHand", "pos": [0, 0.08, 0], "rot": [90, 0, 0]}],
    "anims": {
        "idle": dict(lin("Combat_Stance", 0, 1, 10, 6, True), yaw=0),
        # athletic forward-lean sprint (retargeted from another Meshy rig), spear held steady; fps plants the feet at
        # her def speed (see RUN_FPS below), hero.gd scales playback by ground speed
        "run": dict(rt("voidcaster/a6.glb", "Lean_Forward_Sprint", 0, 1, 12, 11.0, True, {"step": [0, 6]}), prop_lock=[[110, 0, 10]]),
        "run_stop": dict(rt("voidcaster/a7.glb", "Sprint_and_Sudden_Stop", 0.25, 0.72, 8, 18), prop_lock=[[110, 0, 10]]),
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
    "up_axis": 2, "cell": 352, "ss": 2, "cam_size": 3.6, "center_y": 1.0, "elev": 40, "height_m": 2.55,
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
    "up_axis": 1, "cell": 448, "ss": 2, "cam_size": 3.5, "center_y": 0.75, "elev": 40, "height_m": 2.2,
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

# Heroines: rendered WITHOUT weapons, at ~183 px/m (crisp at the manor's larger size); the equipped weapon is a painted
# sprite drawn per frame at the hand (tools/anim/hands.py -> art/anim/<id>/hands.gd, entities/anim_sprite.gd).
for _h in ("kaela", "liora"):
    C[_h]["weapon_props"] = C[_h].pop("props")   # the old baked-in props (kept for reference)
    C[_h].update({"export_hands": True, "cell": 576, "cam_size": 3.15, "ink_px": 3, "webp_q": 88, "vram_hq": True})

# Downscale enemy atlases to roughly their on-screen size (keeps the APK under 100 MB).

# ---------------------------------------------------------------- chapter enemies + generals (Meshy rigs in src/<kind>/)
# Hurt/death come from the sporeling rig (retargeted), so each rig only needed its own idle + signature clips.
def split(clip, h, nw, na, fw, fa, a=0.0, b=1.0, src=None):
    """windup = [a,h] (held anticipation), strike = [h,b]. src = retarget file for clips from another rig."""
    if src:
        return rt(src, clip, a, h, nw, fw), rt(src, clip, h, b, na, fa, False, {"hit": 1})
    return lin(clip, a, h, nw, fw), lin(clip, h, b, na, fa, False, {"hit": 1})

HURT = rt("sporeling/a3.glb", "Hit_Reaction", 0.0, 0.45, 4, 14)
DEATH = rt("sporeling/a4.glb", "Dead", 0.0, 0.95, 10, 12)

def enemy(kind, files, size, anims, **kw):
    cell, cam, cy, h = {"s": (288, 2.5, 0.68, 1.3), "m": (352, 3.1, 0.92, 1.8), "l": (384, 3.7, 1.12, 2.2),
                        "b": (448, 4.1, 1.2, 2.4)}[size]
    d = {"model": kind + "/model.glb", "clip_files": [kind + "/" + f for f in files], "up_axis": 1, "cell": cell, "ss": 2,
         "cam_size": cam, "center_y": cy, "elev": 40, "height_m": h, "anims": anims}
    d["anims"].setdefault("hurt", HURT)
    d["anims"].setdefault("death", DEATH)
    d.update(kw)
    C[kind] = d

def pair(anims, name, sp):
    anims[name + "_w"], anims[name] = sp

A = {"idle": lin("Idle", 0, 1, 10, 8, True), "move": lin("walking", 0, 1, 8, 9, True, {"step": [0, 4]}),
     "hurt": lin("Hit_Reaction", 0.0, 0.45, 4, 14), "death": lin("Dead", 0.0, 0.95, 10, 12)}
pair(A, "throw", split("Crouch_Pull_and_Throw", 0.5, 6, 6, 10, 14))
pair(A, "puff", split("mage_soell_cast", 0.42, 5, 6, 10, 14))
enemy("sporeling", ["model.glb", "a1.glb", "a2.glb", "a3.glb", "a4.glb", "walk.glb", "run.glb"], "s", A, out_scale=0.7)

A = {"idle": lin("Axe_Stance", 0, 1, 10, 8, True), "move": lin("walking_man", 0, 1, 8, 8, True, {"step": [0, 4]}),
     "guard": lin("Axe_Stance", 0, 0.3, 3, 6)}
pair(A, "bash", split("Shield_Push_Left", 0.42, 5, 6, 10, 14))
pair(A, "slash", split("Right_Hand_Sword_Slash", 0.38, 5, 6, 10, 15))
pair(A, "chop", split("Charged_Axe_Chop", 0.55, 7, 6, 9, 14))
enemy("thornknight", ["model.glb", "a2.glb", "a3.glb", "a4.glb", "walk.glb"], "l", A, out_scale=0.75)

A = {"idle": lin("Idle", 0, 1, 10, 8, True), "move": lin("walking_man", 0, 1, 8, 8, True, {"step": [0, 4]}),
     "roar": lin("Chest_Pound", 0, 1, 10, 10), "charge_w": lin("Head_Down_Charge", 0.0, 0.2, 4, 8),
     "charge": lin("Head_Down_Charge", 0.2, 1.0, 8, 14, True, {"step": [0, 4]})}
pair(A, "slam", split("Charged_Ground_Slam", 0.42, 7, 6, 10, 16, 0.03, 0.92))
enemy("forgegolem", ["model.glb", "a1.glb", "a2.glb", "a3.glb", "walk.glb"], "l", A, out_scale=0.72)

A = {"idle": lin("Combat_Stance", 0, 1, 8, 8, True), "move": lin("running", 0, 1, 8, 12, True, {"step": [0, 4]}),
     "hop": lin("Roll_Dodge", 0.05, 0.8, 7, 14)}
pair(A, "cast", split("mage_soell_cast", 0.42, 5, 6, 10, 14))
pair(A, "volley", split("mage_soell_cast_3", 0.48, 6, 6, 10, 14))
enemy("cinderimp", ["model.glb", "a1.glb", "a2.glb", "a4.glb", "run.glb"], "s", A, out_scale=0.7)

A = {"idle": lin("Combat_Stance", 0, 1, 8, 8, True), "move": lin("Spear_Walk", 0, 1, 8, 9, True, {"step": [0, 4]})}
pair(A, "sweep", split("Reaping_Swing", 0.48, 6, 7, 10, 15))
pair(A, "thrust", split("Thrust_Slash", 0.38, 5, 6, 10, 15))
enemy("hollowpike", ["model.glb", "a1.glb", "a2.glb", "a3.glb", "walk.glb"], "m", A, out_scale=0.72)

A = {"idle": lin("Idle", 0, 1, 10, 8, True), "move": rt("forgegolem/walk.glb", "walking_man", 0, 1, 8, 8, True, {"step": [0, 4]})}
pair(A, "cast", split("Charged_Spell_Cast", 0.2, 6, 6, 10, 14, 0.0, 0.5, "gen_bloom/a4.glb"))
pair(A, "bolt", split("mage_soell_cast", 0.42, 5, 6, 10, 14, src="cinderimp/a1.glb"))
enemy("voidcaster", ["model.glb"], "m", A, out_scale=0.72)

A = {"idle": lin("Combat_Stance", 0, 1, 8, 8, True), "move": lin("walking_man", 0, 1, 8, 9, True, {"step": [0, 4]}),
     "dash": rt("gen_seneschal/a9.glb", "run_fast", 0, 1, 8, 16, True, {"step": [0, 4]})}
pair(A, "upslash", split("Charged_Upward_Slash", 0.52, 6, 6, 10, 15))
pair(A, "slash", split("Charged_Slash", 0.52, 6, 6, 10, 15))
pair(A, "judgment", split("Sword_Judgment", 0.55, 7, 7, 10, 14))
pair(A, "combo", split("Weapon_Combo_2", 0.15, 3, 12, 10, 16))
enemy("hollowchampion", ["model.glb", "a1.glb", "a2.glb", "a3.glb", "a4.glb", "walk.glb"], "l", A, out_scale=0.75)

A = {"idle": lin("Combat_Stance", 0, 1, 10, 8, True), "move": lin("walking_man", 0, 1, 8, 8, True, {"step": [0, 4]}),
     "roar": lin("Shouting_Angrily", 0, 1, 12, 10), "leap_w": lin("Basic_Jump", 0.0, 0.3, 4, 10),
     "leap": lin("Basic_Jump", 0.3, 1.0, 8, 12)}
pair(A, "reap", split("Reaping_Swing", 0.48, 6, 7, 10, 15))
pair(A, "combo", split("Triple_Combo_Attack", 0.18, 4, 12, 10, 16))
pair(A, "cast", split("Charged_Spell_Cast", 0.2, 6, 6, 10, 14, 0.0, 0.5))
enemy("gen_bloom", ["model.glb", "a1.glb", "a2.glb", "a3.glb", "a4.glb", "a5.glb", "walk.glb"], "b", A, out_scale=0.85)

A = {"idle": lin("Axe_Stance", 0, 1, 10, 8, True), "move": lin("walking_man", 0, 1, 8, 8, True, {"step": [0, 4]}),
     "roar": lin("Chest_Pound", 0, 1, 10, 10), "charge_w": rt("forgegolem/a2.glb", "Head_Down_Charge", 0.0, 0.2, 4, 8),
     "charge": rt("forgegolem/a2.glb", "Head_Down_Charge", 0.2, 1.0, 8, 14, True, {"step": [0, 4]}),
     "spin_w": lin("Axe_Spin_Attack", 0.0, 0.22, 4, 10), "spin": lin("Axe_Spin_Attack", 0.22, 0.95, 9, 16, True)}
pair(A, "swing", split("Heavy_Hammer_Swing", 0.5, 6, 6, 10, 15))
pair(A, "slam", split("Charged_Ground_Slam", 0.42, 7, 6, 10, 16, 0.03, 0.92))
pair(A, "stomp", split("Angry_Ground_Stomp", 0.45, 5, 6, 10, 15))
enemy("gen_anvil", ["model.glb", "a1.glb", "a2.glb", "a3.glb", "a5.glb", "a6.glb", "walk.glb"], "b", A, out_scale=0.85)

A = {"idle": lin("Combat_Stance", 0, 1, 10, 8, True), "move": lin("walking_man", 0, 1, 8, 8, True, {"step": [0, 4]}),
     "dash": lin("run_fast", 0, 1, 8, 16, True, {"step": [0, 4]}),
     "roar": rt("gen_bloom/a5.glb", "Shouting_Angrily", 0, 1, 12, 10)}
pair(A, "judgment", split("Sword_Judgment", 0.55, 7, 7, 10, 14))
pair(A, "combo", split("Triple_Combo_Attack", 0.18, 4, 12, 10, 16))
pair(A, "cast", split("Charged_Spell_Cast", 0.2, 6, 6, 10, 14, 0.0, 0.5))
enemy("gen_seneschal", ["model.glb", "a1.glb", "a2.glb", "a4.glb", "a9.glb", "walk.glb"], "b", A, out_scale=0.85)

A = {"idle": lin("Idle", 0, 1, 10, 8, True), "move": lin("running", 0, 1, 8, 13, True, {"step": [0, 4]})}
pair(A, "lunge", split("Charged_Slash", 0.52, 5, 6, 10, 15, src="hollowchampion/a2.glb"))
pair(A, "rake", split("Right_Hand_Sword_Slash", 0.38, 5, 6, 10, 15, src="thornknight/a3.glb"))
enemy("bogwraith", ["model.glb", "run.glb"], "m", A, out_scale=0.7)

A = {"idle": lin("Idle", 0, 1, 10, 8, True), "move": lin("walking_man", 0, 1, 8, 8, True, {"step": [0, 4]}),
     "spin_w": rt("gen_anvil/a3.glb", "Axe_Spin_Attack", 0.0, 0.22, 4, 10),
     "spin": rt("gen_anvil/a3.glb", "Axe_Spin_Attack", 0.22, 0.95, 9, 16, True)}
pair(A, "swing", split("Heavy_Hammer_Swing", 0.5, 6, 6, 10, 15, src="gen_anvil/a1.glb"))
pair(A, "slam", split("Charged_Ground_Slam", 0.42, 7, 6, 10, 16, 0.03, 0.92, "gen_anvil/a2.glb"))
enemy("hammerwarden", ["model.glb", "walk.glb"], "l", A, out_scale=0.75,
      props=[{"type": "hammer", "bone": "RightHand", "pos": [0, 8, 0], "scale": 100, "rot": [90, 0, 0], "length": 1.2, "head": 0.42}])

# GLB rigs carry a 0.01 armature scale, so props on them use scale 100 (pos in cm)
# weapons (procedural props, tools/anim/props.gd): Maren's scythe, Hollis's forge hammer
C["gen_bloom"]["props"] = [{"type": "scythe", "bone": "RightHand", "pos": [0, 8, 0], "scale": 100, "rot": [90, 0, 0]}]
C["gen_anvil"]["props"] = [{"type": "hammer", "bone": "RightHand", "pos": [0, 8, 0], "scale": 100, "rot": [90, 0, 0], "length": 1.4, "head": 0.55}]

# Hollow Regent (final boss, 3 phases): phase roar + ground slam retargeted from the other rigs
C["regent"]["anims"]["roar"] = rt("gen_bloom/a5.glb", "Shouting_Angrily", 0, 1, 12, 10)
C["regent"]["anims"]["slam_w"], C["regent"]["anims"]["slam"] = split("Charged_Ground_Slam", 0.42, 7, 6, 10, 16, 0.03, 0.92, "forgegolem/a3.glb")

for _k, _s in {"brute": 0.65, "regent": 0.9, "shade": 0.75, "spitter": 0.9}.items():
    C[_k]["out_scale"] = _s
json.dump(C, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "chars.json"), "w"), indent=1)
print("ok", list(C))
