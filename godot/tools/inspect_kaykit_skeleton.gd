extends SceneTree
## One-off inspection tool (not shipped) -- checks, before wiring anything into
## Token.gd, exactly what godot/assets/README.md's own KayKit section flagged
## as unverified: does Skeleton_Warrior.glb's skeleton actually share bone
## names with the Character Animations pack's Rig_Medium skeleton (a shared
## rig NAME alone doesn't guarantee shared bone names -- same lesson this
## project already learned the hard way for Quaternius's UAL1). Also lists
## every real animation clip name across the animation files being
## considered, the same "read the real list, don't guess" step that already
## caught Godot's "_Loop"-stripping behavior for Quaternius.

const SKELETON_MODEL := "res://assets/creatures/monster/skeleton_warrior.glb"
const ANIM_FILES := [
	"res://assets/creatures/animations/kaykit_rig_medium_special.glb",
	"res://assets/creatures/animations/kaykit_rig_medium_simulation.glb",
]

func _init() -> void:
	if not ResourceLoader.exists(SKELETON_MODEL):
		print("MISSING model: %s" % SKELETON_MODEL)
		quit(1)
		return

	var model_scene := load(SKELETON_MODEL) as PackedScene
	var model_instance := model_scene.instantiate() as Node3D
	get_root().add_child(model_instance)
	var model_skeletons := model_instance.find_children("*", "Skeleton3D", true, false)
	if model_skeletons.is_empty():
		print("Skeleton_Warrior.glb has no Skeleton3D at all")
		quit(1)
		return
	var model_skeleton := model_skeletons[0] as Skeleton3D
	var model_bone_names := {}
	for i in range(model_skeleton.get_bone_count()):
		model_bone_names[model_skeleton.get_bone_name(i)] = true
	print("Skeleton_Warrior.glb: %d bones" % model_skeleton.get_bone_count())

	for anim_path in ANIM_FILES:
		if not ResourceLoader.exists(anim_path):
			print("MISSING: %s" % anim_path)
			continue
		var anim_scene := load(anim_path) as PackedScene
		var anim_instance := anim_scene.instantiate() as Node3D
		get_root().add_child(anim_instance)

		var anim_skeletons := anim_instance.find_children("*", "Skeleton3D", true, false)
		var anim_players := anim_instance.find_children("*", "AnimationPlayer", true, false)
		if anim_skeletons.is_empty() or anim_players.is_empty():
			print("%s -- no Skeleton3D/AnimationPlayer found" % anim_path.get_file())
			anim_instance.queue_free()
			continue
		var anim_skeleton := anim_skeletons[0] as Skeleton3D
		var anim_player := anim_players[0] as AnimationPlayer

		var matched := 0
		for i in range(anim_skeleton.get_bone_count()):
			if model_bone_names.has(anim_skeleton.get_bone_name(i)):
				matched += 1
		print("%s -- anim skeleton %d bones, %d/%d match Skeleton_Warrior's names" % [
			anim_path.get_file(), anim_skeleton.get_bone_count(), matched, anim_skeleton.get_bone_count()
		])
		print("  clips: %s" % [anim_player.get_animation_list()])

		anim_instance.queue_free()

	quit()
