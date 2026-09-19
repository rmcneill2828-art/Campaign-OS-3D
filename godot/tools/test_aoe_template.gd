extends SceneTree
## Functional check for the AoE Template tool (ROADMAP.md's "Seven requested
## features" 2026-09-19 entry, item 7) -- unlike the plain smoke tests
## alongside this one, this actually exercises AoeTemplate.gd's shape math
## AND drives Main.gd through a synthetic state to confirm the Area Spell
## Targets checkboxes really do get auto-checked/unchecked from a placed
## template, not just that the scene loads.
##
## Structured as _init() (instantiate Main.tscn) then _process() (run every
## assertion that needs Main.gd's own _ready() to have actually happened) --
## see smoke_test_main.gd's own doc comment for why: _ready() only runs
## during the tree's first real iteration, not synchronously inside
## add_child(), so anything depending on it can't run from _init() itself.

var _failures := 0
var _main
var _ran := false

func _fail(message: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % message)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

## --- Part 1: AoeTemplate's own shape math, no scene/tree needed --------------------

func _test_shape_math() -> void:
	# point_in_circle -- a point exactly on the boundary counts (RAW: "within" a
	# radius includes its own edge), matching encounter.js's own `<=`.
	_check(AoeTemplate.point_in_circle(3.0, 0.0, 0.0, 0.0, 3.0), "point_in_circle: on the boundary counts")
	_check(not AoeTemplate.point_in_circle(3.1, 0.0, 0.0, 0.0, 3.0), "point_in_circle: just past the boundary doesn't")

	# point_in_cone -- RAW triangle (width = distance along the length), pointing
	# straight along +x (angle 0): a point on the centerline at half the length is
	# inside; a point offset sideways by more than half ITS OWN distance isn't.
	_check(AoeTemplate.point_in_cone(5.0, 0.0, 0.0, 0.0, 0.0, 10.0), "point_in_cone: centerline point within length is inside")
	_check(AoeTemplate.point_in_cone(5.0, 2.4, 0.0, 0.0, 0.0, 10.0), "point_in_cone: just inside the cone's own width at that distance")
	_check(not AoeTemplate.point_in_cone(5.0, 2.6, 0.0, 0.0, 0.0, 10.0), "point_in_cone: just outside the cone's own width at that distance")
	_check(not AoeTemplate.point_in_cone(11.0, 0.0, 0.0, 0.0, 0.0, 10.0), "point_in_cone: past the cone's length is outside")

	# point_in_line -- a fixed-width rectangle extending from the origin.
	_check(AoeTemplate.point_in_line(5.0, 1.0, 0.0, 0.0, 0.0, 10.0, 3.0), "point_in_line: within length and half-width is inside")
	_check(not AoeTemplate.point_in_line(5.0, 2.0, 0.0, 0.0, 0.0, 10.0, 3.0), "point_in_line: past half the width is outside")
	_check(not AoeTemplate.point_in_line(-1.0, 0.0, 0.0, 0.0, 0.0, 10.0, 3.0), "point_in_line: behind the origin is outside")

	# A 90-degree-rotated cone (angle = PI/2, pointing along +y) -- confirms the
	# rotation itself, not just the axis-aligned case every test above uses.
	_check(AoeTemplate.point_in_cone(0.0, 5.0, 0.0, 0.0, PI / 2.0, 10.0), "point_in_cone: rotated 90 degrees, centerline point still inside")
	_check(not AoeTemplate.point_in_cone(5.0, 0.0, 0.0, 0.0, PI / 2.0, 10.0), "point_in_cone: rotated 90 degrees, old centerline point now outside")

	# shape_cells -- circle passes its fields straight through; cone/line produce
	# the expected point counts (triangle vs. rectangle).
	var circle := AoeTemplate.shape_cells("circle", Vector2(1, 1), 0.0, 4.0, 0.0)
	_check(circle["kind"] == "circle" and circle["center"] == Vector2(1, 1) and circle["radius_cells"] == 4.0, "shape_cells: circle passes center/radius through unchanged")
	var cone := AoeTemplate.shape_cells("cone", Vector2.ZERO, 0.0, 4.0, 0.0)
	_check(cone["kind"] == "polygon" and (cone["points"] as Array).size() == 3, "shape_cells: cone is a 3-point triangle")
	var line := AoeTemplate.shape_cells("line", Vector2.ZERO, 0.0, 4.0, 1.0)
	_check(line["kind"] == "polygon" and (line["points"] as Array).size() == 4, "shape_cells: line is a 4-point rectangle")

	# covered_token_names -- the actual wrapper Main.gd calls, end to end.
	var tokens := [
		{"name": "InCircle", "x": 1, "y": 1}, # cell-unit (0.5, 0.5) -- distance 0 from a (0.5,0.5) center
		{"name": "OutCircle", "x": 10, "y": 10}
	]
	var covered := AoeTemplate.covered_token_names(tokens, "circle", Vector2(0.5, 0.5), 0.0, 3.0, 0.0)
	_check(covered.has("InCircle") and not covered.has("OutCircle"), "covered_token_names: circle covers the near token, not the far one")

