extends Node2D
## Veilborne chamber environment (ENVIRONMENT agent).
## Builds one painted isometric chamber: an island of floor with irregular edges over an animated void,
## painted ledges, back walls, exit gates (0 to 2), y-sorted props with collision, hazards (water, lava,
## spike traps, falling debris, void pits), breakable urns, animated fire / light pools / particles,
## foreground silhouettes and a vignette. See docs/OVERHAUL.md "Environment" for the interface.
##
## Floor keys: "catacomb" | "throne" (chapter I and the Regent's hall, the original rooms),
##   "garden" | "garden_boss"  (Chapter II, the Drowned Garden)
##   "forge"  | "forge_boss"   (Chapter III, the Ember Forge)
##   "hollow" | "hollow_boss"  (Chapter IV, the Hollow Throne approach and the final hall)
##
## Layers (z_index, relative to this node which should sit at the arena origin with z 0):
##   -100 abyss backdrop (opaque, parallax)   -95 void particles   -80 ledges   -70 floor   -69 floor shading
##   -68 water / lava / pits   -67 lilies, trap plates, markers   -66 heat shimmer   -60 walls   -58 wall banners
##   -55 gates  -54 gate light rays  -50 reward icons   0 y-sorted props (lead's entity layer)
##   +20 foreground silhouettes / debris    CanvasLayer 2: vignette (below HUD layer 10)

signal debris_impact(pos: Vector2, radius: float, damage: float) ## a falling-debris rock just landed
signal prop_broken(id: int, pos: Vector2)                        ## break_prop() shattered a breakable

const ENV := "res://art/env/"
const MAX_LIGHTS := 16
const SHADER_LIGHTS := 6
const ISO := 0.53 ## floor y squash for top-down art laid on the iso floor

const CHAPTER_TITLES := {
	"catacomb": "Chapter I: The Gilded Catacombs",
	"garden": "Chapter II: The Drowned Garden",
	"forge": "Chapter III: The Ember Forge",
	"hollow": "Chapter IV: The Hollow Throne",
}

const THEMES := {
	"oriel": {
		"sigil": "oriel", "sigil_color": Color(1.0, 0.56, 0.2), "statue": "statue_oriel",
		"flame": [Color(1.0, 0.95, 0.7), Color(1.0, 0.55, 0.15), Color(0.8, 0.14, 0.04)],
		"light": Color(1.0, 0.58, 0.26), "tint": Color(1.06, 1.0, 0.92), "fog": Color(0.42, 0.34, 0.26),
		"mist": Color(0.22, 0.36, 0.33), "particles": "embers", "name": "Hall of Embers",
	},
	"vessa": {
		"sigil": "vessa", "sigil_color": Color(0.55, 0.8, 1.0), "statue": "statue_vessa",
		"flame": [Color(0.9, 0.97, 1.0), Color(0.4, 0.7, 1.0), Color(0.12, 0.22, 0.85)],
		"light": Color(0.5, 0.7, 1.0), "tint": Color(0.92, 0.98, 1.08), "fog": Color(0.32, 0.4, 0.55),
		"mist": Color(0.2, 0.28, 0.42), "particles": "sparks", "name": "Stormwell Crypt",
	},
	"mireth": {
		"sigil": "mireth", "sigil_color": Color(0.32, 0.95, 0.85), "statue": "statue_mireth",
		"flame": [Color(0.85, 1.0, 0.95), Color(0.25, 0.85, 0.8), Color(0.05, 0.3, 0.45)],
		"light": Color(0.35, 0.9, 0.82), "tint": Color(0.9, 1.04, 1.04), "fog": Color(0.3, 0.5, 0.52),
		"mist": Color(0.16, 0.4, 0.42), "particles": "bubbles", "name": "Drowned Ossuary",
	},
	"sable": {
		"sigil": "sable", "sigil_color": Color(1.0, 0.38, 0.52), "statue": "statue_sable",
		"flame": [Color(1.0, 0.85, 0.88), Color(1.0, 0.3, 0.45), Color(0.55, 0.04, 0.18)],
		"light": Color(1.0, 0.42, 0.5), "tint": Color(1.04, 0.94, 0.96), "fog": Color(0.45, 0.28, 0.33),
		"mist": Color(0.32, 0.2, 0.26), "particles": "petals", "name": "Briar Sepulchre",
	},
	"regent": {
		"sigil": "regent", "sigil_color": Color(0.78, 0.52, 1.0), "statue": "",
		"flame": [Color(1.0, 0.9, 1.0), Color(0.75, 0.4, 1.0), Color(0.3, 0.06, 0.6)],
		"light": Color(0.72, 0.48, 1.0), "tint": Color(1.0, 1.0, 1.0), "fog": Color(0.35, 0.25, 0.5),
		"mist": Color(0.3, 0.2, 0.45), "particles": "motes_violet", "name": "Throne of the Hollow Regent",
	},
	# ------------------------------------------------ chapters II - IV
	"garden": {
		"sigil_color": Color(0.4, 1.0, 0.85),
		"flame": [Color(0.85, 1.0, 0.97), Color(0.3, 0.9, 0.85), Color(0.04, 0.35, 0.45)],
		"light": Color(0.38, 0.95, 0.85), "tint": Color(0.74, 0.84, 0.82), "fog": Color(0.32, 0.56, 0.52),
		"mist": Color(0.14, 0.34, 0.34), "particles": "fireflies", "name": "The Drowned Garden",
		"grime": Color(0.06, 0.16, 0.1, 1.0), "seam": Color(0.25, 0.5, 0.42, 0.45), "seam_w": 0.008,
		"ambient": 0.6, "fog_amount": 0.32, "wall_glow": Color(0.3, 0.95, 0.85), "wall_glow_k": 0.55,
		"rim_light": Color(0.5, 1.0, 0.9), "gate_tint": Color(0.82, 1.0, 0.95), "lantern": Color(0.5, 1.0, 0.85),
		"void_caustics": 0.35, "void_stars": 0.0, "void_dark": 0.78, "sigil_r": 430.0,
	},
	"forge": {
		"sigil_color": Color(1.0, 0.45, 0.12),
		"flame": [Color(1.0, 0.95, 0.7), Color(1.0, 0.5, 0.12), Color(0.75, 0.12, 0.03)],
		"light": Color(1.0, 0.5, 0.16), "tint": Color(1.22, 1.06, 0.98), "fog": Color(0.38, 0.2, 0.14),
		"mist": Color(0.3, 0.12, 0.08), "particles": "forge", "name": "The Ember Forge",
		"grime": Color(0.12, 0.05, 0.03, 1.0), "seam": Color(1.0, 0.42, 0.1, 0.4), "seam_w": 0.006,
		"ambient": 0.84, "fog_amount": 0.14, "wall_glow": Color(1.0, 0.55, 0.15), "wall_glow_k": 0.5,
		"rim_light": Color(1.0, 0.55, 0.2), "gate_tint": Color(1.0, 0.86, 0.76), "lantern": Color(1.0, 0.6, 0.3),
		"void_caustics": 0.0, "void_stars": 0.0, "void_dark": 0.82, "sigil_r": 440.0,
	},
	"hollow": {
		"sigil_color": Color(0.75, 0.5, 1.0),
		"flame": [Color(1.0, 0.9, 1.0), Color(0.72, 0.38, 1.0), Color(0.28, 0.05, 0.58)],
		"light": Color(0.7, 0.45, 1.0), "tint": Color(0.92, 0.9, 1.0), "fog": Color(0.34, 0.24, 0.5),
		"mist": Color(0.26, 0.17, 0.4), "particles": "hollow", "name": "The Hollow Throne",
		"grime": Color(0.1, 0.06, 0.16, 1.0), "seam": Color(0.75, 0.6, 0.32, 0.75), "seam_w": 0.007,
		"ambient": 0.78, "fog_amount": 0.2, "wall_glow": Color(0.62, 0.3, 1.0), "wall_glow_k": 0.65,
		"rim_light": Color(0.75, 0.55, 1.0), "gate_tint": Color(0.9, 0.86, 1.0), "lantern": Color(0.72, 0.5, 1.0),
		"void_caustics": 0.0, "void_stars": 0.9, "void_dark": 0.8, "sigil_r": 470.0, "checker": 1.0,
	},
}

