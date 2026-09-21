extends SceneTree
## Functional check for Spell effects (ROADMAP.md's "Seven requested features"
## 2026-09-19 entry, item 6, built 2026-09-21). Fixture strings for the "was this
## message a real cast" detection and the hit/miss/damage text it also reads are not
## hand-guessed: the cast_spell ones and the two cast_area_spell ones were captured
## from a real running engine-server instance (POST /action cast_spell/cast_area_spell
## against a throwaway state, never the real campaign save), the same way
## test_dice_roll.gd's own fixtures already were; the one critical-hit fixture is
## reconstructed from resolveOneAttack()'s own literal template in encounter.js
## (confirmed by reading that function directly this same pass) rather than captured,
## since forcing a real natural-20 roll isn't practical to script -- noted here so
## that distinction isn't lost.
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

func _test_is_spell_cast_message(main) -> void:
	# Captured live: POST /action {type:"cast_spell", caster:"Probe Caster", spell:"Fire Bolt",
	# level:0, target:"Probe Target", damageDice:"2d10", damageType:"fire"} (a hit)
	_check(main.call("_is_spell_cast_message", "Probe Caster casts Fire Bolt. Probe Caster's Fire Bolt attacks Probe Target: 16 + 8 = 24 vs AC 5. Hit. Damage 14 (2d10)."),
		"A successful targeted cantrip cast is recognized")

	# Captured live: same setup, a natural-1 miss.
	_check(main.call("_is_spell_cast_message", "Probe Caster casts Fire Bolt. Probe Caster's Fire Bolt attacks Probe Target: 1 + 8 = 9 vs AC 5. Miss."),
		"A successful cast that then misses its attack roll is still a real cast (only the impact effect should skip, not the cast flash)")

	# Captured live: POST /action {type:"cast_area_spell", ..., level:3, targets:[...], damageType:"fire"}
	_check(main.call("_is_spell_cast_message", "Probe Caster casts Fireball using a 3rd-level spell slot (1 remaining). Probe Target 1 rolls a DEX save: 20 +1 = 21 vs DC 15. Success. Probe Target 1 takes 9 damage (8d6). Probe Target 2 rolls a DEX save: 6 +1 = 7 vs DC 15. Failure. Probe Target 2 takes 19 damage (8d6)."),
		"A successful leveled area-spell cast (with its slot-spend clause) is recognized")

	# Captured live: POST /action {type:"cast_spell", level:0} with no spellcasting.attackBonus set.
	_check(main.call("_is_spell_cast_message", "Probe Caster casts Fire Bolt. (no stated spell attack bonus for Probe Caster -- attack roll skipped.)"),
		"A successful cast with no attack roll at all (no stated spell attack bonus) is still recognized")

	# Every failure string below is castSpell()/castAreaSpell()/spendSpellSlot()'s own
	# literal text in encounter.js -- none of them ever reach the "<name> casts" clause,
	# so none should match. The first is also captured live (POST /action cast_area_spell
	# against a caster seeded with 0 remaining 3rd-level slots).
	_check(not main.call("_is_spell_cast_message", "Probe Caster has no 3rd-level spell slots remaining."),
		"No spell slots remaining is correctly NOT a real cast")
	_check(not main.call("_is_spell_cast_message", "Darkhawk has already used their action this turn."),
		"Action economy block is correctly NOT a real cast")
	_check(not main.call("_is_spell_cast_message", "Spellcasting failed: caster was not found."),
		"Caster not found is correctly NOT a real cast")
	_check(not main.call("_is_spell_cast_message", "Area spell failed: no targets given."),
		"Area spell with no targets is correctly NOT a real cast")
	_check(not main.call("_is_spell_cast_message", "Darkhawk attacks Goblin 1: 14 + 8 = 22 vs AC 13. Hit. Damage 7 (1d8+3)."),
		"A plain (non-spell) attack message is correctly NOT a real cast")

func _test_token_id_by_name(main) -> void:
	var state := {
		"mapName": "Test Map",
		"maps": {"Test Map": {"columns": 12, "rows": 12, "feetPerSquare": 5.0}},
		"tokens": [
			{"id": "caster-1", "name": "Caster", "mapName": "Test Map", "type": "hero", "x": 2, "y": 2, "hp": 10, "maxHp": 10, "conditions": []},
			{"id": "target-1", "name": "Target", "mapName": "Test Map", "type": "monster", "x": 5, "y": 5, "hp": 10, "maxHp": 10, "conditions": []},
			{"id": "target-2", "name": "Target Two", "mapName": "Test Map", "type": "monster", "x": 6, "y": 6, "hp": 10, "maxHp": 10, "conditions": []}
		],
		"turn": {},
		"log": []
	}
	main.call("_apply_state", state)

	_check(main.call("_token_id_by_name", "Caster") == "caster-1", "_token_id_by_name resolves a real token's name to its id")
	_check(main.call("_token_id_by_name", "Target") == "target-1", "_token_id_by_name resolves the other real token too")
	_check(main.call("_token_id_by_name", "Nobody") == "", "_token_id_by_name returns empty for a name no live token has")