## --- Part 2: drives Main.gd (already through a real _ready() pass) through a -------
## synthetic state, no real engine-server needed.

func _test_main_integration(main) -> void:
	_check(main.get("_template_shape_option") != null, "Main._ready() built the AoE Template controls (_template_shape_option exists)")

	# A synthetic /state response shape -- same fields _on_state_response() unwraps
	# before calling _apply_state(), skipping the network round trip entirely (no
	# engine-server needed for this test, same "HTTPRequest just fails to connect,
	# which is fine" convention the other smoke tests already rely on).
	var state := {
		"mapName": "Test Map",
		"maps": {"Test Map": {"columns": 12, "rows": 12, "feetPerSquare": 5.0}},
		"tokens": [
			{"id": "1", "name": "Nearby", "mapName": "Test Map", "type": "hero", "x": 3, "y": 3, "hp": 10, "maxHp": 10, "conditions": []},
			{"id": "2", "name": "FarAway", "mapName": "Test Map", "type": "monster", "x": 11, "y": 11, "hp": 10, "maxHp": 10, "conditions": []}
		],
		"turn": {},
		"log": []
	}
	main.call("_apply_state", state)

	_check(main.get("_area_target_checkboxes").size() == 2, "Area Spell Targets list built one checkbox per token on the map")

	# Place a 15 ft (3 cell) circle at cell (3,3) -- Nearby's own cell, so it should
	# end up checked; FarAway sits at (11,11), well outside.
	main.set("_template_active", true)
	main.set("_template_shape", "circle")
	main.set("_template_origin", Vector2(2.5, 2.5)) # cell (3,3)'s own center, in AoeTemplate's cell-unit space
	main.set("_template_placed", true)
	main.get("_template_length_input").value = 15.0
	main.call("_update_template_overlay")

	var checkboxes: Dictionary = main.get("_area_target_checkboxes")
	_check(checkboxes["Nearby"].button_pressed, "Placed circle auto-checked the token inside it")
	_check(not checkboxes["FarAway"].button_pressed, "Placed circle left the token outside it unchecked")
	_check(main.get("_template_overlay") != null, "Placing a template built a real 3D overlay mesh")

	# Re-aiming to a spot with nobody nearby should un-check Nearby again -- the
	# whole point of this tool tracking the shape LIVE rather than only ever adding
	# checks (see _update_template_overlay()'s own doc comment on this).
	main.set("_template_origin", Vector2(11.5, 0.5)) # far corner, empty
	main.call("_update_template_overlay")
	checkboxes = main.get("_area_target_checkboxes")
	_check(not checkboxes["Nearby"].button_pressed, "Moving the template away un-checked the token that left it")

	# Toggling the tool off should stop it from touching the checkboxes further,
	# freezing whatever's checked for a final manual adjustment before casting.
	checkboxes["Nearby"].button_pressed = true # simulate a DM's own manual override
	main.set("_template_active", false)
	main.call("_update_template_overlay")
	_check(checkboxes["Nearby"].button_pressed, "Toggling the template off stopped it from overwriting a manual checkbox change")
	_check(main.get("_template_overlay") == null, "Toggling the template off cleared the 3D overlay mesh")

func _init() -> void:
	_test_shape_math()
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_main = scene.instantiate()
	get_root().add_child(_main)

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_main_integration(_main)
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All AoE Template assertions passed")
		quit()
	return true