## kind -> texture, world height, collision radius (0 = walk-through), foot (fraction of texture height
## from the bottom where the object touches the floor), shadow width (world px).
## Optional: "break" (breakable via break_prop), "flip" (may be mirrored).
const PROPS := {
	"pillar": {"tex": "props/pillar.png", "h": 430.0, "r": 42.0, "foot": 0.02, "shadow": 140.0},
	"pillar_frame": {"tex": "props/pillar.png", "h": 560.0, "r": 0.0, "foot": 0.02, "shadow": 160.0},
	"pillar_big": {"tex": "props/pillar.png", "h": 760.0, "r": 0.0, "foot": 0.02, "shadow": 220.0},
	"broken_column": {"tex": "props/broken_column.png", "h": 220.0, "r": 44.0, "foot": 0.12, "shadow": 190.0},
	"brazier": {"tex": "props/brazier.png", "h": 120.0, "r": 34.0, "foot": 0.03, "shadow": 110.0},
	"urns": {"tex": "props/urns.png", "h": 150.0, "r": 40.0, "foot": 0.05, "shadow": 140.0},
	"skulls": {"tex": "props/skulls.png", "h": 120.0, "r": 40.0, "foot": 0.06, "shadow": 150.0},
	"statue_oriel": {"tex": "props/statue_oriel.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"statue_vessa": {"tex": "props/statue_vessa.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"statue_mireth": {"tex": "props/statue_mireth.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"statue_sable": {"tex": "props/statue_sable.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"crystals": {"tex": "props/crystals.png", "h": 170.0, "r": 46.0, "foot": 0.08, "shadow": 160.0},
	"candelabra": {"tex": "props/candelabra.png", "h": 230.0, "r": 26.0, "foot": 0.02, "shadow": 90.0},
	"throne": {"tex": "props/throne.png", "h": 520.0, "r": 130.0, "foot": 0.06, "shadow": 420.0},
	# Drowned Garden
	"fountain": {"tex": "garden/fountain.png", "h": 250.0, "r": 105.0, "foot": 0.2, "shadow": 300.0},
	"g_lantern": {"tex": "garden/lantern.png", "h": 230.0, "r": 24.0, "foot": 0.04, "shadow": 90.0},
	"g_statue": {"tex": "garden/statue.png", "h": 320.0, "r": 48.0, "foot": 0.07, "shadow": 160.0, "flip": true},
	"reeds": {"tex": "garden/reeds.png", "h": 150.0, "r": 58.0, "foot": 0.12, "shadow": 200.0, "flip": true},
	"willow": {"tex": "garden/willow.png", "h": 520.0, "r": 58.0, "foot": 0.1, "shadow": 300.0, "flip": true},
	"g_pot": {"tex": "garden/pot.png", "h": 105.0, "r": 30.0, "foot": 0.05, "shadow": 100.0, "break": true, "flip": true},
	"g_arch": {"tex": "garden/arch.png", "h": 340.0, "r": 32.0, "foot": 0.05, "shadow": 120.0, "flip": true},
	# Ember Forge
	"anvil": {"tex": "forge/anvil.png", "h": 150.0, "r": 52.0, "foot": 0.14, "shadow": 170.0, "flip": true},
	"bellows": {"tex": "forge/bellows.png", "h": 220.0, "r": 72.0, "foot": 0.14, "shadow": 230.0, "flip": true},
	"chainpost": {"tex": "forge/chainpost.png", "h": 330.0, "r": 28.0, "foot": 0.05, "shadow": 110.0, "flip": true},
	"crucible": {"tex": "forge/crucible.png", "h": 150.0, "r": 50.0, "foot": 0.08, "shadow": 160.0},
	"furnace": {"tex": "forge/furnace.png", "h": 440.0, "r": 82.0, "foot": 0.07, "shadow": 240.0, "flip": true},
	"rack": {"tex": "forge/rack.png", "h": 190.0, "r": 55.0, "foot": 0.14, "shadow": 200.0, "flip": true},
	"barrel": {"tex": "forge/barrel.png", "h": 110.0, "r": 30.0, "foot": 0.06, "shadow": 100.0, "break": true, "flip": true},
	# Hollow Throne
	"h_brazier": {"tex": "hollow/brazier.png", "h": 290.0, "r": 30.0, "foot": 0.04, "shadow": 110.0},
	"h_statue": {"tex": "hollow/statue.png", "h": 380.0, "r": 50.0, "foot": 0.09, "shadow": 170.0, "flip": true},
	"standard": {"tex": "hollow/standard.png", "h": 380.0, "r": 22.0, "foot": 0.04, "shadow": 110.0, "flip": true},
	"obelisk": {"tex": "hollow/obelisk.png", "h": 360.0, "r": 46.0, "foot": 0.09, "shadow": 160.0, "flip": true},
	"h_urn": {"tex": "hollow/urn.png", "h": 115.0, "r": 26.0, "foot": 0.04, "shadow": 90.0, "break": true},
	"h_candelabra": {"tex": "hollow/candelabra.png", "h": 250.0, "r": 24.0, "foot": 0.03, "shadow": 90.0, "flip": true},
	"h_throne": {"tex": "hollow/throne.png", "h": 800.0, "r": 150.0, "foot": 0.1, "shadow": 480.0},
}

## Classic room layouts in diamond units (u = x / W, v = y / H of the PLAYABLE half extents).
const LAYOUTS := {
	"oriel": [
		["pillar", -0.38, -0.12], ["pillar", 0.38, -0.12],
		["brazier", -0.64, 0.06], ["brazier", 0.64, 0.06], ["brazier", -0.24, 0.52], ["brazier", 0.24, 0.52],
		["statue_oriel", -0.5, -0.40], ["urns", 0.52, -0.38], ["skulls", 0.74, -0.16], ["broken_column", -0.74, -0.14],
	],
	"vessa": [
		["pillar", -0.3, -0.3], ["pillar", 0.3, -0.3], ["pillar", -0.3, 0.3], ["pillar", 0.3, 0.3],
		["brazier", -0.66, 0.0], ["brazier", 0.66, 0.0], ["brazier", 0.0, -0.62],
		["statue_vessa", 0.5, -0.40], ["broken_column", -0.52, -0.36], ["skulls", -0.62, 0.26], ["urns", 0.64, 0.24],
	],
	"mireth": [
		["statue_mireth", 0.0, -0.06],
		["brazier", -0.46, -0.34], ["brazier", 0.46, -0.34], ["brazier", -0.46, 0.36], ["brazier", 0.46, 0.36],
		["broken_column", -0.76, 0.0], ["urns", 0.76, 0.0], ["skulls", -0.2, -0.66], ["pillar", 0.24, -0.62],
	],
	"sable": [
		["statue_sable", -0.48, -0.42], ["pillar", -0.64, 0.26],
		["broken_column", -0.36, 0.08], ["broken_column", 0.36, 0.08],
		["brazier", -0.62, -0.16], ["brazier", 0.62, -0.16], ["brazier", -0.26, 0.5], ["brazier", 0.26, 0.5],
		["urns", 0.5, -0.4], ["skulls", 0.72, 0.1],
	],
	"regent": [
		["throne", 0.0, -0.76],
		["candelabra", -0.26, -0.6], ["candelabra", 0.26, -0.6],
		["crystals", -0.56, -0.22], ["crystals", 0.58, -0.2], ["crystals", -0.4, 0.42], ["crystals", 0.42, 0.44],
		["brazier", -0.72, 0.04], ["brazier", 0.72, 0.04],
		["pillar", -0.42, 0.0], ["pillar", 0.42, 0.0],
	],
}

## Island outlines in VISUAL diamond units (x / vhalf.x, y / vhalf.y). The back walls run straight from
## L' (wl along T->L) through T to R' (wr along T->R); "front" lists the outline from R' round to L'.
## "start" is the heroes' entry point in playable units.
const SHAPES := {
	"diamond": {"wl": 1.0, "wr": 1.0, "front": [[0.5, 0.5], [0.0, 1.0], [-0.5, 0.5]], "start": [0.0, 0.62]},
	"cross": {"wl": 1.0, "wr": 1.0, "front": [[0.72, 0.28], [0.44, 0.22], [0.30, 0.70], [0.0, 1.0], [-0.30, 0.70],
		[-0.44, 0.22], [-0.72, 0.28]], "start": [0.0, 0.66]},
	"horseshoe": {"wl": 1.0, "wr": 1.0, "front": [[0.66, 0.34], [0.38, 0.42], [0.16, 0.30], [0.0, 0.34], [-0.16, 0.30],
		[-0.38, 0.42], [-0.66, 0.34]], "start": [0.0, 0.12]},
	"wide": {"wl": 0.8, "wr": 0.8, "front": [[0.92, 0.04], [0.66, 0.32], [0.34, 0.6], [0.0, 0.86], [-0.34, 0.6],
		[-0.66, 0.32], [-0.92, 0.04]], "start": [0.0, 0.6]},
	"arena": {"wl": 0.86, "wr": 0.86, "front": [[0.96, 0.02], [0.74, 0.25], [0.44, 0.54], [0.0, 0.92], [-0.44, 0.54],
		[-0.74, 0.25], [-0.96, 0.02]], "start": [0.0, 0.66]},
}

## Chapter room layouts. props: [kind or "a|b" alternatives, u, v, (optional) 0 = no jitter].
## water / lava / pits: [u, v, radius px]; channels: lava polylines [[u, v], ...]; spikes: [u, v];
## debris: [u, v, radius px]; breakables: [kind, u, v] (a seeded subset is placed).
const CHAPTER_LAYOUTS := {
	"garden": [
		{"name": "Lily Terraces", "shape": "diamond",
			"props": [["fountain", 0.0, -0.5, 0], ["willow", -0.66, -0.06], ["willow", 0.6, -0.34], ["g_lantern", -0.3, -0.42],
				["g_lantern", 0.3, -0.62], ["g_lantern", -0.26, 0.5], ["g_lantern", 0.4, 0.4], ["reeds", 0.7, 0.12], ["g_statue|g_arch", -0.5, -0.4]],
			"water": [[-0.5, 0.2, 230.0], [0.46, -0.08, 190.0]],
			"breakables": [["g_pot", -0.12, -0.62], ["g_pot", 0.62, 0.22], ["g_pot", -0.72, 0.12], ["g_pot", 0.12, 0.7]]},
		{"name": "Weeping Cloister", "shape": "cross",
			"props": [["willow", -0.48, -0.32], ["willow", 0.5, -0.3], ["g_statue", 0.0, -0.66, 0], ["g_lantern", -0.34, 0.0],
				["g_lantern", 0.34, 0.0], ["g_lantern", 0.0, 0.42], ["g_arch", -0.78, 0.0], ["g_arch", 0.78, 0.0], ["reeds", 0.2, 0.62]],
			"water": [[0.0, -0.18, 170.0], [-0.6, 0.12, 150.0], [0.6, 0.12, 150.0]],
			"spikes": [[-0.2, 0.3], [0.2, 0.3]],
			"breakables": [["g_pot", -0.2, -0.56], ["g_pot", 0.22, -0.56], ["g_pot", -0.1, 0.78], ["g_pot", 0.68, -0.18]]},
		{"name": "Sunken Fountain Court", "shape": "wide",
			"props": [["fountain", 0.0, -0.02, 0], ["willow", -0.62, -0.2], ["g_statue", 0.54, -0.4], ["g_lantern", -0.4, -0.46],
				["g_lantern", 0.4, 0.36], ["g_lantern", -0.4, 0.36], ["reeds", 0.68, 0.06], ["g_arch", -0.2, -0.72]],
			"water": [[0.0, -0.02, 360.0]],
			"breakables": [["g_pot", 0.22, -0.6], ["g_pot", -0.7, 0.1], ["g_pot", 0.7, -0.14], ["g_pot", 0.0, 0.6]]},
		{"name": "Willow Grotto", "shape": "horseshoe",
			"props": [["willow", 0.0, -0.62, 0], ["willow", -0.72, 0.06], ["g_statue", 0.66, 0.0], ["g_lantern", -0.36, -0.36],
				["g_lantern", 0.36, -0.36], ["g_lantern", -0.5, 0.3], ["g_lantern", 0.5, 0.3], ["reeds", -0.3, 0.12], ["g_arch|reeds", 0.36, -0.62]],
			"water": [[-0.56, 0.36, 170.0], [0.56, 0.34, 170.0], [0.0, -0.3, 150.0]],
			"spikes": [[0.0, 0.1]],
			"breakables": [["g_pot", -0.2, -0.5], ["g_pot", 0.2, -0.5], ["g_pot", 0.76, 0.2], ["g_pot", -0.8, -0.1]]},
	],
	"garden_boss": [
		{"name": "The Drowned Heart", "shape": "arena",
			"props": [["fountain", 0.0, -0.64, 0], ["willow", -0.74, -0.06, 0], ["willow", 0.74, -0.06, 0], ["g_statue", -0.4, -0.5, 0],
				["g_statue", 0.4, -0.5, 0], ["g_lantern", -0.5, 0.22, 0], ["g_lantern", 0.5, 0.22, 0], ["g_lantern", -0.2, -0.42, 0],
				["g_lantern", 0.2, -0.42, 0], ["reeds", -0.3, 0.62, 0], ["reeds", 0.32, 0.6, 0]],
			"water": [[-0.56, -0.16, 200.0], [0.56, -0.16, 200.0], [0.0, 0.56, 180.0]],
			"breakables": [["g_pot", -0.72, 0.2], ["g_pot", 0.72, 0.2]]},
	],
	"forge": [
		{"name": "Bellows Hall", "shape": "diamond",
			"props": [["furnace", -0.5, -0.42], ["bellows", 0.5, -0.36], ["crucible", 0.32, -0.56], ["anvil", -0.3, 0.06],
				["anvil", 0.34, 0.1], ["chainpost", -0.72, 0.0], ["chainpost", 0.0, 0.62], ["rack", 0.66, -0.06]],
			"channels": [[[-0.98, 0.0], [-0.6, 0.24], [-0.4, 0.6]]],
			"spikes": [[0.0, -0.3], [0.2, 0.36]],
			"debris": [[0.5, 0.3, 150.0]],
			"breakables": [["barrel", -0.12, -0.62], ["barrel", 0.62, 0.2], ["barrel", -0.5, 0.3], ["barrel", 0.16, 0.6]]},
		{"name": "Slag Channels", "shape": "cross",
			"props": [["furnace", 0.0, -0.72, 0], ["bellows", -0.42, -0.42], ["crucible", 0.4, -0.44], ["anvil", -0.36, 0.0],
				["anvil", 0.36, 0.0], ["rack", 0.0, 0.5], ["chainpost", -0.8, 0.0], ["chainpost", 0.8, 0.0]],
			"channels": [[[-0.62, -0.38], [-0.36, -0.12], [-0.2, 0.28], [-0.24, 0.74]], [[0.62, -0.38], [0.36, -0.12], [0.2, 0.28], [0.24, 0.74]]],
			"spikes": [[0.0, -0.22]],
			"breakables": [["barrel", -0.6, 0.14], ["barrel", 0.6, 0.14], ["barrel", 0.0, 0.8], ["barrel", -0.12, -0.5]]},
		{"name": "Crucible Pit", "shape": "wide",
			"props": [["crucible", -0.36, -0.3], ["crucible", 0.36, -0.3], ["crucible", 0.0, 0.42], ["furnace", -0.62, -0.18],
				["bellows", 0.62, -0.16], ["anvil", -0.5, 0.26], ["rack", 0.5, 0.28], ["chainpost", 0.0, -0.66, 0]],
			"lava": [[0.0, -0.02, 210.0]],
			"spikes": [[-0.26, 0.24], [0.26, 0.22]],
			"debris": [[-0.3, -0.56, 140.0]],
			"breakables": [["barrel", 0.22, -0.62], ["barrel", -0.74, 0.08], ["barrel", 0.76, 0.06]]},
		{"name": "Anvil Gallery", "shape": "horseshoe",
			"props": [["furnace", -0.32, -0.66], ["furnace", 0.32, -0.66], ["anvil", -0.6, 0.12], ["anvil", 0.6, 0.12],
				["anvil", 0.0, -0.12, 0], ["bellows", -0.7, -0.18], ["chainpost", 0.72, -0.12], ["rack", 0.4, 0.36]],
			"pits": [[-0.36, -0.2, 130.0], [0.36, -0.22, 130.0]],
			"spikes": [[-0.3, 0.3], [0.0, -0.44]],
			"debris": [[0.0, 0.2, 150.0]],
			"breakables": [["barrel", -0.52, 0.36], ["barrel", 0.2, -0.46], ["barrel", -0.12, 0.2]]},
	],
	"forge_boss": [
		{"name": "The Great Furnace", "shape": "arena",
			"props": [["furnace", -0.32, -0.7, 0], ["furnace", 0.32, -0.7, 0], ["bellows", -0.62, -0.32, 0], ["bellows", 0.62, -0.32, 0],
				["crucible", -0.18, -0.52, 0], ["crucible", 0.18, -0.52, 0], ["anvil", -0.56, 0.3, 0], ["anvil", 0.56, 0.3, 0],
				["chainpost", -0.86, 0.0, 0], ["chainpost", 0.86, 0.0, 0]],
			"channels": [[[-0.86, 0.12], [-0.6, 0.12], [-0.36, 0.6]], [[0.86, 0.12], [0.6, 0.12], [0.36, 0.6]]],
			"debris": [[-0.4, -0.1, 170.0], [0.4, -0.1, 170.0]],
			"breakables": [["barrel", -0.78, -0.1], ["barrel", 0.78, -0.1]]},
	],
	"hollow": [
		{"name": "Gallery of Veils", "shape": "diamond",
			"props": [["h_statue", -0.42, -0.4], ["h_statue", 0.42, -0.4], ["h_statue", -0.42, 0.36], ["h_statue", 0.42, 0.36],
				["h_brazier", -0.7, 0.0], ["h_brazier", 0.7, 0.0], ["standard", 0.0, -0.7, 0], ["h_candelabra", -0.16, -0.58], ["h_candelabra", 0.16, -0.58]],
			"debris": [[-0.24, 0.0, 150.0]],
			"spikes": [[0.24, 0.02]],
			"breakables": [["h_urn", -0.64, -0.2], ["h_urn", 0.64, 0.2], ["h_urn", 0.1, 0.66], ["h_urn", -0.6, 0.24]]},
		{"name": "Broken Colonnade", "shape": "cross",
			"props": [["obelisk", -0.36, -0.3], ["obelisk", 0.36, -0.3], ["h_statue", 0.0, -0.7, 0], ["h_brazier", -0.6, -0.06],
				["h_brazier", 0.6, -0.06], ["standard", -0.24, 0.5], ["standard", 0.24, 0.5], ["h_candelabra", -0.7, 0.2]],
			"spikes": [[0.0, 0.1], [-0.3, 0.12], [0.3, 0.12]],
			"debris": [[0.0, -0.36, 140.0]],
			"breakables": [["h_urn", 0.74, 0.1], ["h_urn", -0.16, -0.56], ["h_urn", 0.16, -0.56], ["h_urn", 0.0, 0.8]]},
		{"name": "Hall of Banners", "shape": "horseshoe",
			"props": [["standard", -0.5, -0.36], ["standard", 0.5, -0.36], ["standard", -0.62, 0.22], ["standard", 0.62, 0.22],
				["h_brazier", -0.24, -0.62], ["h_brazier", 0.24, -0.62], ["obelisk", 0.0, -0.4, 0], ["h_candelabra", -0.4, 0.04], ["h_candelabra", 0.4, 0.04]],
			"spikes": [[-0.2, -0.1], [0.2, -0.1]],
			"debris": [[-0.5, 0.0, 130.0], [0.5, 0.0, 130.0]],
			"breakables": [["h_urn", -0.76, 0.0], ["h_urn", 0.76, 0.0], ["h_urn", -0.12, 0.12], ["h_urn", 0.12, 0.12]]},
		{"name": "Antechamber of Ash", "shape": "wide",
			"props": [["h_brazier", -0.36, -0.2], ["h_brazier", 0.36, -0.2], ["h_brazier", -0.3, 0.4], ["h_brazier", 0.3, 0.4], ["h_statue", -0.64, -0.14],
				["h_statue", 0.64, -0.14], ["obelisk", 0.0, -0.66, 0], ["standard", -0.4, 0.4], ["standard", 0.4, 0.4]],
			"pits": [[0.0, -0.02, 230.0]],
			"debris": [[-0.5, 0.18, 130.0]],
			"breakables": [["h_urn", -0.2, -0.52], ["h_urn", 0.2, -0.52], ["h_urn", 0.7, 0.1], ["h_urn", -0.7, 0.1]]},
	],
	"hollow_boss": [
		{"name": "The Hollow Throne", "shape": "arena",
			"props": [["h_throne", 0.0, -0.74, 0], ["standard", -0.34, -0.58, 0], ["standard", 0.34, -0.58, 0], ["h_brazier", -0.58, -0.3, 0],
				["h_brazier", 0.58, -0.3, 0], ["h_statue", -0.8, 0.0, 0], ["h_statue", 0.8, 0.0, 0], ["h_candelabra", -0.44, 0.38, 0],
				["h_candelabra", 0.44, 0.38, 0], ["obelisk", -0.2, 0.7, 0], ["obelisk", 0.2, 0.7, 0]],
			"debris": [[-0.36, 0.06, 160.0], [0.36, 0.06, 160.0]],
			"breakables": [["h_urn", -0.64, 0.14], ["h_urn", 0.64, 0.14]]},
	],
}

const HAZARD_DPS := {"lava": 30.0, "water": 0.0, "spikes": 40.0, "debris": 0.0}
const HAZARD_SLOW := {"lava": 0.25, "water": 0.35, "spikes": 0.0, "debris": 0.0}
const SPIKE_PERIOD := 3.2
const SPIKE_WARN := 0.6
const SPIKE_UP := 1.0
const DEBRIS_DAMAGE := 22.0

# --------------------------------------------------------------- state
var floor_key := "catacomb"
var room_index := 0
var theme_id := "oriel"
var theme: Dictionary = {}
var chapter := "catacomb"
var half := Vector2(1050, 560)   ## playable diamond half extents
var vhalf := Vector2(1140, 608)  ## visual floor half extents
var wall_h := 640.0
var force_variant := -1          ## tests / tools: pick a layout variant instead of the seeded one
var _variant := 0
var _layout: Dictionary = {}
var _legacy := true

var _obstacles: Array = []
var _spawns: Array = []
var _start := Vector2.ZERO
var _doors: Array = []           ## [{pos, gate, mat, rays, motes, light, top, base}]
var _exits := 1
var _has_gate := true
var _door_open := false
var _door_t := 0.0
var _lit := 0.0
var _wave := 1.0
var _tween: Tween

var _island := PackedVector2Array()   ## visual island outline (world)
var _walk := PackedVector2Array()     ## playable outline (world)
var _walk_g := PackedVector2Array()   ## playable outline in ground space (y * 2)
var _deep := PackedByteArray()        ## coarse grid: 1 = cell lies deep inside the walkable area
var _deep_org := Vector2.ZERO
var _deep_cell := 64.0
var _deep_w := 0
var _deep_h := 0
var _wl := 1.0
var _wr := 1.0

var _hazards: Array = []
var _spike_nodes: Array = []     ## [hazard index, spikes Node2D, warning glow, phase]
var _debris_zones: Array = []
var _breakables: Array = []      ## [{id, pos, radius, node, obstacle, broken}]
var _pools: Array = []           ## water pools: [center, radius]
var _ripples: Array = []         ## [Sprite2D, pool index, timer]
var _koi: Array = []             ## [holder, sprite, center, radius, speed, phase]
var _floaters: Array = []        ## [Sprite2D, base y, phase]
var _bursts: Array = []          ## [CPUParticles2D, interval, timer]
var _bellows: Array = []         ## [Sprite2D, base scale, phase]
var _heat_regions: Array = []
var _heat: Polygon2D

var _ysort_parent: Node2D
var _ysorted: Array = []     ## props living in the lead's y-sorted layer
var _halos: Array = []       ## [Node2D, base_scale, phase, base_alpha, y squash]
var _swingers: Array = []    ## [Node2D pivot, phase, amplitude]
var _silhouettes: Array = [] ## Node2D (fade near camera)
var _occluders: Array = []   ## [Node2D, half width, height] tall props that fade when the focus is behind them
var _cam_followers: Array = [] ## particle emitters that follow the camera
var _icons: Array = []       ## [Node2D, base y, phase]
var _rng := RandomNumberGenerator.new()

var _noise: Texture2D
var _dot: Texture2D
var _glow: Texture2D
var _shadow: Texture2D
var _white: Texture2D
var _petal: Texture2D
var _rock: Texture2D
var _ring: Texture2D
var _smoke: Texture2D

var _backdrop: Sprite2D
var _void_mat: ShaderMaterial
var _floor_mat: ShaderMaterial
var _wall_mats: Array = []
var _water_mats: Array = []
var _vignette: CanvasLayer
var _lights_a := PackedVector4Array()
var _lights_b := PackedVector4Array()
var _sa := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
var _sb := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
var _sigil_light := -1
var _flash := 0.0
var _low := false
var _max_shader_lights := SHADER_LIGHTS
var _flash_timer := 3.0
var _base_amounts := {}      ## CPUParticles2D -> full-quality amount

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

# =============================================================== public API

## Build (or rebuild) the chamber. Deterministic for a seed. `exits`: number of painted exit gates (0..2);
## -1 picks the default (catacomb rooms 1, chapter combat rooms 2, chapter bosses 1, final halls 0).
func build(p_floor_key: String, p_room_index: int, seed_value: int, exits := -1) -> void:
	_clear()
	floor_key = p_floor_key
	room_index = p_room_index
	_rng.seed = seed_value
	_legacy = not CHAPTER_LAYOUTS.has(floor_key)
	chapter = _chapter_of(floor_key)
	var boss := floor_key.ends_with("_boss") or floor_key == "throne"
	if _legacy:
		if floor_key == "throne":
			theme_id = "regent"
		else:
			floor_key = "catacomb"
			chapter = "catacomb"
			theme_id = ["oriel", "vessa", "mireth", "sable"][posmod(room_index, 4)]
		_layout = {"shape": "diamond"}
	else:
		theme_id = chapter
		var variants: Array = CHAPTER_LAYOUTS[floor_key]
		# every variant comes up within a run, starting at a seed-dependent one
		if force_variant >= 0:
			_variant = posmod(force_variant, variants.size())
		else:
			_variant = posmod(posmod(seed_value - room_index, 97) + room_index, variants.size())
		_layout = variants[_variant]
	if boss:
		half = Vector2(1150, 620)
		wall_h = 700.0
	else:
		half = Vector2(1050, 560)
		wall_h = 640.0
	if exits < 0:
		if floor_key == "throne" or floor_key == "hollow_boss":
			exits = 0
		elif floor_key == "catacomb" or boss:
			exits = 1
		else:
			exits = 2
	_exits = clampi(exits, 0, 2)
	_has_gate = _exits > 0
	theme = THEMES[theme_id]
	var m := 90.0
	vhalf = Vector2(half.x + m, half.y + m * half.y / half.x)
	_door_open = false
	_door_t = 0.0
	_lit = 0.0
	_wave = 1.0
	_make_shared_textures()
	_build_island()
	_build_backdrop()
	_build_rims()
	_build_floor()
	_build_walls()
	_build_gates()
	if _legacy:
		_build_layout()
	else:
		_build_chapter_layout()
	_build_particles()
	_build_foreground()
	_build_vignette()
	_compute_spawns()
	_push_lights()
	for n in find_children("*", "CPUParticles2D", true, false):
		_base_amounts[n] = n.amount
	for p in _ysorted:
		for n in p.find_children("*", "CPUParticles2D", true, false):
			_base_amounts[n] = n.amount
	if _low:
		_apply_low()
	if is_instance_valid(_ysort_parent):
		add_ysorted_props_to(_ysort_parent)

func get_bounds_half() -> Vector2:
	return half

func get_obstacles() -> Array:
	return _obstacles

## First exit (kept for callers that know only one door).
func get_door_pos() -> Vector2:
	return _doors[0]["pos"] if _doors.size() > 0 else Vector2(0, -half.y + 70.0)

## Exit spots for "choose your next chamber" (index i matches set_door_rewards()[i]).
## Chapter rooms: one painted gate per entry (get_gate_count() == size). Classic catacomb rooms keep the
## arena's convention: [the gate, a spot in front of the side wall where the arena stands its veil arch].
## Rooms without a gate return [get_door_pos()].
func get_door_positions() -> Array:
	if _doors.is_empty():
		return [get_door_pos()]
	var a: Array = []
	for d in _doors:
		a.append(d["pos"])
	if _legacy and _doors.size() == 1:
		var side := -1.0 if posmod(room_index, 2) == 0 else 1.0
		a.append(Vector2(side * half.x * 0.3, -half.y * 0.52))
	return a

## Number of exits drawn by the environment itself (painted gates). Entries of get_door_positions()
## at or past this index need the arena's own arch.
func get_gate_count() -> int:
	return _doors.size()

## Index of the exit within `dist` of pos, or -1.
func get_door_index_at(pos: Vector2, dist := 90.0) -> int:
	var dp := get_door_positions()
	for i in range(dp.size()):
		if pos.distance_to(dp[i]) < dist:
			return i
	return -1

## Opens (or closes) every exit together.
func set_door_open(open: bool) -> void:
	if open == _door_open:
		return
	_door_open = open
	if _tween and _tween.is_valid():
		_tween.kill()
	if not open:
		_door_t = 0.0
		_lit = 0.0
		_wave = 1.0
		for d in _doors:
			d["motes"].emitting = false
		_apply_dynamic()
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(v: float): _wave = v; _apply_dynamic(), 0.0, 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v: float): _lit = v; _apply_dynamic(), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _has_gate:
		_tween.tween_method(func(v: float): _door_t = v; _apply_dynamic(), 0.0, 1.0, 1.7).set_delay(0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		for d in _doors:
			d["motes"].emitting = true

func is_door_open() -> bool:
	return _door_open

## Floating reward icons above the painted gates (Hades-style door previews). Each entry: Texture2D,
## a resource path, or null for none. Call after build(); cleared by the next build().
func set_door_rewards(rewards: Array) -> void:
	for ic in _icons:
		if is_instance_valid(ic[0]):
			ic[0].queue_free()
	_icons.clear()
	for i in range(mini(rewards.size(), _doors.size())):
		var r = rewards[i]
		var tex: Texture2D = null
		if r is Texture2D:
			tex = r
		elif r is String and r != "" and ResourceLoader.exists(r):
			tex = load(r)
		if tex == null:
			continue
		var d: Dictionary = _doors[i]
		var root := Node2D.new()
		root.position = d["top"]
		root.z_index = -50
		var h := Sprite2D.new()
		h.texture = _glow
		h.material = _additive()
		h.scale = Vector2.ONE * 1.7
		h.modulate = Color(theme["light"].lerp(Color(1, 0.9, 0.7), 0.5), 0.75)
		root.add_child(h)
		var s := Sprite2D.new()
		s.texture = tex
		s.scale = Vector2.ONE * 120.0 / maxf(tex.get_width(), tex.get_height())
		root.add_child(s)
		add_child(root)
		_icons.append([root, root.position.y, _rng.randf() * TAU])

func get_spawn_points() -> Array:
	return _spawns

func get_player_start() -> Vector2:
	return _start

## Gameplay hazards: [{type: "lava"|"water"|"spikes"|"debris", poly: PackedVector2Array (world),
## rect: Rect2, dps: float, slow: float (fraction of move speed removed), active: bool}].
## Spikes flip "active" on a cycle (glow warning first); "debris" zones deal damage through the
## debris_impact signal (extra keys: damage, radius). Use hazard_at() for a per-position query.
func get_hazards() -> Array:
	return _hazards

## Combined effect of the active hazards at a ground position: {dps, slow, types}.
## Void pits are obstacles (get_obstacles entries with a "pit" key), not hazards.
func hazard_at(pos: Vector2) -> Dictionary:
	var dps := 0.0
	var slow := 0.0
	var types: Array = []
	for h in _hazards:
		if not h["active"] or (h["dps"] <= 0.0 and h["slow"] <= 0.0):
			continue
		var rc: Rect2 = h["rect"]
		if not rc.has_point(pos):
			continue
		if Geometry2D.is_point_in_polygon(pos, h["poly"]):
			dps += h["dps"]
			slow = maxf(slow, h["slow"])
			types.append(h["type"])
	return {"dps": dps, "slow": slow, "types": types}

## Breakable props (urns, pots, ore barrels) still standing: [{id, pos, radius}].
func get_breakables() -> Array:
	var a: Array = []
	for b in _breakables:
		if not b["broken"]:
			a.append({"id": b["id"], "pos": b["pos"], "radius": b["radius"]})
	return a

## Shatters a breakable: removes its collision, plays shards, emits prop_broken. False if unknown / broken.
func break_prop(id: int) -> bool:
	for b in _breakables:
		if b["id"] != id or b["broken"]:
			continue
		b["broken"] = true
		_obstacles.erase(b["obstacle"])
		var n: Node2D = b["node"]
		if is_instance_valid(n):
			var spr: Sprite2D = n.get_meta("sprite")
			var sh := _particles(14, 0.9, _rock, Color.WHITE, 0)
			sh.one_shot = true
			sh.explosiveness = 0.95
			sh.preprocess = 0.0
			sh.position = Vector2(0, -40)
			sh.direction = Vector2(0, -1)
			sh.spread = 70.0
			sh.initial_velocity_min = 160.0
			sh.initial_velocity_max = 320.0
			sh.gravity = Vector2(0, 700)
			sh.angular_velocity_min = -360.0
			sh.angular_velocity_max = 360.0
			sh.scale_amount_min = 0.5
			sh.scale_amount_max = 1.2
			sh.color_ramp = null
			sh.color = Color(0.85, 0.8, 0.74)
			n.add_child(sh)
			sh.emitting = true
			var t := n.create_tween()
			if spr:
				t.tween_property(spr, "modulate:a", 0.0, 0.12)
			t.tween_interval(1.2)
			t.tween_callback(sh.queue_free)
		prop_broken.emit(id, b["pos"])
		return true
	return false

## Moves every y-sorted prop (pillars, statues, braziers...) into the lead's y-sorted entity layer.
## Idempotent; props are re-added automatically on later build() calls.
func add_ysorted_props_to(parent: Node2D) -> void:
	_ysort_parent = parent
	for p in _ysorted:
		if not is_instance_valid(p):
			continue
		if p.get_parent() == parent:
			continue
		if p.get_parent():
			p.get_parent().remove_child(p)
		parent.add_child(p)

## Clamp into the walkable island + push out of solid props and pits. Radius 0 probes (projectiles)
## ignore pits so shots fly over the void.
func resolve(pos: Vector2, radius: float) -> Vector2:
	if _legacy:
		var w := half.x - radius
		var hh := half.y - radius * 0.5
		var k := absf(pos.x) / w + absf(pos.y) / hh
		if k > 1.0:
			pos /= k
	else:
		pos = _clamp_island(pos, radius)
	for o in _obstacles:
		if radius <= 0.0 and o.has("pit"):
			continue
		var d: Vector2 = pos - o["pos"]
		d.y *= 2.0 # obstacles are flat ellipses on the iso floor
		var rr: float = o["radius"] + radius
		var l := d.length()
		if l < rr:
			if l < 0.001:
				d = Vector2(1, 0)
				l = 1.0
			d = d / l * rr
			d.y *= 0.5
			pos = o["pos"] + d
	return pos

## World rect the camera may show without leaving painted space (optional camera limits).
func get_camera_limits() -> Rect2:
	return Rect2(-vhalf.x - 700.0, -vhalf.y - wall_h, (vhalf.x + 700.0) * 2.0, vhalf.y * 2.0 + wall_h + 500.0)

## Optional low-end mode: plain backdrop (no mist shader), 3 shader lights, half the particles, no vignette,
## no heat shimmer (the only screen read), calmer water. Call after build(); persists for later builds.
func set_low_quality(on: bool) -> void:
	if on == _low:
		return
	_low = on
	_apply_low()

func _apply_low() -> void:
	var on := _low
	if _backdrop == null:
		return
	_backdrop.material = null if on else _void_mat
	if _vignette:
		_vignette.visible = not on
	for n in _base_amounts.keys():
		if is_instance_valid(n):
			n.amount = maxi(2, _base_amounts[n] / 2) if on else _base_amounts[n]
	_max_shader_lights = 3 if on else SHADER_LIGHTS
	if is_instance_valid(_heat):
		_heat.visible = not on
	for m in _water_mats:
		m.set_shader_parameter("lowq", 1.0 if on else 0.0)
	for r in _ripples:
		if is_instance_valid(r[0]):
			r[0].visible = not on

func get_room_title() -> String:
	if not _legacy:
		return _layout.get("name", theme.get("name", ""))
	return theme.get("name", "")

## "Chapter II: The Drowned Garden" etc. for a floor key (defaults to the current floor).
func get_chapter_title(p_floor_key := "") -> String:
	return CHAPTER_TITLES.get(_chapter_of(p_floor_key if p_floor_key != "" else floor_key), "")

func get_theme_id() -> String:
	return theme_id

## Number of layout variants for a floor key.
func get_layout_count(p_floor_key: String) -> int:
	if CHAPTER_LAYOUTS.has(p_floor_key):
		return CHAPTER_LAYOUTS[p_floor_key].size()
	return 4 if p_floor_key == "catacomb" else 1

func _chapter_of(k: String) -> String:
	if k == "throne":
		return "hollow"
	var base := k.trim_suffix("_boss")
	return base if CHAPTER_TITLES.has(base) else "catacomb"

# =============================================================== build helpers

func _clear() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	for p in _ysorted:
		if is_instance_valid(p):
			p.queue_free()
	_ysorted.clear()
	for c in get_children():
		c.queue_free()
	_obstacles.clear()
	_spawns.clear()
	_halos.clear()
	_swingers.clear()
	_silhouettes.clear()
	_occluders.clear()
	_cam_followers.clear()
	_wall_mats.clear()
	_water_mats.clear()
	_lights_a.clear()
	_lights_b.clear()
	_doors.clear()
	_icons.clear()
	_hazards.clear()
	_spike_nodes.clear()
	_debris_zones.clear()
	_breakables.clear()
	_pools.clear()
	_ripples.clear()
	_koi.clear()
	_floaters.clear()
	_bursts.clear()
	_bellows.clear()
	_heat_regions.clear()
	_base_amounts.clear()
	_heat = null
	_sigil_light = -1
	_vignette = null

func _tex(path: String) -> Texture2D:
	return load(ENV + path) as Texture2D

func _art(kind: String) -> Texture2D:
	if _legacy:
		var throne := floor_key == "throne"
		match kind:
			"abyss": return _tex("abyss_throne.webp" if throne else "abyss_catacomb.webp")
			"rim": return _tex("rim_throne.webp" if throne else "rim_catacomb.webp")
			"floor": return _tex("floor_throne.webp" if throne else "floor_catacomb.webp")
			"wall": return _tex("wall_throne.webp" if throne else "wall_catacomb.webp")
			"sigil": return _tex("sigil_%s.webp" % theme["sigil"])
	return _tex("%s/%s.webp" % [chapter, kind])

func _make_shared_textures() -> void:
	if _noise:
		return
	_noise = _tex("noise.png")
	_white = _solid_tex(8, 8, Color.WHITE)
	_dot = _radial(32, Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.0)
	_glow = _radial(128, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0), 0.0)
	_shadow = _radial(64, Color(0, 0, 0, 0.75), Color(0, 0, 0, 0), 0.25)
	_smoke = _radial(64, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0), 0.2)
	# petal: soft ellipse
	var img := Image.create(24, 12, false, Image.FORMAT_RGBA8)
	for y in range(12):
		for x in range(24):
			var d := Vector2((x - 11.5) / 12.0, (y - 5.5) / 6.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 3.0, 0, 1)))
	_petal = ImageTexture.create_from_image(img)
	# rock chip: irregular dark polygon
	var rimg := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in range(20):
		for x in range(20):
			var a := atan2(y - 9.5, x - 9.5)
			var rr := 8.0 + 2.0 * sin(a * 3.0) + 1.5 * cos(a * 5.0)
			var dd := Vector2(x - 9.5, y - 9.5).length()
			var shade := 0.5 + 0.3 * (1.0 - (y / 20.0))
			rimg.set_pixel(x, y, Color(shade, shade * 0.95, shade * 1.05, 1.0 if dd < rr else 0.0))
	_rock = ImageTexture.create_from_image(rimg)
	# ripple ring
	var gimg := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - absf(d - 0.85) / 0.1, 0.0, 1.0)
			gimg.set_pixel(x, y, Color(1, 1, 1, a * a))
	_ring = ImageTexture.create_from_image(gimg)