## `Object.set()` with a raw array LITERAL silently fails to assign into a statically
## typed `Array[String]` script property -- confirmed directly (a throwaway probe
## script): the property is left at its existing value with no error printed at all,
## since `.set()`'s reflection path doesn't perform the same implicit typed-array
## conversion a real static `x = [...]` assignment would. Passing an already-typed
## `Array[String]` local (declared with that exact type, carrying real type metadata
## at runtime, per the two small helpers below) works correctly -- that's why every
## _last_spell_target_ids assignment in this function goes through one of them rather
## than an inline literal straight into main.set().
func _typed_ids(ids: Array[String]) -> Array[String]:
	return ids

func _test_spawn_spell_effects(main) -> void:
	var tokens_root: Node = main
	main.set("_last_spell_caster_id", "caster-1")
	main.set("_last_spell_damage_type", "fire")

	# A successful cast with no target at all (a self-only buff, or simply nothing
	# selected) -- only the caster's own casting flash, no impact effect.
	main.set("_last_spell_target_ids", _typed_ids([]))
	var before := tokens_root.get_child_count()
	main.call("_try_show_spell_effects", ["Probe Caster casts Fire Bolt. (no stated spell attack bonus for Probe Caster -- attack roll skipped.)"])
	_check(tokens_root.get_child_count() == before + 1, "A targetless successful cast spawns exactly one effect (the caster's own cast flash)")

	# A targeted cast that MISSES -- still just the one caster flash, no impact effect
	# for a target that was never actually hit.
	main.set("_last_spell_target_ids", _typed_ids(["target-1"]))
	before = tokens_root.get_child_count()
	main.call("_try_show_spell_effects", ["Probe Caster casts Fire Bolt. Probe Caster's Fire Bolt attacks Probe Target: 1 + 8 = 9 vs AC 5. Miss."])
	_check(tokens_root.get_child_count() == before + 1, "A cast that misses its attack roll spawns only the caster flash, no impact effect")

	# A targeted cast that HITS -- caster flash AND a target impact effect: two.
	before = tokens_root.get_child_count()
	main.call("_try_show_spell_effects", ["Probe Caster casts Fire Bolt. Probe Caster's Fire Bolt attacks Probe Target: 16 + 8 = 24 vs AC 5. Hit. Damage 14 (2d10)."])
	_check(tokens_root.get_child_count() == before + 2, "A cast that hits its target spawns both the caster flash and a target impact effect")

	# A failed cast attempt (no slots left) -- nothing should spawn at all, even though
	# _last_spell_* is still (harmlessly) populated from the attempt.
	before = tokens_root.get_child_count()
	main.call("_try_show_spell_effects", ["Probe Caster has no 3rd-level spell slots remaining."])
	_check(tokens_root.get_child_count() == before, "A failed cast (no slots remaining) spawns nothing")

	# An area cast against two targets, one genuinely hit and one fully resisted
	# (halfOnSave: false, a successful save) -- caster flash + exactly ONE impact
	# effect (the resisted target gets none). Real captured text (see
	# _test_is_spell_cast_message above) confirms both the "<name> rolls a ... save"
	# and "<name> takes N damage"/"<name> takes no damage" shapes; this message
	# combines both real shapes against the two distinct targets seeded above.
	main.set("_last_spell_target_ids", _typed_ids(["target-1", "target-2"]))
	before = tokens_root.get_child_count()
	main.call("_try_show_spell_effects", ["Probe Caster casts Fireball using a 3rd-level spell slot (1 remaining). Target rolls a DEX save: 20 +1 = 21 vs DC 15. Success. Target takes no damage. Target Two rolls a DEX save: 6 +1 = 7 vs DC 15. Failure. Target Two takes 19 damage (8d6)."])
	_check(tokens_root.get_child_count() == before + 2, "An area cast with one resisted and one hit target spawns the caster flash plus exactly one impact effect")

func _test_visual(effect) -> void:
	effect.start(Color(1.0, 0.45, 0.1), Vector3(1, 2, 3), true, false)
	_check(effect.position == Vector3(1, 2, 3), "start() positions the effect at the given origin")
	var particles: GPUParticles3D = effect.get("_particles")
	_check(particles != null and is_instance_valid(particles), "start() creates a real GPUParticles3D")
	_check(particles.one_shot and particles.emitting, "The particle system is a one-shot burst that's actually emitting")
	var process_material: ParticleProcessMaterial = particles.process_material
	_check(process_material.color == Color(1.0, 0.45, 0.1), "The particle color matches the damage type's own color")
	_check(process_material.direction == Vector3(0, 1, 0), "rise:true aims the burst upward")
	_check(not effect.get("_freed"), "A freshly started effect hasn't cleaned itself up yet")

	# Force elapsed time past LIFETIME_SECONDS + CLEANUP_BUFFER_SECONDS in one call,
	# the same fast-forward technique test_dice_roll.gd's own _test_visual already uses
	# for DiceRollVisual's identical SETTLE_SECONDS/LINGER_SECONDS timer.
	effect.call("_process", 5.0)
	_check(effect.get("_freed"), "Enough elapsed time frees the effect")

func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_main = scene.instantiate()
	get_root().add_child(_main)

var _ran := false
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_is_spell_cast_message(_main)
	_test_token_id_by_name(_main)
	_test_spawn_spell_effects(_main)
	var effect := SpellEffect.new()
	get_root().add_child(effect)
	_test_visual(effect)
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All Spell Effect assertions passed")
		quit()
	return true
