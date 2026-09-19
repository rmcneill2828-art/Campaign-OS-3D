extends SceneTree
## Functional check for CharacterViewer.gd (ROADMAP.md's "Seven requested features"
## 2026-09-19 entry, item 3). Exercises the pieces a live engine-server can't help
## verify on its own: that the whole code-built scene (camera rig, model token, HUD)
## actually gets built by _ready(), that _apply_token()/_format_stats() render a
## token's data correctly, that a Load Model override survives repeated polls without
## the "already has a parent" bug an earlier version of this file's own _apply_token()
## had (see its doc comment), and that the runtime glTF loader
## (_load_external_glb()) really can parse a real .glb file from an absolute OS path
## -- using a file already committed to this repo (Kenney's floor.glb) rather than a
## throwaway fixture, so this is a genuine parse, not a mocked one.
##
## See smoke_test_main.gd's own doc comment for why quit() is deferred to the first
## _process() tick rather than called synchronously in _init().

var _failures := 0
var _viewer

func _fail(message: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % message)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

func _fake_token(overrides: Dictionary = {}) -> Dictionary:
	var data := {
		"id": "1", "name": "Kestrel", "type": "hero", "mapName": "Test Map",
		"x": 3, "y": 3, "hp": 20, "maxHp": 28, "ac": 15,
		"abilityScores": {"STR": 12, "DEX": 17, "CON": 14, "INT": 10, "WIS": 15, "CHA": 8},
		"conditions": [], "speed": 30
	}
	for key in overrides:
		data[key] = overrides[key]
	return data

func _test_character_viewer(viewer) -> void:
	_check(viewer.get("_camera_rig") != null, "_ready() built the orbit camera rig")
	_check(viewer.get("_model_token") != null, "_ready() built the embedded Token")
	_check(viewer.get("_stats_label") != null, "_ready() built the stats panel")
	_check(viewer.get("_model_path_input") != null, "_ready() built the Load Model input row")

	viewer.call("_apply_token", _fake_token())
	var stats: String = viewer.get("_stats_label").text
	_check(stats.contains("Kestrel"), "Stats panel shows the token's name")
	_check(stats.contains("20 / 28"), "Stats panel shows HP/MaxHP")
	_check(stats.contains("DEX 17 (+3)"), "Stats panel shows a correctly computed ability modifier")
	_check(stats.contains("STR 12 (+1)"), "Stats panel shows another correctly computed ability modifier")
	_check(stats.contains("Conditions: none"), "Stats panel reports no conditions when the list is empty")

	viewer.call("_apply_token", _fake_token({"conditions": ["Prone", "Poisoned"]}))
	stats = viewer.get("_stats_label").text
	_check(stats.contains("Prone, Poisoned"), "Stats panel lists real conditions when present")

	# _load_external_glb() against a real file already committed to this repo (not a
	# mocked/throwaway fixture) -- proves the runtime GLTFDocument path genuinely
	# parses a real .glb from an absolute OS path, the same way a model pulled from
	# the external sourcing library would arrive.
	var real_glb_path := ProjectSettings.globalize_path("res://assets/Environment/dungeon-kit/Models/GLB format/floor.glb")
	_check(FileAccess.file_exists(real_glb_path), "Sanity check: the real committed .glb this test loads actually exists on disk")
	var loaded = viewer.call("_load_external_glb", real_glb_path)
	_check(loaded != null, "_load_external_glb() successfully parses a real .glb file from an absolute path")
	if loaded:
		loaded.queue_free()

	_check(viewer.call("_load_external_glb", real_glb_path.replace("floor.glb", "does_not_exist.glb")) == null, "_load_external_glb() returns null (not a crash) for a missing file")

	# Regression check for the exact bug found while building this: applying a Load
	# Model override, then polling again with the SAME token type, must not try to
	# re-parent the override node into a parent it's already a child of.
	var override_instance = viewer.call("_load_external_glb", real_glb_path)
	viewer.get("_model_token").call("preview_external_model", override_instance)
	viewer.set("_custom_model_instance", override_instance)
	viewer.call("_apply_token", _fake_token({"hp": 15})) # same type ("hero") as before -- must NOT re-trigger preview_external_model()
	_check(is_instance_valid(override_instance) and override_instance.get_parent() != null, "A same-type poll after loading an override leaves it in place without throwing")

	# A genuine type change (rare in practice -- e.g. a DM correcting bad seed data)
	# SHOULD re-apply the override, exercising the other branch of that same check.
	viewer.call("_apply_token", _fake_token({"type": "monster"}))
	_check(is_instance_valid(override_instance), "A real type change re-applies the override without throwing either")

func _init() -> void:
	_viewer = CharacterViewer.new()
	_viewer.open("http://127.0.0.1:1", "1") # a real port nothing listens on -- the HTTPRequest just fails to connect, harmless and expected, same convention smoke_test_main.gd's own doc comment documents
	get_root().add_child(_viewer)

var _ran := false
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_character_viewer(_viewer)
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All Character Viewer assertions passed")
		quit()
	return true