func _solid_tex(w: int, h: int, c: Color) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _radial(size: int, inner: Color, outer: Color, hold: float) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	if hold > 0.0:
		g.add_point(hold, inner)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t

func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

func _shader(name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/env_%s.gdshader" % name)
	return m

func _add_light(pos: Vector2, color: Color, radius: float, intensity: float, flicker: float) -> int:
	if _lights_a.size() >= MAX_LIGHTS:
		return -1
	_lights_a.append(Vector4(pos.x, pos.y, radius, intensity))
	_lights_b.append(Vector4(color.r, color.g, color.b, flicker))
	return _lights_a.size() - 1

## Culls lights to the camera view, applies flicker on the CPU and uploads at most SHADER_LIGHTS.
func _push_lights() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var c := cam.get_screen_center_position() if cam else Vector2.ZERO
	var ext := get_viewport_rect().size * 0.5 / (cam.zoom if cam else Vector2.ONE) if is_inside_tree() else Vector2(2000, 1000)
	var n := 0
	for i in range(_lights_a.size()):
		var la := _lights_a[i]
		if la.w <= 0.001:
			continue
		if absf(la.x - c.x) > ext.x + la.z or absf(la.y - c.y) > ext.y + la.z * 0.6:
			continue
		var lb := _lights_b[i]
		var fl := 1.0 - lb.w * (0.5 + 0.5 * sin(t * (6.3 + i * 1.7) + i * 2.1)) * (0.6 + 0.4 * sin(t * 13.1 + i))
		_sa[n] = Vector4(la.x, la.y, la.z, la.w * fl)
		_sb[n] = lb
		n += 1
		if n >= _max_shader_lights:
			break
	for m in _wall_mats:
		m.set_shader_parameter("light_count", n)
		m.set_shader_parameter("light_a", _sa)
		m.set_shader_parameter("light_b", _sb)
	if _floor_mat:
		_floor_mat.set_shader_parameter("light_count", n)
		_floor_mat.set_shader_parameter("light_a", _sa)
		_floor_mat.set_shader_parameter("light_b", _sb)

func _apply_dynamic() -> void:
	if _floor_mat:
		_floor_mat.set_shader_parameter("sigil_lit", _lit)
		_floor_mat.set_shader_parameter("sigil_wave", _wave)
	for d in _doors:
		var gm: ShaderMaterial = d["mat"]
		gm.set_shader_parameter("open_t", _door_t)
		gm.set_shader_parameter("glow", _door_t)
		d["rays"].modulate.a = _door_t
		var li: int = d["light"]
		if li >= 0:
			var v := _lights_a[li]
			_lights_a[li] = Vector4(v.x, v.y, v.z, 1.5 * _door_t)
	if _sigil_light >= 0:
		var s := _lights_a[_sigil_light]
		_lights_a[_sigil_light] = Vector4(s.x, s.y, s.z, 0.15 + 0.55 * _lit)
	_push_lights()

# --------------------------------------------------------------- island outline + walkable area
func _build_island() -> void:
	var sh: Dictionary = SHAPES[_layout.get("shape", "diamond")]
	_wl = sh["wl"]
	_wr = sh["wr"]
	var T := Vector2(0, -vhalf.y)
	var lp := T.lerp(Vector2(-vhalf.x, 0), _wl)
	var rp := T.lerp(Vector2(vhalf.x, 0), _wr)
	var pts := PackedVector2Array([lp, T, rp])
	if _legacy:
		pts.append(Vector2(0, vhalf.y))
	else:
		var chain: Array = [rp]
		for p in sh["front"]:
			chain.append(Vector2(p[0] * vhalf.x, p[1] * vhalf.y))
		chain.append(lp)
		var ph := _rng.randf() * 10.0
		for i in range(chain.size() - 1):
			var a: Vector2 = chain[i]
			var b: Vector2 = chain[i + 1]
			var steps := maxi(2, int(a.distance_to(b) / 60.0))
			var nrm := (b - a).orthogonal().normalized()
			for s in range(1 if i == 0 else 0, steps):
				var t := float(s) / steps
				var p := a.lerp(b, t)
				var fade := 1.0
				if i == 0:
					fade = clampf(t * 4.0, 0.0, 1.0)
				elif i == chain.size() - 2:
					fade = clampf((1.0 - t) * 4.0, 0.0, 1.0)
				var j := (sin(p.x * 0.013 + ph) * 0.6 + sin(p.y * 0.031 + ph * 2.0) * 0.4) * 24.0 + _rng.randf_range(-9.0, 9.0)
				pts.append(p + nrm * j * fade)
	_island = pts
	if _legacy:
		_start = Vector2(0, half.y * 0.6)
		_walk = PackedVector2Array([Vector2(-half.x, 0), Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y)])
		_walk_g = PackedVector2Array()
		return
	# walkable: inset by the same margin as the classic diamond
	var best := PackedVector2Array()
	var best_a := 0.0
	for poly in Geometry2D.offset_polygon(_island, -86.0, Geometry2D.JOIN_ROUND):
		var a := absf(_poly_area(poly))
		if a > best_a:
			best_a = a
			best = poly
	_walk = _simplify(best, 18.0)
	_walk_g = PackedVector2Array()
	for p in _walk:
		_walk_g.append(Vector2(p.x, p.y * 2.0))
	_build_deep_grid()
	var st: Array = sh["start"]
	_start = _clamp_island(Vector2(st[0] * half.x, st[1] * half.y), 60.0)

