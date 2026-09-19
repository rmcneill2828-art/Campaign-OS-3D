extends SceneTree
## Functional check for the Character Creator panel (ROADMAP.md's "Seven requested
## features" 2026-09-19 entry, item 1). engine-server's own tests/createCharacter.test.js
## already covers the actual HTTP round trip against a simulated dm-bridge/watch.js;
## this covers the piece that lives only in Godot -- that _ready() actually builds every
## control, and that _character_draft_from_form() reads them into the exact draft shape
## characterCreator.js's validateDraft()/computeCharacter() (server-side) expect.
##
## See smoke_test_main.gd's own doc comment for why quit() is deferred to the first
## _process() tick rather than called synchronously in _init().

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

func _test_character_creator(main) -> void:
	_check(main.get("_cc_name") != null, "Main._ready() built the Character Creator controls (_cc_name exists)")
	_check(main.get("_cc_ability_inputs").size() == 6, "One SpinBox per ability score was built")
	_check(main.get("_cc_skill_checkboxes").size() == 18, "One checkbox per 5e skill was built")
	_check(main.get("_cc_class").item_count == 12, "Class dropdown has all 12 standard 5e classes")

	# Fill out a draft the same way a DM actually would, then read it back through
	# _character_draft_from_form() and confirm it matches characterDraftFromForm()'s own
	# shape in ui/app.js exactly -- field names, ability score dict, nested
	# personality/attack/spellcasting objects.
	main.get("_cc_name").text = "Kestrel"
	main.get("_cc_race").text = "Half-Elf"
	main.get("_cc_class").selected = 4 # CHARACTER_CLASS_LIST[4] == "Fighter"
	main.get("_cc_level").value = 3
	main.get("_cc_background").text = "Outlander"
	main.get("_cc_alignment").text = "Chaotic Good"
	var ability_inputs: Dictionary = main.get("_cc_ability_inputs")
	ability_inputs["STR"].value = 12
	ability_inputs["DEX"].value = 17
	ability_inputs["CON"].value = 14
	ability_inputs["INT"].value = 10
	ability_inputs["WIS"].value = 15
	ability_inputs["CHA"].value = 8
	var skill_checkboxes: Dictionary = main.get("_cc_skill_checkboxes")
	skill_checkboxes["Perception"].button_pressed = true
	skill_checkboxes["Survival"].button_pressed = true
	main.get("_cc_speed").value = 30
	main.get("_cc_weapon_name").text = "Longbow"
	main.get("_cc_weapon_dice").text = "1d8"
	main.get("_cc_traits").text = "Quiet"
	main.get("_cc_is_caster").button_pressed = false

	var draft: Dictionary = main.call("_character_draft_from_form")
	_check(draft["name"] == "Kestrel", "Draft carries the entered name")
	_check(draft["race"] == "Half-Elf", "Draft carries the entered race")
	_check(draft["className"] == "Fighter", "Draft's className reads the selected OptionButton item, not its index")
	_check(draft["level"] == 3, "Draft carries the entered level as an int")
	_check(draft["abilityScores"] == {"STR": 12, "DEX": 17, "CON": 14, "INT": 10, "WIS": 15, "CHA": 8}, "Draft's abilityScores dict matches every SpinBox")
	var profs: Array = draft["proficientSkills"]
	_check(profs.has("Perception") and profs.has("Survival") and profs.size() == 2, "Draft's proficientSkills lists exactly the checked boxes")
	_check(draft["attack"]["weaponName"] == "Longbow" and draft["attack"]["diceSize"] == "1d8", "Draft's attack sub-dict carries the weapon fields")
	_check(draft["personality"]["traits"] == "Quiet", "Draft's personality sub-dict carries the traits field")
	_check(not draft.has("spellcasting"), "Unchecked Spellcaster box means no spellcasting key at all (matches ui/app.js's own null, not an empty object)")

	main.get("_cc_is_caster").button_pressed = true
	main.get("_cc_spells_known").text = "Cure Wounds"
	draft = main.call("_character_draft_from_form")
	_check(draft.has("spellcasting") and draft["spellcasting"]["isCaster"] == true, "Checking Spellcaster adds a real spellcasting sub-dict")
	_check(draft["spellcasting"]["spellsKnown"] == "Cure Wounds", "spellcasting sub-dict carries the entered spells")

	# _on_cc_standard_array_pressed()/_on_cc_roll_scores_pressed() -- both just need to
	# actually reach every SpinBox without throwing; roll_scores' own randomness means the
	# only thing worth asserting is that it lands in 5e's real 3-18 range, not the exact
	# value.
	main.call("_on_cc_standard_array_pressed")
	_check(ability_inputs["STR"].value == 15 and ability_inputs["CHA"].value == 8, "Standard Array button assigns 15/14/13/12/10/8 across STR..CHA in order")
	main.call("_on_cc_roll_scores_pressed")
	var rolled: float = ability_inputs["STR"].value
	_check(rolled >= 3 and rolled <= 18, "Roll Scores produces a real 4d6-drop-lowest result (3-18)")

func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_main = scene.instantiate()
	get_root().add_child(_main)

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_character_creator(_main)
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All Character Creator assertions passed")
		quit()
	return true
