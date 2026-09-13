extends RefCounted
class_name MapScenes
## Phase 4's map-scene contract, factored out of Main.gd so both it and
## PlayerView.gd (Phase 6) resolve a server mapName to the same hand-built
## scene -- unlike the small data lists this project duplicates BETWEEN
## engine.js and GDScript (ABILITY_KEYS, SKILL_LIST, ...), where no shared
## import mechanism exists across that language boundary, these two files
## are both GDScript in the same project, so there's no reason to accept
## drift risk here too. Extend SCENES as more real maps get built.

const SCENES := {
	"Prototype Chamber": "res://scenes/maps/prototype_chamber.tscn",
	"Entrance Hall": "res://scenes/maps/entrance_hall.tscn"
}

static func resolve(map_name: String) -> String:
	return SCENES.get(map_name, "")