func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(p.size()):
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5

func _simplify(p: PackedVector2Array, min_d: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for q in p:
		if o.is_empty() or o[o.size() - 1].distance_to(q) >= min_d:
			o.append(q)
	return o

## Outward unit normal of island edge a->b (robust to winding and concave notches).
func _outward(a: Vector2, b: Vector2) -> Vector2:
	var n := (b - a).orthogonal().normalized()
	if Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 4.0, _island):
		n = -n
	return n

## Coarse grid of cells lying more than 70 px (ground space) inside the walkable outline: resolve()
## skips the polygon test there, which covers most calls.
func _build_deep_grid() -> void:
	_deep_org = Vector2(-vhalf.x, -vhalf.y)
	_deep_w = int(ceil(vhalf.x * 2.0 / _deep_cell))
	_deep_h = int(ceil(vhalf.y * 2.0 / _deep_cell))
	_deep = PackedByteArray()
	_deep.resize(_deep_w * _deep_h)
	for j in range(_deep_h):
		for i in range(_deep_w):
			var c := _deep_org + Vector2((i + 0.5) * _deep_cell, (j + 0.5) * _deep_cell)
			var ok := Geometry2D.is_point_in_polygon(c, _walk)
			if ok:
				ok = _edge_dist_g(Vector2(c.x, c.y * 2.0)) > 70.0 + _deep_cell * 1.2
			_deep[j * _deep_w + i] = 1 if ok else 0

func _edge_dist_g(g: Vector2) -> float:
	var best := INF
	var n := _walk_g.size()
	for i in range(n):
		var q := Geometry2D.get_closest_point_to_segment(g, _walk_g[i], _walk_g[(i + 1) % n])
		best = minf(best, g.distance_squared_to(q))
	return sqrt(best)

func _clamp_island(pos: Vector2, radius: float) -> Vector2:
	if _walk_g.size() < 3:
		return pos
	var i := int(floor((pos.x - _deep_org.x) / _deep_cell))
	var j := int(floor((pos.y - _deep_org.y) / _deep_cell))
	if radius <= 70.0 and i >= 0 and j >= 0 and i < _deep_w and j < _deep_h and _deep[j * _deep_w + i] == 1:
		return pos
	for _it in range(2):
		var g := Vector2(pos.x, pos.y * 2.0)
		var inside := Geometry2D.is_point_in_polygon(g, _walk_g)
		var best := INF
		var bq := g
		var n := _walk_g.size()
		for k in range(n):
			var q := Geometry2D.get_closest_point_to_segment(g, _walk_g[k], _walk_g[(k + 1) % n])
			var d := g.distance_squared_to(q)
			if d < best:
				best = d
				bq = q
		var dist := sqrt(best)
		if inside and dist >= radius:
			return pos
		var dir := (g - bq) / maxf(dist, 0.001)
		if not inside:
			dir = -dir
		if dist < 0.001:
			dir = -g.normalized()
		g = bq + dir * maxf(radius, 0.5)
		pos = Vector2(g.x, g.y * 0.5)
	return pos

func _inside_island(p: Vector2, margin := 0.0) -> bool:
	if _legacy:
		return absf(p.x) / half.x + absf(p.y) / half.y < 1.05 - margin / half.x
	if not Geometry2D.is_point_in_polygon(p, _walk):
		return false
	return margin <= 0.0 or _edge_dist_g(Vector2(p.x, p.y * 2.0)) >= margin

# --------------------------------------------------------------- backdrop / void
func _build_backdrop() -> void:
	_backdrop = Sprite2D.new()
	_backdrop.texture = _art("abyss")
	_backdrop.z_index = -100
	_backdrop.scale = Vector2.ONE * 1.8
	_void_mat = _shader("void")
	_void_mat.set_shader_parameter("noise_tex", _noise)
	_void_mat.set_shader_parameter("mist_color", theme["mist"])
	_void_mat.set_shader_parameter("mist", 0.4)
	_void_mat.set_shader_parameter("flash_color", Color(0.55, 0.72, 1.0))
	if _legacy:
		_void_mat.set_shader_parameter("darken", 0.8 if floor_key == "throne" else 0.72)
		_void_mat.set_shader_parameter("stars", 0.9 if theme_id == "regent" else 0.0)
		_void_mat.set_shader_parameter("caustics", 0.45 if theme_id == "mireth" else 0.0)
	else:
		_void_mat.set_shader_parameter("darken", theme["void_dark"])
		_void_mat.set_shader_parameter("stars", theme["void_stars"])
		_void_mat.set_shader_parameter("caustics", theme["void_caustics"])
		_void_mat.set_shader_parameter("caustic_color", theme["light"])
	_backdrop.material = _void_mat
	add_child(_backdrop)

# --------------------------------------------------------------- ledges
func _build_rims() -> void:
	var tex := _art("rim")
	var depth := 520.0 if (floor_key == "throne" or floor_key.ends_with("_boss")) else 430.0
	var rep_w := float(tex.get_width()) * depth / float(tex.get_height())
	var ts := tex.get_size() # Polygon2D UVs are in texture pixels
	# front-facing runs of the island outline get a painted cliff face hanging into the void
	var n := _island.size()
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var polys: Array = []
	var u := 0.0
	var prev_ok := false
	for i in range(n):
		var a := _island[i]
		var b := _island[(i + 1) % n]
		var nrm := _outward(a, b)
		if nrm.y <= 0.05:
			prev_ok = false
			continue
		if not prev_ok and not _legacy:
			u = _rng.randf() * 2.0
		var shade := lerpf(0.62, 0.86, clampf(0.5 - nrm.x * 0.7, 0.0, 1.0))
		var d0 := depth
		var d1 := depth
		if not _legacy:
			d0 *= 0.9 + 0.2 * sin(a.x * 0.01)
			d1 *= 0.9 + 0.2 * sin(b.x * 0.01)
		var u1 := u + a.distance_to(b) / rep_w
		var k := verts.size()
		verts.append_array([a, b, b + Vector2(0, d1), a + Vector2(0, d0)])
		uvs.append_array([Vector2(u, 0) * ts, Vector2(u1, 0) * ts, Vector2(u1, 1) * ts, Vector2(u, 1) * ts])
		var c := Color(shade, shade, shade, clampf(nrm.y * 1.4, 0.0, 1.0))
		cols.append_array([c, c, c, c])
		polys.append(PackedInt32Array([k, k + 1, k + 2, k + 3]))
		u = u1
		prev_ok = true
	var p := Polygon2D.new()
	p.polygon = verts
	p.uv = uvs
	p.vertex_colors = cols
	p.polygons = polys
	p.texture = tex
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	p.z_index = -80
	var m := _shader("rim")
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("shade", 1.0)
	if _legacy:
		m.set_shader_parameter("glow_key", Color(0.65, 0.3, 1.0))
		m.set_shader_parameter("glow_strength", 0.6 if floor_key == "throne" else 0.0)
	else:
		m.set_shader_parameter("glow_key", theme["wall_glow"])
		m.set_shader_parameter("glow_strength", 0.5)
		m.set_shader_parameter("rim_light", 0.55)
		m.set_shader_parameter("rim_color", theme["rim_light"])
	m.set_shader_parameter("abyss_color", Color(theme["mist"]).darkened(0.8))
	p.material = m
	add_child(p)

# --------------------------------------------------------------- floor
func _build_floor() -> void:
	var p := Polygon2D.new()
	p.polygon = _island
	p.z_index = -70
	_floor_mat = _shader("floor")
	var throne := floor_key == "throne"
	_floor_mat.set_shader_parameter("atlas", _art("floor"))
	_floor_mat.set_shader_parameter("noise_tex", _noise)
	_floor_mat.set_shader_parameter("sigil_tex", _art("sigil"))
	_floor_mat.set_shader_parameter("iso", Vector2(104.0, 104.0 * half.y / half.x))
	_floor_mat.set_shader_parameter("half_size", vhalf)
	var sc := Vector2(0, -half.y * 0.02)
	var sr := 470.0
	if _legacy:
		_floor_mat.set_shader_parameter("inset", 0.004 if throne else 0.006)
		_floor_mat.set_shader_parameter("seam_color", Color(0.55, 0.42, 0.22, 0.35) if throne else Color(0.85, 0.66, 0.3, 0.8))
		_floor_mat.set_shader_parameter("seam_width", 0.006 if throne else 0.013)
		_floor_mat.set_shader_parameter("tint", Color(1.3, 1.2, 1.35) if throne else theme["tint"])
		_floor_mat.set_shader_parameter("grime", Color(0.12, 0.08, 0.16, 1.0) if throne else Color(0.09, 0.15, 0.1, 1.0))
		_floor_mat.set_shader_parameter("ambient", 0.95 if throne else 0.7)
		_floor_mat.set_shader_parameter("fog_amount", 0.2)
		if theme_id == "mireth":
			sc = Vector2(0, -half.y * 0.06)
			sr = 420.0
		elif theme_id == "regent":
			sc = Vector2(0, half.y * 0.04)
			sr = 560.0
	else:
		_floor_mat.set_shader_parameter("inset", 0.006)
		_floor_mat.set_shader_parameter("seam_color", theme["seam"])
		_floor_mat.set_shader_parameter("seam_width", theme["seam_w"])
		_floor_mat.set_shader_parameter("tint", theme["tint"])
		_floor_mat.set_shader_parameter("grime", theme["grime"])
		_floor_mat.set_shader_parameter("ambient", theme["ambient"])
		_floor_mat.set_shader_parameter("fog_amount", theme["fog_amount"])
		_floor_mat.set_shader_parameter("checker", theme.get("checker", 0.0))
		sr = theme["sigil_r"] * (1.2 if floor_key.ends_with("_boss") else 1.0)
		sc = _sigil_spot()
	_floor_mat.set_shader_parameter("seam_ink", 0.008)
	_floor_mat.set_shader_parameter("sigil_center", sc)
	_floor_mat.set_shader_parameter("sigil_radius", sr)
	_floor_mat.set_shader_parameter("sigil_color", theme["sigil_color"])
	_floor_mat.set_shader_parameter("sigil_base", 0.42)
	_floor_mat.set_shader_parameter("sigil_lit", 0.0)
	_floor_mat.set_shader_parameter("sigil_wave", 1.0)
	_floor_mat.set_shader_parameter("fog_color", theme["fog"])
	p.material = _floor_mat
	add_child(p)
	_sigil_light = _add_light(sc, theme["sigil_color"], sr * 1.25, 0.15, 0.0)
	if not _legacy:
		_build_edge_shade()

