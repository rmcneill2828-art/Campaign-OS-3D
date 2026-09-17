extends SceneTree
## One-off inspection tool (not shipped) -- same discipline as
## inspect_kaykit_skeleton.gd: verify bone-name compatibility between the
## static character model and each animation file BEFORE wiring anything
## into Token.gd, and list each file's real clip name (post Godot-import).

const CHARACTER_MODEL := "res://assets/creatures/monster/orc_warrior.glb"
const ANIM_FILES := [
	"res://assets/creatures/animations/meshy_orc_idle.glb",
	"res://assets/creatures/animations/meshy_orc_walk.glb",
	"res://assets/creatures/animations/meshy_orc_death.glb",
	"res://assets/creatures/animations/meshy_orc_hit1.glb",
	"res://assets/creatures/animations/meshy_orc_hit2.glb",
	"res://assets/creatures/animations/meshy_orc_kneel.glb",
]

func _init() -> void:
	if not ResourceLoader.exists(CHARACTER_MODEL):
		print("MISSING model: %s" % CHARACTER_MODEL)
		quit(1)
		return

	var model_scene := load(CHARACTER_MODEL) as PackedScene
	var model_instance := model_scene.instantiate() as Node3D
	get_root().add_child(model_instance)
	var model_skeletons := model_instance.find_children("*", "Skeleton3D", true, false)
	if model_skeletons.is_empty():
		print("orc_warrior.glb has no Skeleton3D at all")
		quit(1)
		return
	var model_skeleton := model_skeletons[0] as Skeleton3D
	var model_bone_names := {}
	for i in range(model_skeleton.get_bone_count()):
		model_bone_names[model_skeleton.get_bone_name(i)] = true
	print("orc_warrior.glb: %d bones" % model_skeleton.get_bone_count())

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
		print("%s -- anim skeleton %d bones, %d/%d match orc_warrior's names; clips: %s" % [
			anim_path.get_file(), anim_skeleton.get_bone_count(), matched, anim_skeleton.get_bone_count(),
			anim_player.get_animation_list()
		])

		anim_instance.queue_free()

	quit()
