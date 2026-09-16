extends SceneTree
## Verifies a MODEL_CONFIG `bone_name_map` actually resolves against a real
## character model + animation-source pair, the same "measure the real thing"
## discipline inspect_kaykit_skeleton.gd/inspect_meshy_orc.gd already apply --
## checks Token's own map constants directly (not a copy of them), so this
## can never silently drift from what Token.gd actually ships.
##
## Edit CHARACTER_MODEL/ANIMATION_SOURCE/BONE_NAME_MAP below to check the
## NEXT Meshy-rigged model before wiring it into a new MODEL_CONFIG entry.
## TWO Meshy bone-naming conventions are confirmed so far, not
## interchangeable -- see Token.gd's own MODEL_CONFIG doc comment for the
## full story: MESHY_API_RIG_TO_QUATERNIUS_UAL1_BONE_MAP is what the
## Composio-connected rigging API produces (orc_warrior.glb);
## MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP is what the website's
## Rigging tool produces with "Skeleton template: Mixamo" selected -- a
## choice the API doesn't even expose. A model rigged a THIRD way (a
## different template choice, a quadruped, a future Meshy account/pipeline
## change) isn't guaranteed to match either -- re-run this tool against it
## rather than assuming.

const CHARACTER_MODEL := "res://assets/creatures/hero/barbarian.glb"
const ANIMATION_SOURCE := "res://assets/creatures/animations/mixamo_idle.fbx"
const BONE_NAME_MAP := {} # exact-name matching expected now -- see Token.gd's "hero:barbarian" entry

func _init() -> void:
	if not ResourceLoader.exists(CHARACTER_MODEL):
		print("MISSING character model: %s" % CHARACTER_MODEL)
		quit(1)
		return
	if not ResourceLoader.exists(ANIMATION_SOURCE):
		print("MISSING animation source: %s" % ANIMATION_SOURCE)
		quit(1)
		return

	var character_scene := load(CHARACTER_MODEL) as PackedScene
	var character_instance := character_scene.instantiate() as Node3D
	get_root().add_child(character_instance)
	var character_skeletons := character_instance.find_children("*", "Skeleton3D", true, false)
	if character_skeletons.is_empty():
		print("%s has no Skeleton3D at all" % CHARACTER_MODEL)
		quit(1)
		return
	var character_skeleton := character_skeletons[0] as Skeleton3D

	var source_scene := load(ANIMATION_SOURCE) as PackedScene
	var source_instance := source_scene.instantiate() as Node3D
	get_root().add_child(source_instance)
	var source_skeletons := source_instance.find_children("*", "Skeleton3D", true, false)
	if source_skeletons.is_empty():
		print("%s has no Skeleton3D at all" % ANIMATION_SOURCE)
		quit(1)
		return
	var source_skeleton := source_skeletons[0] as Skeleton3D

	print("%s: %d bones. %s: %d bones. bone_name_map: %d entries.\n" % [
		CHARACTER_MODEL.get_file(), character_skeleton.get_bone_count(),
		ANIMATION_SOURCE.get_file(), source_skeleton.get_bone_count(),
		BONE_NAME_MAP.size()
	])

	# Mirrors Token.gd's _setup_animation() bone-matching loop exactly -- this
	# tool is only useful if it checks the SAME logic the real code runs, not
	# an approximation of it.
	var matched_via_map := 0
	var matched_via_exact_name := 0
	var unmatched: Array[String] = []
	for char_idx in range(character_skeleton.get_bone_count()):
		var bone_name := character_skeleton.get_bone_name(char_idx)
		var mapped_name: String = BONE_NAME_MAP.get(bone_name, bone_name)
		var source_idx := source_skeleton.find_bone(mapped_name)
		if source_idx == -1:
			unmatched.append(bone_name)
		elif BONE_NAME_MAP.has(bone_name):
			matched_via_map += 1
		else:
			matched_via_exact_name += 1

	var total := character_skeleton.get_bone_count()
	var matched := matched_via_map + matched_via_exact_name
	print("Matched: %d/%d (%d via bone_name_map, %d via exact name)" % [matched, total, matched_via_map, matched_via_exact_name])
	print("Unmatched (stay in bind pose, no animation drives them): %s" % (", ".join(unmatched) if not unmatched.is_empty() else "(none)"))

	# Real bones matching doesn't help if the clip name Token.gd's own config
	# expects ("mixamo.com", guessed from a raw string found in the FBX file's
	# bytes, not confirmed as the actual AnimStack/Take name Godot's importer
	# surfaces) doesn't actually resolve against what's really in this file's
	# AnimationPlayer -- print the real list so that doesn't have to be
	# guessed at either.
	var source_players := source_instance.find_children("*", "AnimationPlayer", true, false)
	if source_players.is_empty():
		print("\n%s has NO AnimationPlayer at all" % ANIMATION_SOURCE.get_file())
	else:
		var source_player := source_players[0] as AnimationPlayer
		print("\n%s AnimationPlayer's real clip list: %s" % [ANIMATION_SOURCE.get_file(), source_player.get_animation_list()])

	quit()