## Keeps the sigil off pools and pits: the centre, unless something occupies it.
func _sigil_spot() -> Vector2:
	var c := Vector2(0, -half.y * 0.02)
	for key in ["water", "lava", "pits"]:
		for w in _layout.get(key, []):
			var p := Vector2(w[0] * half.x, w[1] * half.y)
			if p.distance_to(c) < w[2] + 120.0:
				var alt := Vector2(0, half.y * 0.34)
				return alt if Geometry2D.is_point_in_polygon(alt, _walk) else Vector2(0, -half.y * 0.42)
	return c

## Ambient occlusion inside the island's front edges, and a lit lip along them (rim light).
func _build_edge_shade() -> void:
	var n := _island.size()
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var polys: Array = []
	var lip := PackedVector2Array()
	for i in range(n):
		var a := _island[i]
		var b := _island[(i + 1) % n]
		var nrm := _outward(a, b)
		if nrm.y <= 0.05:
			if lip.size() > 1:
				_lip_line(lip)
			lip = PackedVector2Array()
			continue
		var w := 90.0
		var k := verts.size()
		verts.append_array([a, b, b - nrm * w, a - nrm * w])
		var c0 := Color(0, 0, 0, 0.5)
		var c1 := Color(0, 0, 0, 0)
		cols.append_array([c0, c0, c1, c1])
		polys.append(PackedInt32Array([k, k + 1, k + 2, k + 3]))
		if lip.is_empty():
			lip.append(a)
		lip.append(b)
	if lip.size() > 1:
		_lip_line(lip)
	var s := Polygon2D.new()
	s.polygon = verts
	s.vertex_colors = cols
	s.polygons = polys
	s.z_index = -69
	add_child(s)

func _lip_line(pts: PackedVector2Array) -> void:
	var l := Line2D.new()
	l.points = pts
	l.width = 5.0
	l.default_color = Color(theme["rim_light"], 0.45)
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.material = _additive()
	l.z_index = -69
	add_child(l)

# --------------------------------------------------------------- walls
func _build_walls() -> void:
	var throne := floor_key == "throne"
	var tex := _art("wall")
	var rep_w := float(tex.get_width()) * wall_h / float(tex.get_height())
	var T := Vector2(0, -vhalf.y)
	var L := T.lerp(Vector2(-vhalf.x, 0), _wl)
	var R := T.lerp(Vector2(vhalf.x, 0), _wr)
	var up := Vector2(0, -wall_h)
	var off := _rng.randf() * 0.5
	for side in [[L, T, 0.95, Vector2(0.12, 0.0)], [T, R, 0.7, Vector2(0.0, 0.12)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var u0 := off
		var u1 := off + a.distance_to(b) / rep_w
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([a + up, b + up, b, a])
		var ts := tex.get_size() # Polygon2D UVs are in texture pixels
		p.uv = PackedVector2Array([Vector2(u0, 0) * ts, Vector2(u1, 0) * ts, Vector2(u1, 1) * ts, Vector2(u0, 1) * ts])
		p.texture = tex
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		p.z_index = -60
		var m := _shader("wall")
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("noise_tex", _noise)
		m.set_shader_parameter("shade", side[2])
		m.set_shader_parameter("span", u1)
		m.set_shader_parameter("u_start", u0)
		m.set_shader_parameter("end_fade", side[3])
		m.set_shader_parameter("top_dark", 0.32)
		if _legacy:
			m.set_shader_parameter("glow_key", Color(0.45, 0.3, 1.0))
			m.set_shader_parameter("glow_strength", 0.55 if throne else 0.0)
		else:
			m.set_shader_parameter("glow_key", theme["wall_glow"])
			m.set_shader_parameter("glow_strength", theme["wall_glow_k"])
		m.set_shader_parameter("ambient", 0.8)
		p.material = m
		add_child(p)
		_wall_mats.append(m)
	# skirting shadow where walls meet the floor
	var s := Polygon2D.new()
	var d := 46.0
	s.polygon = PackedVector2Array([L, T, R, R + Vector2(-d * 2.0, 0), T + Vector2(0, d), L + Vector2(d * 2.0, 0)])
	s.vertex_colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)])
	s.z_index = -69
	add_child(s)
	# banners hung on the walls (classic catacombs; the chapter walls have theirs painted in)
	if _legacy and not throne:
		var banner := _tex("props/banner.png")
		for t in [0.32, 0.68]:
			if _exits == 2 and t > 0.5:
				continue
			_wall_banner(banner, L, T, t, 0.55)
			_wall_banner(banner, T, R, 1.0 - t, 0.55)

func _wall_banner(tex: Texture2D, a: Vector2, b: Vector2, t: float, height_frac: float) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, 0)
	var sc := 150.0 / tex.get_width()
	s.scale = Vector2(sc, sc)
	var dir := (b - a).normalized()
	var ang := dir.angle()
	s.rotation = ang
	s.skew = -ang
	s.position = a.lerp(b, t) + Vector2(0, -wall_h * height_frac - 120.0)
	s.z_index = -58
	s.modulate = Color(0.85, 0.82, 0.85) if b.x <= 0.0 else Color(0.65, 0.62, 0.68)
	var m := _shader("sway")
	m.set_shader_parameter("amp", 5.0)
	m.set_shader_parameter("seed", _rng.randf() * 10.0)
	s.material = m
	add_child(s)

# --------------------------------------------------------------- gates
func _build_gates() -> void:
	if _exits <= 0:
		return
	if _exits == 1:
		_gate_at(Vector2(0, -vhalf.y + 40.0), 0.0, 400.0, Vector2(0, 1), Vector2(0, -half.y + 70.0))
		return
	# one gate on each back wall, sheared onto the wall plane
	var T := Vector2(0, -vhalf.y)
	for b in [T.lerp(Vector2(-vhalf.x, 0), _wl), T.lerp(Vector2(vhalf.x, 0), _wr)]:
		var dir: Vector2 = (b - T).normalized()
		var base := T + dir * (vhalf.length() * 0.42) + Vector2(0, 24.0)
		var ang := (dir if dir.x > 0.0 else -dir).angle()
		var inward := Vector2(-dir.y, dir.x)
		if inward.dot(-base) < 0.0:
			inward = -inward
		_gate_at(base, ang, 320.0, inward, base + inward * 125.0)

func _gate_at(base: Vector2, ang: float, width: float, inward: Vector2, floor_pos: Vector2) -> void:
	var tex := _tex("gate_closed.png")
	var sc := width / tex.get_width()
	var gate := Sprite2D.new()
	gate.texture = tex
	gate.centered = false
	gate.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	gate.scale = Vector2(sc, sc)
	gate.rotation = ang
	gate.skew = -ang
	gate.position = base
	gate.z_index = -55
	var mat := _shader("gate")
	mat.set_shader_parameter("open_tex", _tex("gate_open.png"))
	mat.set_shader_parameter("mask_tex", _tex("gate_mask.png"))
	mat.set_shader_parameter("open_t", 0.0)
	gate.material = mat
	if not _legacy:
		gate.modulate = theme["gate_tint"]
	add_child(gate)
	# threshold shadow under the gate
	var sh := Sprite2D.new()
	sh.texture = _shadow
	sh.position = base + Vector2(0, -6)
	sh.rotation = ang
	sh.scale = Vector2(width * 1.1 / 64.0, 70.0 / 64.0)
	sh.z_index = -56
	add_child(sh)
	# light rays spilling out onto the floor (additive, vertex-colour fade)
	var along := Vector2(cos(ang), sin(ang))
	var inw := inward.normalized()
	var o := base + Vector2(0, -8.0) - inw * 40.0
	var rays := Polygon2D.new()
	var warm := Color(1.0, 0.86, 0.6) if _legacy else Color(1.0, 0.86, 0.6).lerp(theme["light"], 0.35)
	var hw := width * 0.26
	var far := 340.0
	rays.polygon = PackedVector2Array([o - along * hw, o, o + along * hw, o + along * hw * 3.1 + inw * far, o + inw * (far + 40.0), o - along * hw * 3.1 + inw * far])
	rays.vertex_colors = PackedColorArray([Color(warm, 0.0), Color(warm, 0.42), Color(warm, 0.0), Color(warm, 0.0), Color(warm, 0.0), Color(warm, 0.0)])
	rays.polygons = [PackedInt32Array([0, 1, 4, 5]), PackedInt32Array([1, 2, 3, 4])]
	rays.material = _additive()
	rays.z_index = -54
	rays.modulate.a = 0.0
	add_child(rays)
	var light := _add_light(base + inw * 100.0, Color(1.0, 0.85, 0.6), 520.0, 0.0, 0.05)
	# motes drifting out of the open gate
	var motes := _particles(28, 2.6, _dot, Color(1.0, 0.9, 0.65), 1)
	motes.position = base + Vector2(0, -120)
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(90, 110)
	motes.direction = inw
	motes.spread = 40.0
	motes.initial_velocity_min = 20.0
	motes.initial_velocity_max = 70.0
	motes.gravity = Vector2(0, -6)
	motes.scale_amount_min = 0.12
	motes.scale_amount_max = 0.3
	motes.z_index = -53
	motes.emitting = false
	add_child(motes)
	var top := base + Vector2(0, -tex.get_height() * sc - 80.0)
	_doors.append({"pos": floor_pos, "gate": gate, "mat": mat, "rays": rays, "motes": motes, "light": light, "top": top, "base": base})

# --------------------------------------------------------------- props
func _uv(u: float, v: float) -> Vector2:
	return Vector2(u * half.x, v * half.y)

func _build_layout() -> void:
	# frame pillars at the side corners and flanking the gate (outside the playable area)
	_prop("pillar_big", Vector2(-vhalf.x + 30.0, -10.0))
	_prop("pillar_big", Vector2(vhalf.x - 30.0, -10.0))
	if _exits == 1:
		var k := 290.0
		_prop("pillar_frame", Vector2(-k, -vhalf.y + k * vhalf.y / vhalf.x + 6.0))
		_prop("pillar_frame", Vector2(k, -vhalf.y + k * vhalf.y / vhalf.x + 6.0))
	elif _exits == 0:
		_prop("pillar_frame", Vector2(-330, -vhalf.y + 330.0 * vhalf.y / vhalf.x + 6.0))
		_prop("pillar_frame", Vector2(330, -vhalf.y + 330.0 * vhalf.y / vhalf.x + 6.0))
	for e in LAYOUTS[theme_id]:
		_prop(e[0], _uv(e[1], e[2]))
	# lanterns hanging from the vault
	var lpos := [Vector2(-0.18, -0.25), Vector2(0.55, 0.22), Vector2(-0.6, 0.3)]
	for i in range(2 if floor_key == "throne" else 3):
		var lp: Vector2 = lpos[i]
		_lantern(_uv(lp.x, lp.y))

func _build_chapter_layout() -> void:
	var lay := _layout
	var T := Vector2(0, -vhalf.y)
	var L := T.lerp(Vector2(-vhalf.x, 0), _wl)
	var R := T.lerp(Vector2(vhalf.x, 0), _wr)
	# frame pieces at the wall ends and the back corner (decor only, outside the playable area)
	var frame: Array = {"garden": ["willow", "g_arch"], "forge": ["chainpost", "furnace"], "hollow": ["h_statue", "standard"]}[chapter]
	_prop(frame[0], L + Vector2(50.0, 14.0), true)
	_prop(frame[0], R + Vector2(-50.0, 14.0), true)
	if _exits != 1:
		_prop(frame[1], T + Vector2(0, 70.0), true)
	else:
		_prop(frame[1], T.lerp(L, 0.34) + Vector2(16, 40), true)
		_prop(frame[1], T.lerp(R, 0.34) + Vector2(-16, 40), true)
	# set pieces first: they claim lights before the props do
	for w in lay.get("water", []):
		_water_pool(_uv(w[0], w[1]), w[2])
	for w in lay.get("lava", []):
		_lava_pool(_uv(w[0], w[1]), w[2])
	for c in lay.get("channels", []):
		var pts := PackedVector2Array()
		for q in c:
			pts.append(_uv(q[0], q[1]))
		_lava_channel(pts, 62.0)
	for w in lay.get("pits", []):
		_pit(_uv(w[0], w[1]), w[2])
	for s in lay.get("spikes", []):
		_spike_trap(_uv(s[0], s[1]))
	for d in lay.get("debris", []):
		_debris_zone(_uv(d[0], d[1]), d[2])
	_build_heat()
	# never start the player inside water, lava, a trap or a debris zone
	if _start_blocked(_start):
		var found := false
		for ring in range(1, 10):
			for k in range(12):
				var a := PI * 0.5 + (k / 2 + 0.5) * (1 if k % 2 == 0 else -1) * TAU / 12.0
				var q := _start + Vector2(cos(a), sin(a) * 0.5) * ring * 40.0
				if _inside_island(q, 60.0) and not _start_blocked(q):
					_start = q
					found = true
					break
			if found:
				break
	for e in lay.get("props", []):
		var kinds: PackedStringArray = String(e[0]).split("|")
		var kind := kinds[_rng.randi() % kinds.size()]
		var jit := 0.0 if (e.size() > 3 and e[3] == 0) else 0.035
		var pp := _free_spot(_uv(e[1] + _rng.randf_range(-jit, jit), e[2] + _rng.randf_range(-jit, jit)), PROPS[kind]["r"])
		if pp.x < INF:
			_prop(kind, pp)
	# a seeded subset of the breakables (2 to 4)
	var br: Array = lay.get("breakables", []).duplicate()
	for i in range(br.size()):
		var j := _rng.randi_range(i, br.size() - 1)
		var tmp = br[i]
		br[i] = br[j]
		br[j] = tmp
	for i in range(mini(br.size(), 2 + _rng.randi() % 3)):
		var b: Array = br[i]
		var bp := _free_spot(_uv(b[1] + _rng.randf_range(-0.03, 0.03), b[2] + _rng.randf_range(-0.03, 0.03)), PROPS[b[0]]["r"])
		if bp.x < INF:
			_prop(b[0], bp)
	if chapter == "garden":
		var lpos := [Vector2(-0.2, -0.22), Vector2(0.56, 0.2), Vector2(-0.58, 0.3)]
		for i in range(2 if floor_key.ends_with("_boss") else 3):
			var lp := _free_spot(_uv(lpos[i].x, lpos[i].y), 30.0)
			if lp.x < INF:
				_lantern(lp)
	# floating palace debris drifting past the island's front edges
	if chapter == "hollow":
		var cnt := 6 if floor_key.ends_with("_boss") else 4
		for i in range(cnt):
			var a := PI * (0.06 + 0.88 * (i + _rng.randf_range(0.2, 0.8)) / cnt)
			_floater(Vector2(cos(a) * vhalf.x * 1.1, sin(a) * vhalf.y * 1.1 + 90.0))

