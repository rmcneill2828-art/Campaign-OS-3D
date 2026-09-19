extends SceneTree
## Functional check for Visual Dice Rolls (ROADMAP.md's "Seven requested features"
## 2026-09-19 entry, item 2). The four fixture strings below are not hand-guessed --
## each was captured from a REAL running engine-server instance (POST /action
## saving_throw/ability_check/roll_initiative, plain and with advantage/disadvantage),
## the same way engine-server's own tests/server.test.js already regex-asserts this
## exact wording. If encounter.js's own message wording ever changes upstream, this
## test (not just a silent client-side assumption) is what would catch the drift.
##
## See smoke_test_main.gd's own doc comment for why quit() is deferred to the first
## _process() tick rather than called synchronously in _init().

var _failures := 0
var _main

func _fail(message: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % message)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

func _test_extraction(main) -> void:
	# Captured live: POST /action {type:"saving_throw", target:"Darkhawk", ability:"DEX", dc:10}
	var plain_save: Dictionary = main.call("_extract_d20_rolls", "Darkhawk rolls a DEX save: 14 +2 = 16 vs DC 10. Success.")
	_check(plain_save.get("kept") == 14 and (plain_save.get("pair") as Array).is_empty(), "Plain saving throw: extracts the kept d20, no pair")

	# Captured live: same, + advantage:true
	var adv_save: Dictionary = main.call("_extract_d20_rolls", "Darkhawk rolls a DEX save: 18 (advantage: 18, 16) +2 = 20 vs DC 10. Success.")
	_check(adv_save.get("kept") == 18 and adv_save.get("pair") == [18, 16], "Advantage saving throw: extracts the kept d20 AND the raw [a, b] pair in roll order")

	# Captured live: POST /action {type:"ability_check", target:"Wren", skill:"Perception", dc:10, disadvantage:true}
	var dis_check: Dictionary = main.call("_extract_d20_rolls", "Wren rolls a Perception check: 1 (disadvantage: 15, 1) +1 = 2 vs DC 10. Failure.")
	_check(dis_check.get("kept") == 1 and dis_check.get("pair") == [15, 1], "Disadvantage ability check: extracts the kept (lower) d20 AND the raw pair")

	# Captured live: POST /action {type:"roll_initiative", target:"Darkhawk"}
	var initiative: Dictionary = main.call("_extract_d20_rolls", "Darkhawk rolls initiative: 18 +2 = 20.")
	_check(initiative.get("kept") == 18 and (initiative.get("pair") as Array).is_empty(), "Initiative roll: extracts the kept d20, no pair")

	# A real move/attack message must NOT spuriously match -- this pass explicitly
	# doesn't cover attack/damage dice (see _extract_d20_rolls()'s own doc comment).
	var no_match: Dictionary = main.call("_extract_d20_rolls", "Darkhawk attacks Goblin 1: 14 + 8 = 22 vs AC 13. Hit. Damage 7 (1d8+3).")
	_check(no_match.is_empty(), "An attack message (out of scope for this pass) is correctly NOT matched")
	var move_message: Dictionary = main.call("_extract_d20_rolls", "Darkhawk moves to (5, 5).")
	_check(move_message.is_empty(), "A plain move confirmation is correctly NOT matched")

func _test_spawning(main) -> void:
	var tokens_root: Node = main
	var before := tokens_root.get_child_count()
	main.call("_spawn_dice", {"kept": 14, "pair": []})
	_check(tokens_root.get_child_count() == before + 1, "A plain roll spawns exactly one DiceRollVisual")

	before = tokens_root.get_child_count()
	main.call("_spawn_dice", {"kept": 18, "pair": [18, 16]})
	_check(tokens_root.get_child_count() == before + 2, "An advantage/disadvantage pair spawns exactly two DiceRollVisual instances")

func _test_visual(die) -> void:
	die.start(14, Vector3(1, 2, 3), Color.RED)
	_check(die.get("_result") == 14, "start() records the real result")
	_check(die.get("_label").text == "14", "The Label3D shows the real result as text")
	_check(die.get("_body") != null and is_instance_valid(die.get("_body")), "start() creates a real RigidBody3D")
	_check(not die.get("_settled"), "A freshly started die hasn't settled yet")

	# Force elapsed time past SETTLE_SECONDS in one call rather than actually waiting
	# in real time -- _process() only accumulates whatever delta it's given, so this
	# is a legitimate way to fast-forward a physics-timed animation for a test.
	die.call("_process", 5.0)
	_check(die.get("_settled"), "Enough elapsed time settles the die")
	_check(die.get("_body").freeze, "A settled die freezes its RigidBody3D so physics can't move the shown result any further")

func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_main = scene.instantiate()
	get_root().add_child(_main)

var _ran := false
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_extraction(_main)
	_test_spawning(_main)
	var die := DiceRollVisual.new()
	get_root().add_child(die)
	_test_visual(die)
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All Visual Dice Roll assertions passed")
		quit()
	return true