## True when a prop of ground radius r may stand at pos: on the island, clear of hazards, pits,
## the player start, the exits and the props already placed.
func _spot_ok(pos: Vector2, r: float, on_walk := false) -> bool:
	if not Geometry2D.is_point_in_polygon(pos, _island):
		return false
	if on_walk and not _inside_island(pos, 10.0):
		return false
	if pos.distance_to(_start) < r + 120.0:
		return false
	for d in _doors:
		if pos.distance_to(d["pos"]) < r + 130.0:
			return false
	for h in _hazards:
		var rc: Rect2 = h["rect"]
		if rc.grow(r + 48.0).has_point(pos):
			var poly: PackedVector2Array = h["poly"]
			if Geometry2D.is_point_in_polygon(pos, poly):
				return false
			for i in range(poly.size()):
				var q := Geometry2D.get_closest_point_to_segment(pos, poly[i], poly[(i + 1) % poly.size()])
				var dq := q - pos
				if Vector2(dq.x, dq.y * 2.0).length() < r + (44.0 if h["type"] == "lava" else 14.0):
					return false
	for o in _obstacles:
		var dv: Vector2 = o["pos"] - pos
		if Vector2(dv.x, dv.y * 2.0).length() < float(o["radius"]) + r + 10.0:
			return false
	return true

func _start_blocked(q: Vector2) -> bool:
	for h in _hazards:
		var rc: Rect2 = h["rect"]
		if rc.grow(70.0).has_point(q):
			return true
	for o in _obstacles:
		if o.get("pit", false) and q.distance_to(o["pos"]) < o["radius"] + 80.0:
			return true
	return false

## The nearest acceptable spot around pos (spiral search), or Vector2(INF, INF).
func _free_spot(pos: Vector2, r: float) -> Vector2:
	# a prop laid out on the walkable floor stays on it (so it remains a collider); edge decor may sit on the rim
	var on_walk := _inside_island(pos)
	if _spot_ok(pos, r, on_walk):
		return pos
	for ring in range(1, 7):
		var rad := ring * 34.0
		var n := 6 + ring * 2
		var a0 := _rng.randf() * TAU
		for k in range(n):
			var a := a0 + TAU * k / n
			var q := pos + Vector2(cos(a), sin(a) * 0.5) * rad
			if _spot_ok(q, r, on_walk):
				return q
	return Vector2(INF, INF)

func _prop(kind: String, pos: Vector2, frame := false) -> Node2D:
	var d: Dictionary = PROPS[kind]
	var tex := _tex(d["tex"])
	var root := Node2D.new()
	root.position = pos
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var th := float(tex.get_height())
	var h: float = d["h"] * (1.2 if frame else 1.0)
	var sc: float = h / th
	# contact shadow
	var sh := Sprite2D.new()
	sh.texture = _shadow
	sh.scale = Vector2(d["shadow"] / 64.0, d["shadow"] * 0.42 / 64.0)
	sh.z_index = -1
	root.add_child(sh)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -th * (1.0 - d["foot"]))
	s.scale = Vector2(sc, sc)
	if _rng.randf() < 0.5 and (kind in ["urns", "skulls", "broken_column", "crystals", "brazier"] or d.get("flip", false)):
		s.scale.x = -sc
	root.add_child(s)
	root.set_meta("sprite", s)
	if floor_key == "throne" and kind.begins_with("pillar"):
		s.modulate = Color(0.78, 0.66, 0.95) # violet-stained marble in the Regent's hall
	if frame:
		s.modulate = Color(0.74, 0.72, 0.8)
	var r: float = d["r"]
	if r > 0.0 and not frame and _inside_island(pos):
		var ob := {"pos": pos, "radius": r}
		_obstacles.append(ob)
		if d.get("break", false):
			_breakables.append({"id": _breakables.size(), "pos": pos, "radius": r, "node": root, "obstacle": ob, "broken": false})
	var fc: Array = theme["flame"]
	match kind:
		"brazier":
			_fire(root, Vector2(0, -d["h"] * 0.86), Vector2(62, 96), 1.0)
			_add_light(pos + Vector2(0, 10), theme["light"], 430.0, 0.95, 0.35)
			_embers(root, Vector2(0, -d["h"] * 0.95))
		"statue_oriel":
			_halo(root, Vector2(-d["h"] * 0.21, -d["h"] * 0.93), 120.0, Color(1.0, 0.6, 0.25), 0.55)
			_fire(root, Vector2(-d["h"] * 0.215, -d["h"] * 0.9), Vector2(26, 40), 0.8)
		"candelabra":
			_halo(root, Vector2(0, -d["h"] * 0.82), 210.0, theme["light"].lerp(Color(1, 0.8, 0.5), 0.5), 0.5)
			_add_light(pos, Color(1.0, 0.75, 0.45), 300.0, 0.6, 0.25)
		"crystals":
			_halo(root, Vector2(0, -d["h"] * 0.5), 260.0, Color(0.7, 0.4, 1.0), 0.38)
		"throne":
			_halo(root, Vector2(0, -d["h"] * 0.55), 620.0, Color(0.6, 0.35, 1.0), 0.32)
		"statue_mireth":
			_halo(root, Vector2(d["h"] * 0.05, -d["h"] * 0.25), 220.0, Color(0.4, 0.9, 1.0), 0.35)
		# ---------------- garden
		"fountain":
			_halo(root, Vector2(0, -h * 0.5), 420.0, theme["light"], 0.32)
			_add_light(pos + Vector2(0, 30), theme["light"], 520.0, 0.8, 0.08)
			var sp := _particles(16, 1.4, _dot, Color(0.7, 1.0, 0.95), 1)
			sp.position = Vector2(0, -h * 0.8)
			sp.direction = Vector2(0, -1)
			sp.spread = 60.0
			sp.initial_velocity_min = 40.0
			sp.initial_velocity_max = 90.0
			sp.gravity = Vector2(0, 160)
			sp.scale_amount_min = 0.08
			sp.scale_amount_max = 0.16
			root.add_child(sp)
		"g_lantern":
			if not frame:
				_halo(root, Vector2(0, -h * 0.74), 200.0, theme["light"], 0.55)
				_add_light(pos + Vector2(0, 10), theme["light"], 380.0, 0.8, 0.2)
		"willow":
			_halo(root, Vector2(-h * 0.12, -h * 0.42), 150.0, theme["light"], 0.28)
			_halo(root, Vector2(h * 0.14, -h * 0.42), 130.0, theme["light"], 0.28)
			_swingers.append([s, _rng.randf() * TAU, 0.012])
		"reeds":
			_halo(root, Vector2(0, -h * 0.3), 120.0, Color(0.4, 0.8, 1.0), 0.25)
		# ---------------- forge
		"anvil":
			var sp := _spark_burst(root, Vector2(-h * 0.1, -h * 0.66))
			_bursts.append([sp, _rng.randf_range(1.6, 2.6), _rng.randf() * 2.0])
			_halo(root, Vector2(-h * 0.1, -h * 0.66), 120.0, fc[1], 0.4)
		"crucible":
			_halo(root, Vector2(0, -h * 0.82), 220.0, fc[1], 0.6)
			_add_light(pos + Vector2(0, 10), theme["light"], 420.0, 1.0, 0.25)
			_smoke_column(root, Vector2(0, -h * 0.9), 0.6)
			_embers(root, Vector2(0, -h * 0.85))
		"furnace":
			if not frame:
				_fire(root, Vector2(-h * 0.13, -h * 0.17), Vector2(70, 80), 0.9)
				_add_light(pos + Vector2(-30, 40), theme["light"], 480.0, 1.0, 0.3)
			_smoke_column(root, Vector2(0, -h * 0.98), 1.0)
		"bellows":
			_bellows.append([s, s.scale, _rng.randf() * TAU])
		"rack":
			_halo(root, Vector2(0, -h * 0.5), 160.0, fc[1], 0.3)
		"barrel":
			_halo(root, Vector2(0, -h * 0.9), 90.0, fc[1], 0.45)
		# ---------------- hollow
		"h_brazier":
			_fire(root, Vector2(0, -h * 0.86), Vector2(54, 88), 1.0)
			_add_light(pos + Vector2(0, 10), theme["light"], 430.0, 0.95, 0.3)
			_embers(root, Vector2(0, -h * 0.95))
		"h_candelabra":
			_halo(root, Vector2(0, -h * 0.8), 230.0, theme["light"], 0.5)
			_add_light(pos, theme["light"], 300.0, 0.6, 0.25)
		"obelisk":
			_halo(root, Vector2(0, -h * 0.55), 200.0, theme["light"], 0.3)
		"h_throne":
			_halo(root, Vector2(0, -h * 0.6), 720.0, Color(0.6, 0.35, 1.0), 0.32)
			_halo(root, Vector2(0, -h * 0.82), 120.0, Color(0.8, 0.5, 1.0), 0.6)
			_add_light(pos + Vector2(0, 60), theme["light"], 560.0, 0.9, 0.1)
		"standard":
			var m := _shader("sway")
			m.set_shader_parameter("band", Vector2(0.08, 0.62))
			m.set_shader_parameter("amp", 7.0)
			m.set_shader_parameter("seed", _rng.randf() * 10.0)
			s.material = m
	if kind.begins_with("statue") and theme_id != "oriel":
		_add_light(pos + Vector2(0, 30), theme["sigil_color"], 260.0, 0.35, 0.0)
	if h >= 200.0:
		_occluders.append([root, tex.get_width() * sc * 0.42, h])
	_ysorted.append(root)
	add_child(root)
	return root

func _fire(parent: Node2D, at: Vector2, size: Vector2, intensity: float) -> void:
	var f := Sprite2D.new()
	f.texture = _white
	f.centered = false
	f.offset = Vector2(-4, -8)
	f.scale = size / 8.0
	f.position = at + Vector2(0, size.y * 0.12)
	var m := _shader("flame")
	var fc: Array = theme["flame"]
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("core", fc[0])
	m.set_shader_parameter("mid", fc[1])
	m.set_shader_parameter("outer", fc[2])
	m.set_shader_parameter("seed", _rng.randf())
	m.set_shader_parameter("intensity", 1.0 * intensity)
	f.material = m
	parent.add_child(f)
	_halo(parent, at + Vector2(0, -size.y * 0.25), size.x * 4.2, fc[1], 0.55)

func _halo(parent: Node2D, at: Vector2, diameter: float, color: Color, alpha: float, squash := 1.0) -> Sprite2D:
	var h := Sprite2D.new()
	h.texture = _glow
	h.material = _additive()
	h.position = at
	var bs := diameter / 128.0
	h.scale = Vector2(bs, bs * squash)
	h.modulate = Color(color, alpha)
	parent.add_child(h)
	_halos.append([h, bs, _rng.randf() * TAU, alpha, squash])
	return h

func _lantern(pos: Vector2) -> void:
	var tex := _tex("props/lantern.png")
	var root := Node2D.new()
	root.position = pos
	var hang := 470.0
	var pivot := Node2D.new()
	pivot.position = Vector2(0, -hang)
	root.add_child(pivot)
	var s := Sprite2D.new()
	s.texture = tex
	var sc := 300.0 / tex.get_height()
	s.scale = Vector2(sc, sc)
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.45)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pivot.add_child(s)
	var lc: Color = Color(0.6, 1.0, 0.7) if floor_key == "catacomb" else (Color(0.7, 0.5, 1.0) if floor_key == "throne" else theme["lantern"])
	_halo(pivot, Vector2(0, 300.0 * 0.45), 180.0, lc, 0.45)
	var sh := Sprite2D.new()
	sh.texture = _glow
	sh.material = _additive()
	sh.scale = Vector2(2.2, 0.9)
	sh.modulate = Color(lc, 0.12)
	sh.z_index = -1
	root.add_child(sh)
	_swingers.append([pivot, _rng.randf() * TAU, 0.035])
	_ysorted.append(root)
	add_child(root)

# --------------------------------------------------------------- chapter set pieces
## Quad sprite whose shader draws an elliptic pool of radius r (world px) centred at c.
func _pool_quad(c: Vector2, r: float, mat: ShaderMaterial, z: int, pad := 1.12) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _white
	s.position = c
	s.scale = Vector2(r * 2.0 * pad / 8.0, r * 2.0 * pad * ISO / 8.0)
	s.material = mat
	s.z_index = z
	mat.set_shader_parameter("pad", pad)
	add_child(s)
	return s

func _ellipse_poly(c: Vector2, r: float, n := 20) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(n):
		var a := TAU * i / n
		p.append(c + Vector2(cos(a) * r, sin(a) * r * ISO))
	return p

func _add_hazard(type: String, poly: PackedVector2Array, extra := {}) -> Dictionary:
	var rc := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		rc = rc.expand(q)
	var h := {"type": type, "poly": poly, "rect": rc, "dps": HAZARD_DPS[type], "slow": HAZARD_SLOW[type], "active": type != "spikes"}
	h.merge(extra)
	_hazards.append(h)
	return h

func _water_pool(c: Vector2, r: float) -> void:
	var m := _shader("water")
	m.set_shader_parameter("noise_tex", _noise)
	var lc: Color = theme["light"]
	m.set_shader_parameter("shallow", Color(0.2, 0.62, 0.58).lerp(lc, 0.2))
	m.set_shader_parameter("deep", Color(0.02, 0.12, 0.16))
	m.set_shader_parameter("glow", Color(0.5, 1.0, 0.92))
	m.set_shader_parameter("seed", _rng.randf())
	_pool_quad(c, r, m, -68)
	_water_mats.append(m)
	_add_hazard("water", _ellipse_poly(c, r * 0.92))
	_pools.append([c, r])
	var pi := _pools.size() - 1
	_add_light(c, lc, r * 1.6, 0.35, 0.0)
	# lily pads (top-down art laid flat on the water)
	var lil := _tex("garden/lilies.png")
	for i in range(1 + int(r / 120.0) + _rng.randi() % 2):
		var a := _rng.randf() * TAU
		var d := r * _rng.randf_range(0.35, 0.7)
		var holder := Node2D.new()
		holder.position = c + Vector2(cos(a) * d, sin(a) * d * ISO)
		holder.scale = Vector2(1.0, ISO)
		holder.z_index = -67
		var s := Sprite2D.new()
		s.texture = lil
		s.rotation = _rng.randf() * TAU
		s.scale = Vector2.ONE * _rng.randf_range(0.5, 0.8)
		holder.add_child(s)
		add_child(holder)
		_swingers.append([s, _rng.randf() * TAU, 0.08])
	# koi gliding under the surface
	var koi := _tex("garden/koi.png")
	for i in range(1 + int(r / 160.0)):
		var holder := Node2D.new()
		holder.position = c
		holder.scale = Vector2(1.0, ISO)
		holder.z_index = -69
		var s := Sprite2D.new()
		s.texture = koi
		s.scale = Vector2.ONE * 0.75
		s.modulate = Color(0.85, 1.0, 1.0, 0.9)
		holder.add_child(s)
		add_child(holder)
		_koi.append([holder, s, c, r * _rng.randf_range(0.35, 0.6), _rng.randf_range(0.25, 0.45) * (1.0 if _rng.randf() < 0.5 else -1.0), _rng.randf() * TAU])
	# expanding ripple rings
	for i in range(2):
		var rs := Sprite2D.new()
		rs.texture = _ring
		rs.material = _additive()
		rs.z_index = -67
		rs.modulate = Color(0.7, 1.0, 0.95, 0.0)
		add_child(rs)
		_ripples.append([rs, pi, _rng.randf() * 3.0])

func _lava_pool(c: Vector2, r: float) -> void:
	var m := _shader("lava")
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("mode", 0)
	m.set_shader_parameter("seed", _rng.randf())
	_pool_quad(c, r, m, -68)
	_add_hazard("lava", _ellipse_poly(c, r * 0.88))
	_add_light(c, Color(1.0, 0.45, 0.12), r * 2.2, 1.1, 0.12)
	_halo(self, c, r * 3.0, Color(1.0, 0.4, 0.1), 0.22, ISO).z_index = -67
	_heat_regions.append(_ellipse_poly(c, r * 1.02))
	var e := _particles(10, 2.2, _dot, Color(1.0, 0.6, 0.2), 1)
	e.position = c
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.emission_rect_extents = Vector2(r * 0.7, r * 0.3)
	e.direction = Vector2(0, -1)
	e.spread = 20.0
	e.initial_velocity_min = 30.0
	e.initial_velocity_max = 90.0
	e.scale_amount_min = 0.08
	e.scale_amount_max = 0.18
	e.z_index = -66
	add_child(e)

func _lava_channel(pts: PackedVector2Array, w: float) -> void:
	# densify, then offset into a strip (UV.x = length / 256, UV.y across)
	var line := PackedVector2Array()
	for i in range(pts.size() - 1):
		var steps := maxi(1, int(pts[i].distance_to(pts[i + 1]) / 40.0))
		for s in range(steps):
			line.append(pts[i].lerp(pts[i + 1], float(s) / steps))
	line.append(pts[pts.size() - 1])
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var polys: Array = []
	var along := 0.0
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(line.size()):
		var a := line[maxi(i - 1, 0)]
		var b := line[mini(i + 1, line.size() - 1)]
		var n := (b - a).normalized().orthogonal()
		n = Vector2(n.x, n.y * 0.8).normalized()
		if i > 0:
			along += line[i].distance_to(line[i - 1])
		var hw := w * (0.85 + 0.3 * sin(along * 0.02))
		verts.append(line[i] + n * hw)
		verts.append(line[i] - n * hw)
		uvs.append(Vector2(along / 256.0, 0.0))
		uvs.append(Vector2(along / 256.0, 1.0))
		left.append(line[i] + n * hw * 0.85)
		right.append(line[i] - n * hw * 0.85)
		if i > 0:
			var k := i * 2
			polys.append(PackedInt32Array([k - 2, k, k + 1, k - 1]))
	# Polygon2D only passes UVs with a texture (UVs in texture pixels): a 4x4 white repeat tile
	var p := Polygon2D.new()
	p.texture = _solid_tex(4, 4, Color.WHITE)
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for i in range(uvs.size()):
		uvs[i] *= 4.0
	p.polygon = verts
	p.uv = uvs
	p.polygons = polys
	var m := _shader("lava")
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("mode", 1)
	m.set_shader_parameter("seed", _rng.randf())
	m.set_shader_parameter("flow", 0.22)
	p.material = m
	p.z_index = -68
	add_child(p)
	right.reverse()
	var poly := left.duplicate()
	poly.append_array(right)
	_add_hazard("lava", poly)
	_heat_regions.append(poly)
	for i in range(0, line.size(), 8):
		_add_light(line[i], Color(1.0, 0.45, 0.12), 280.0, 0.75, 0.15)
	var e := _particles(10, 2.0, _dot, Color(1.0, 0.6, 0.2), 1)
	e.position = (line[0] + line[line.size() - 1]) * 0.5
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var ext := (line[line.size() - 1] - line[0]).abs() * 0.5
	e.emission_rect_extents = Vector2(maxf(ext.x, 30.0), maxf(ext.y, 20.0))
	e.direction = Vector2(0, -1)
	e.spread = 20.0
	e.initial_velocity_min = 30.0
	e.initial_velocity_max = 80.0
	e.scale_amount_min = 0.06
	e.scale_amount_max = 0.14
	e.z_index = -66
	add_child(e)

## One screen-reading node for all the lava in the room: shimmer rising above the lava areas.
func _build_heat() -> void:
	if _heat_regions.is_empty():
		return
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var polys: Array = []
	for reg in _heat_regions:
		var rc := Rect2(reg[0], Vector2.ZERO)
		for q in reg:
			rc = rc.expand(q)
		var k := verts.size()
		var top := rc.position.y - 160.0
		var bot := rc.end.y
		verts.append_array([Vector2(rc.position.x, top), Vector2(rc.end.x, top), Vector2(rc.end.x, bot), Vector2(rc.position.x, bot)])
		cols.append_array([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1)])
		polys.append(PackedInt32Array([k, k + 1, k + 2, k + 3]))
	_heat = Polygon2D.new()
	_heat.polygon = verts
	_heat.vertex_colors = cols
	_heat.polygons = polys
	var m := _shader("heat")
	m.set_shader_parameter("noise_tex", _noise)
	_heat.material = m
	_heat.z_index = -66
	add_child(_heat)
	_heat_regions.clear()

func _pit(c: Vector2, r: float) -> void:
	var m := _shader("pit")
	m.set_shader_parameter("noise_tex", _noise)
	var rim := _art("rim")
	m.set_shader_parameter("cliff_tex", rim)
	m.set_shader_parameter("seed", _rng.randf())
	m.set_shader_parameter("void_color", Color(theme["mist"]).darkened(0.85))
	m.set_shader_parameter("glow", theme["light"])
	m.set_shader_parameter("glow_amount", 0.3)
	m.set_shader_parameter("cliff_rep", maxf(1.0, PI * r / (rim.get_width() * 430.0 / rim.get_height())))
	m.set_shader_parameter("cliff_depth", 0.7)
	_pool_quad(c, r, m, -68, 1.25)
	_obstacles.append({"pos": c, "radius": r * 0.86, "pit": true})
	var v := _particles(8, 3.0, _rock, Color(0.5, 0.45, 0.5), 0)
	v.position = c + Vector2(0, -r * ISO * 0.3)
	v.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	v.emission_rect_extents = Vector2(r * 0.6, 10)
	v.direction = Vector2(0, 1)
	v.spread = 5.0
	v.initial_velocity_min = 20.0
	v.initial_velocity_max = 50.0
	v.gravity = Vector2(0, 90)
	v.scale_amount_min = 0.3
	v.scale_amount_max = 0.8
	v.z_index = -68
	add_child(v)

func _spike_trap(c: Vector2) -> void:
	var size := 150.0
	var holder := Node2D.new()
	holder.position = c
	holder.scale = Vector2(1.0, ISO)
	holder.z_index = -67
	var plate := Sprite2D.new()
	var ptex := _tex("forge/trap.png")
	plate.texture = ptex
	plate.rotation = PI * 0.25
	plate.scale = Vector2.ONE * size / ptex.get_width()
	plate.modulate = Color(0.7, 0.85, 0.8) if chapter == "garden" else Color(0.9, 0.86, 0.86)
	holder.add_child(plate)
	var warn := Sprite2D.new()
	warn.texture = _glow
	warn.material = _additive()
	warn.scale = Vector2.ONE * size * 1.3 / 128.0
	warn.modulate = Color(1.0, 0.35, 0.15, 0.0) if chapter == "forge" else Color(theme["light"], 0.0)
	holder.add_child(warn)
	add_child(holder)
	var root := Node2D.new()
	root.position = c + Vector2(0, 8)
	var sp := Node2D.new()
	root.add_child(sp)
	var stex := _tex("hollow/spikes.png")
	var sc := 120.0 / stex.get_height()
	for o in [Vector2(-26, -6), Vector2(26, -6), Vector2(0, 8)]:
		var s := Sprite2D.new()
		s.texture = stex
		s.centered = false
		s.offset = Vector2(-stex.get_width() * 0.5, -stex.get_height() * 0.92)
		s.position = o
		s.scale = Vector2(sc * 0.7, sc * 0.75)
		sp.add_child(s)
	sp.scale = Vector2(1, 0.0)
	_ysorted.append(root)
	add_child(root)
	var k := size * 0.62
	var poly := PackedVector2Array([c + Vector2(-k, 0), c + Vector2(0, -k * ISO), c + Vector2(k, 0), c + Vector2(0, k * ISO)])
	_add_hazard("spikes", poly, {"period": SPIKE_PERIOD, "up": SPIKE_UP})
	_spike_nodes.append([_hazards.size() - 1, sp, warn, _rng.randf() * SPIKE_PERIOD])

func _debris_zone(c: Vector2, r: float) -> void:
	var sh := Sprite2D.new()
	sh.texture = _shadow
	sh.position = c
	sh.z_index = -67
	sh.modulate.a = 0.0
	add_child(sh)
	var rock := Sprite2D.new()
	if chapter == "hollow":
		rock.texture = _tex("hollow/debris.png")
		rock.scale = Vector2.ONE * 0.42
	else:
		rock.texture = _rock
		rock.scale = Vector2.ONE * 6.0
		rock.modulate = Color(0.28, 0.2, 0.18)
	rock.visible = false
	rock.z_index = 15
	add_child(rock)
	var dust := _particles(16, 0.8, _smoke, Color(0.6, 0.55, 0.55), 0)
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.preprocess = 0.0
	dust.emitting = false
	dust.direction = Vector2(0, -1)
	dust.spread = 90.0
	dust.initial_velocity_min = 80.0
	dust.initial_velocity_max = 200.0
	dust.damping_min = 120.0
	dust.damping_max = 200.0
	dust.scale_amount_min = 0.8
	dust.scale_amount_max = 1.8
	dust.z_index = 14
	add_child(dust)
	# faint ring on the floor so the zone reads before anything falls
	var mk := Sprite2D.new()
	mk.texture = _ring
	mk.position = c
	mk.scale = Vector2(r * 2.0 / 64.0, r * 2.0 * ISO / 64.0)
	mk.modulate = Color(theme["light"], 0.2)
	mk.material = _additive()
	mk.z_index = -67
	add_child(mk)
	_add_hazard("debris", _ellipse_poly(c, r), {"damage": DEBRIS_DAMAGE, "radius": r * 0.5})
	_debris_zones.append({"c": c, "r": r, "t": _rng.randf_range(1.5, 4.0), "state": 0, "shadow": sh, "rock": rock, "dust": dust, "at": c})

func _floater(p: Vector2) -> void:
	var root := Node2D.new()
	root.position = p
	var g := Sprite2D.new()
	g.texture = _glow
	g.material = _additive()
	g.modulate = Color(theme["light"], 0.16)
	g.scale = Vector2(1.6, 0.6)
	root.add_child(g)
	var tex := _tex("hollow/debris.png")
	var s := Sprite2D.new()
	s.texture = tex
	var sc := _rng.randf_range(110.0, 190.0) / tex.get_height()
	s.scale = Vector2(sc * (1.0 if _rng.randf() < 0.5 else -1.0), sc)
	s.position = Vector2(0, -_rng.randf_range(80.0, 200.0))
	s.modulate = Color(0.8, 0.78, 0.86)
	root.add_child(s)
	_floaters.append([s, s.position.y, _rng.randf() * TAU])
	_ysorted.append(root)
	add_child(root)

func _spark_burst(parent: Node2D, at: Vector2) -> CPUParticles2D:
	var fc: Array = theme["flame"]
	var sp := _particles(14, 0.7, _dot, fc[0].lerp(fc[1], 0.4), 1)
	sp.position = at
	sp.one_shot = true
	sp.explosiveness = 0.9
	sp.preprocess = 0.0
	sp.emitting = false
	sp.direction = Vector2(0, -1)
	sp.spread = 75.0
	sp.initial_velocity_min = 120.0
	sp.initial_velocity_max = 280.0
	sp.gravity = Vector2(0, 520)
	sp.scale_amount_min = 0.06
	sp.scale_amount_max = 0.13
	parent.add_child(sp)
	return sp

func _smoke_column(parent: Node2D, at: Vector2, k: float) -> void:
	var s := _particles(int(10 * k) + 4, 4.5, _smoke, Color(0.16, 0.12, 0.12), 0)
	s.position = at
	s.direction = Vector2(0.15, -1)
	s.spread = 12.0
	s.initial_velocity_min = 40.0
	s.initial_velocity_max = 70.0
	s.gravity = Vector2(10, -10)
	s.scale_amount_min = 1.2 * k
	s.scale_amount_max = 2.4 * k
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0))
	s.scale_amount_curve = c
	s.angular_velocity_min = -20.0
	s.angular_velocity_max = 20.0
	parent.add_child(s)

# --------------------------------------------------------------- particles
func _particles(amount: int, lifetime: float, tex: Texture2D, color: Color, additive: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.texture = tex
	p.local_coords = false
	p.preprocess = lifetime
	p.randomness = 0.5
	p.lifetime_randomness = 0.4
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.2, Color(color, 1.0))
	g.add_point(0.7, Color(color, 0.8))
	p.color_ramp = g
	if additive == 1:
		p.material = _additive()
	return p

func _embers(parent: Node2D, at: Vector2) -> void:
	var fc: Array = theme["flame"]
	var e := _particles(6, 1.8, _dot, fc[1].lerp(Color.WHITE, 0.25), 1)
	e.position = at
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 14.0
	e.direction = Vector2(0, -1)
	e.spread = 25.0
	e.initial_velocity_min = 40.0
	e.initial_velocity_max = 95.0
	e.gravity = Vector2(0, -18)
	e.angular_velocity_min = 0
	e.scale_amount_min = 0.08
	e.scale_amount_max = 0.18
	e.orbit_velocity_min = -0.05
	e.orbit_velocity_max = 0.05
	parent.add_child(e)

func _cam_particles(amount: int, lifetime: float, tex: Texture2D, color: Color, additive: int, z: int) -> CPUParticles2D:
	var p := _particles(amount, lifetime, tex, color, additive)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(900, 480)
	p.z_index = z
	add_child(p)
	_cam_followers.append(p)
	return p

func _build_particles() -> void:
	# ambient motes around the camera (emitter follows the camera; particles stay in world space)
	var col: Color = theme["sigil_color"].lerp(Color(1, 0.95, 0.85), 0.55)
	var motes := _cam_particles(34, 7.0, _dot, col, 1, 12)
	motes.direction = Vector2(0.3, -1)
	motes.spread = 60.0
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 22.0
	motes.gravity = Vector2(0, -2)
	motes.scale_amount_min = 0.06
	motes.scale_amount_max = 0.16
	match theme["particles"]:
		"petals":
			var p := _cam_particles(26, 8.0, _petal, Color(0.95, 0.3, 0.42), 0, 13)
			p.emission_rect_extents = Vector2(900, 420)
			p.direction = Vector2(1, 0.4)
			p.spread = 30.0
			p.initial_velocity_min = 18.0
			p.initial_velocity_max = 40.0
			p.gravity = Vector2(4, 9)
			p.angular_velocity_min = -90.0
			p.angular_velocity_max = 90.0
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 0.9
		"sparks":
			var s := _particles(18, 1.2, _dot, Color(0.6, 0.85, 1.0), 1)
			s.position = Vector2(0, -half.y * 0.02)
			s.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			s.emission_rect_extents = Vector2(420, 220)
			s.direction = Vector2(0, -1)
			s.spread = 180.0
			s.initial_velocity_min = 30.0
			s.initial_velocity_max = 120.0
			s.damping_min = 60.0
			s.damping_max = 120.0
			s.scale_amount_min = 0.05
			s.scale_amount_max = 0.12
			s.z_index = -65
			add_child(s)
		"bubbles":
			var b := _cam_particles(22, 5.0, _dot, Color(0.45, 0.95, 0.9), 1, 12)
			b.direction = Vector2(0, -1)
			b.spread = 15.0
			b.initial_velocity_min = 14.0
			b.initial_velocity_max = 34.0
			b.scale_amount_min = 0.1
			b.scale_amount_max = 0.24
		"motes_violet":
			_void_rubble(Color(0.55, 0.5, 0.6))
			_rising_sparks(Color(0.75, 0.55, 1.0), 20)
		"fireflies":
			# blinking fireflies drifting over the floor
			var f := _cam_particles(26, 6.0, _dot, Color(0.75, 1.0, 0.6), 1, 12)
			var g := Gradient.new()
			var fc := Color(0.75, 1.0, 0.6)
			g.offsets = PackedFloat32Array([0.0, 0.12, 0.2, 0.32, 0.45, 0.6, 0.72, 0.85, 1.0])
			g.colors = PackedColorArray([Color(fc, 0), Color(fc, 1), Color(fc, 0.15), Color(fc, 1), Color(fc, 0.2), Color(fc, 1), Color(fc, 0.1), Color(fc, 0.9), Color(fc, 0)])
			f.color_ramp = g
			f.direction = Vector2(1, -0.3)
			f.spread = 180.0
			f.initial_velocity_min = 10.0
			f.initial_velocity_max = 30.0
			f.orbit_velocity_min = -0.03
			f.orbit_velocity_max = 0.03
			f.scale_amount_min = 0.12
			f.scale_amount_max = 0.22
			# drifting willow leaves
			var l := _cam_particles(14, 9.0, _petal, Color(0.55, 0.62, 0.5), 0, 13)
			l.direction = Vector2(1, 0.5)
			l.spread = 30.0
			l.initial_velocity_min = 14.0
			l.initial_velocity_max = 30.0
			l.gravity = Vector2(3, 8)
			l.angular_velocity_min = -80.0
			l.angular_velocity_max = 80.0
			l.angle_max = 360.0
			l.scale_amount_min = 0.5
			l.scale_amount_max = 0.8
			# water drips falling from the island into the void
			_void_rubble(Color(0.3, 0.75, 0.7), true)
		"forge":
			var e := _cam_particles(30, 4.0, _dot, Color(1.0, 0.55, 0.18), 1, 12)
			e.direction = Vector2(0.15, -1)
			e.spread = 25.0
			e.initial_velocity_min = 30.0
			e.initial_velocity_max = 80.0
			e.orbit_velocity_min = -0.02
			e.orbit_velocity_max = 0.02
			e.scale_amount_min = 0.06
			e.scale_amount_max = 0.15
			var a := _cam_particles(18, 8.0, _petal, Color(0.25, 0.22, 0.22), 0, 13)
			a.direction = Vector2(0.4, 1)
			a.spread = 30.0
			a.initial_velocity_min = 10.0
			a.initial_velocity_max = 30.0
			a.angular_velocity_min = -60.0
			a.angular_velocity_max = 60.0
			a.angle_max = 360.0
			a.scale_amount_min = 0.3
			a.scale_amount_max = 0.6
			_void_rubble(Color(0.4, 0.22, 0.16))
		"hollow":
			_void_rubble(Color(0.6, 0.55, 0.66))
			_rising_sparks(Color(0.75, 0.55, 1.0), 22)
			var a := _cam_particles(16, 9.0, _petal, Color(0.32, 0.2, 0.42), 0, 13)
			a.direction = Vector2(1, 0.3)
			a.spread = 25.0
			a.initial_velocity_min = 16.0
			a.initial_velocity_max = 34.0
			a.gravity = Vector2(3, 6)
			a.angular_velocity_min = -90.0
			a.angular_velocity_max = 90.0
			a.angle_max = 360.0
			a.scale_amount_min = 0.45
			a.scale_amount_max = 0.8
	if theme_id == "oriel":
		var a := _cam_particles(18, 4.0, _dot, Color(1.0, 0.6, 0.25), 1, 12)
		a.direction = Vector2(0.2, -1)
		a.spread = 25.0
		a.initial_velocity_min = 25.0
		a.initial_velocity_max = 60.0
		a.scale_amount_min = 0.06
		a.scale_amount_max = 0.14

func _rising_sparks(c: Color, amount: int) -> void:
	var v := _particles(amount, 4.0, _dot, c, 1)
	v.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	v.emission_rect_extents = Vector2(half.x * 0.7, half.y * 0.5)
	v.direction = Vector2(0, -1)
	v.spread = 20.0
	v.initial_velocity_min = 20.0
	v.initial_velocity_max = 60.0
	v.scale_amount_min = 0.06
	v.scale_amount_max = 0.16
	v.z_index = 12
	add_child(v)

## Rubble (or water drips) falling past the island into the void, behind the floor.
func _void_rubble(c: Color, drips := false) -> void:
	var d := _particles(22, 3.5, _dot if drips else _rock, c, 1 if drips else 0)
	d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	d.emission_rect_extents = Vector2(1000, 120)
	d.position = Vector2(0, -560)
	d.direction = Vector2(0, 1)
	d.spread = 8.0
	d.initial_velocity_min = 60.0
	d.initial_velocity_max = 160.0
	d.gravity = Vector2(0, 260)
	d.angular_velocity_min = -180.0
	d.angular_velocity_max = 180.0
	d.scale_amount_min = 0.12 if drips else 0.5
	d.scale_amount_max = 0.25 if drips else 1.6
	d.z_index = -95
	add_child(d)
	_cam_followers.append(d)

# --------------------------------------------------------------- foreground
func _build_foreground() -> void:
	var texs: Array = [_tex("props/pillar.png")]
	var hs := 700.0
	if not _legacy:
		match chapter:
			"garden":
				texs = [_tex("garden/willow.png"), _tex("garden/arch.png")]
				hs = 900.0
			"forge":
				texs = [_tex("forge/chainpost.png"), _tex("forge/furnace.png")]
				hs = 760.0
			"hollow":
				texs = [_tex("hollow/statue.png"), _tex("hollow/standard.png")]
				hs = 820.0
	# bases far below the front ledges: only the tops rise into view when the camera nears the front
	var spots := [Vector2(-vhalf.x * 0.45, vhalf.y * 0.55 + 980.0), Vector2(vhalf.x * 0.52, vhalf.y * 0.48 + 1000.0), Vector2(-vhalf.x * 1.0, 1010.0), Vector2(vhalf.x * 1.02, 1040.0)]
	for i in range(spots.size()):
		var tex: Texture2D = texs[i % texs.size()]
		var sc := hs / tex.get_height()
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
		s.scale = Vector2(sc, sc) * (1.0 + 0.12 * i)
		if not _legacy and i % 2 == 1:
			s.scale.x = -s.scale.x
		s.position = spots[i]
		s.modulate = Color(0.03, 0.025, 0.04, 0.92)
		s.z_index = 20
		add_child(s)
		_silhouettes.append(s)
	if floor_key == "throne" or (not _legacy and chapter != "garden"):
		# a few large dark fragments drifting down in front of everything
		var d := _particles(4, 6.0, _rock, Color(0.08, 0.06, 0.1), 0)
		d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		d.emission_rect_extents = Vector2(900, 60)
		d.position = Vector2(0, -520)
		d.direction = Vector2(0, 1)
		d.spread = 5.0
		d.initial_velocity_min = 90.0
		d.initial_velocity_max = 150.0
		d.angular_velocity_min = -60.0
		d.angular_velocity_max = 60.0
		d.scale_amount_min = 2.5
		d.scale_amount_max = 4.0
		d.z_index = 21
		add_child(d)
		_cam_followers.append(d)

func _build_vignette() -> void:
	_vignette = CanvasLayer.new()
	_vignette.layer = 2
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := _shader("vignette")
	m.set_shader_parameter("color", Color(theme["mist"]).darkened(0.9))
	m.set_shader_parameter("strength", 0.8)
	r.material = m
	_vignette.add_child(r)
	add_child(_vignette)

# --------------------------------------------------------------- spawns
func _compute_spawns() -> void:
	var cands: Array = []
	var rings := [0.68, 0.45] if _legacy else [0.68, 0.45, 0.25]
	for ring in rings:
		for i in range(10):
			var a := TAU * (i + (0.5 if ring < 0.5 else 0.0)) / 10.0
			cands.append(Vector2(cos(a) * half.x * ring, sin(a) * half.y * ring))
	for c in cands:
		if not _legacy and not _inside_island(c, 40.0):
			continue
		var ok := true
		for o in _obstacles:
			var d: Vector2 = c - o["pos"]
			d.y *= 2.0
			if d.length() < o["radius"] + 70.0:
				ok = false
				break
		if ok:
			for h in _hazards:
				if h["type"] == "lava" and Geometry2D.is_point_in_polygon(c, h["poly"]):
					ok = false
					break
		if not ok or c.distance_to(_start) <= 330.0:
			continue
		var near_door: bool = c.distance_to(get_door_pos()) <= 140.0
		for d in _doors:
			if c.distance_to(d["pos"]) <= 140.0:
				near_door = true
		if not near_door:
			_spawns.append(c)

# =============================================================== per-frame life

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_push_lights()
	var cam := get_viewport().get_camera_2d()
	var cpos := Vector2.ZERO
	if cam:
		cpos = cam.get_screen_center_position()
	if _backdrop:
		_backdrop.position = cpos * 0.86
		var vs := get_viewport_rect().size
		var z := cam.zoom if cam else Vector2.ONE
		var ts := _backdrop.texture.get_size()
		var need := maxf(vs.x / z.x / ts.x, vs.y / z.y / ts.y) * 1.4
		_backdrop.scale = Vector2.ONE * maxf(need, 1.2)
	for f in _cam_followers:
		if is_instance_valid(f):
			f.position = cpos if f.z_index > 0 else Vector2(cpos.x, f.position.y)
	for h in _halos:
		var n: Node2D = h[0]
		if is_instance_valid(n):
			var ph: float = h[2]
			var k := 1.0 + 0.06 * sin(t * 7.3 + ph) + 0.04 * sin(t * 13.7 + ph * 2.0)
			n.scale = Vector2(h[1] * k, h[1] * k * h[4])
			n.modulate.a = h[3] * (0.85 + 0.15 * k)
	for s in _swingers:
		var p: Node2D = s[0]
		if is_instance_valid(p):
			p.rotation = sin(t * 0.9 + s[1]) * s[2]
	for ic in _icons:
		var n: Node2D = ic[0]
		if is_instance_valid(n):
			n.position.y = ic[1] + sin(t * 2.0 + ic[2]) * 8.0
	# tall props turn translucent while the focus (camera follows the heroes) is behind them
	var focus := cpos + Vector2(0, 50)
	for o in _occluders:
		var n: Node2D = o[0]
		if is_instance_valid(n):
			var behind: bool = focus.y < n.position.y - 10.0 and focus.y > n.position.y - o[2] and absf(focus.x - n.position.x) < o[1] + 50.0
			n.modulate.a = move_toward(n.modulate.a, 0.45 if behind else 1.0, delta * 4.0)
	# foreground silhouettes fade when they cover the middle of the view
	for s in _silhouettes:
		if is_instance_valid(s):
			var top: Vector2 = s.position + Vector2(0, -s.texture.get_height() * s.scale.y)
			var dx := absf(s.position.x - cpos.x)
			var near := dx < 520.0 and top.y < cpos.y + 260.0
			s.modulate.a = move_toward(s.modulate.a, 0.35 if near else 0.92, delta * 2.0)
	# storm flashes
	if theme_id == "vessa" and _void_mat:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash = 1.0
			_flash_timer = randf_range(3.0, 7.0)
		_flash = maxf(0.0, _flash - delta * 3.5)
		var f2 := _flash * (0.6 + 0.4 * sin(t * 60.0))
		_void_mat.set_shader_parameter("flash", f2 * 0.6)
	if not _legacy:
		_process_chapter(t, delta)

func _process_chapter(t: float, delta: float) -> void:
	# koi circling under the water
	for k in _koi:
		var holder: Node2D = k[0]
		if not is_instance_valid(holder):
			continue
		var a: float = k[5] + t * k[4]
		var r: float = k[3] * (0.85 + 0.15 * sin(t * 0.7 + k[5]))
		var c: Vector2 = k[2]
		holder.position = c + Vector2(cos(a) * r, sin(a) * r * ISO)
		var heading := Vector2(-sin(a), cos(a)) * signf(k[4])
		var spr: Sprite2D = k[1]
		spr.rotation = heading.angle() - deg_to_rad(116.0) + sin(t * 5.0 + k[5]) * 0.12
	# ripples
	for rp in _ripples:
		var s: Sprite2D = rp[0]
		if not is_instance_valid(s) or not s.visible:
			continue
		rp[2] -= delta
		if rp[2] <= 0.0:
			rp[2] = _rng.randf_range(2.0, 3.6)
			var pool: Array = _pools[rp[1]]
			var a := _rng.randf() * TAU
			var d: float = _rng.randf() * pool[1] * 0.6
			s.position = pool[0] + Vector2(cos(a) * d, sin(a) * d * ISO)
		var k := clampf(1.0 - rp[2] / 2.0, 0.0, 1.0)
		var sz := lerpf(0.4, 2.2, k)
		s.scale = Vector2(sz, sz * ISO)
		s.modulate.a = (1.0 - k) * 0.4 if rp[2] < 2.0 else 0.0
	# spikes: warning glow, then up, then down
	for sn in _spike_nodes:
		var h: Dictionary = _hazards[sn[0]]
		var ph := fmod(t + sn[3], SPIKE_PERIOD)
		var up_at := SPIKE_PERIOD - SPIKE_UP
		var warn_at := up_at - SPIKE_WARN
		var target := 0.0
		var w := 0.0
		if ph >= up_at:
			target = 1.0
		elif ph >= warn_at:
			target = 0.12
			w = (ph - warn_at) / SPIKE_WARN
		var sp: Node2D = sn[1]
		sp.scale.y = move_toward(sp.scale.y, target, delta * (14.0 if target > sp.scale.y else 4.0))
		h["active"] = sp.scale.y > 0.6
		var wn: Sprite2D = sn[2]
		wn.modulate.a = 0.55 * w + 0.25 * target
	# falling debris: shadow telegraph, rock drop, dust, damage signal
	for z in _debris_zones:
		z["t"] -= delta
		var sh: Sprite2D = z["shadow"]
		var rock: Sprite2D = z["rock"]
		match z["state"]:
			0:
				if z["t"] <= 0.0:
					z["state"] = 1
					z["t"] = 1.3
					var a := _rng.randf() * TAU
					var d: float = sqrt(_rng.randf()) * z["r"] * 0.75
					z["at"] = z["c"] + Vector2(cos(a) * d, sin(a) * d * ISO)
					sh.position = z["at"]
					rock.visible = true
					rock.rotation = _rng.randf() * TAU
			1:
				var k: float = 1.0 - z["t"] / 1.3
				var rr: float = z["r"] * 0.5
				sh.scale = Vector2(rr * 2.0 / 64.0, rr * 2.0 * ISO / 64.0) * lerpf(0.3, 1.0, k)
				sh.modulate.a = 0.85 * k
				rock.position = z["at"] + Vector2(0, -1100.0 * (1.0 - k * k))
				rock.rotation += delta * 2.0
				if z["t"] <= 0.0:
					z["state"] = 2
					z["t"] = 0.5
					rock.visible = false
					var dust: CPUParticles2D = z["dust"]
					dust.position = z["at"]
					dust.restart()
					debris_impact.emit(z["at"], rr, DEBRIS_DAMAGE)
			2:
				sh.modulate.a = maxf(0.0, sh.modulate.a - delta * 2.0)
				if z["t"] <= 0.0:
					z["state"] = 0
					z["t"] = _rng.randf_range(2.5, 5.0)
	# anvil sparks ("hammer strikes")
	for b in _bursts:
		b[2] -= delta
		if b[2] <= 0.0:
			b[2] = b[1] * _rng.randf_range(0.8, 1.3)
			var p: CPUParticles2D = b[0]
			if is_instance_valid(p):
				p.restart()
	for b in _bellows:
		var s: Sprite2D = b[0]
		if is_instance_valid(s):
			s.scale = Vector2(b[1].x, b[1].y * (1.0 + 0.05 * sin(t * 1.8 + b[2])))
	for f in _floaters:
		var s: Sprite2D = f[0]
		if is_instance_valid(s):
			s.position.y = f[1] + sin(t * 0.8 + f[2]) * 14.0
			s.rotation = sin(t * 0.5 + f[2]) * 0.05
