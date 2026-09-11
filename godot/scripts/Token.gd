extends Node3D
class_name Token
## One 3D miniature. Deliberately dumb -- it only renders whatever `apply_data()`
## is given each poll and reports its own click via the "Body" StaticBody3D's group
## membership; Main.gd owns all selection/movement decisions and talks to the
## server.
##
## Model loading is intentionally NOT preload() -- the real creature models
## (Quaternius, Phase 2) are licensed for use but NOT committed to this git repo
## (see godot/assets/README.md: their license permits using them in a game,
## but not redistributing the raw asset files themselves, which committing them
## to a repo would risk). A fresh clone without those files re-downloaded must
## still open and run -- just with the plain colored-capsule placeholder Phase 0
## shipped with -- rather than fail to load the scene at all. `load()` +
## `ResourceLoader.exists()` achieves that; `preload()` would not.

## token type -> {path: model scene to instance, label_height: where the
## name/HP label should float above this model's own feet, in meters}.
## Whatever vertical offset a real model needs to actually stand on the floor
## is figured out at runtime, not assumed here -- see _ground_model() below.
const MODEL_CONFIG := {
	"hero": {"path": "res://assets/creatures/hero/superhero_male.gltf", "label_height": 2.0},
	"monster": {"path": "res://assets/creatures/monster/imp.glb", "label_height": 1.9}
}
const FALLBACK_LABEL_HEIGHT := 1.9
const FALLBACK_CAPSULE_RADIUS := 0.4
const FALLBACK_CAPSULE_HEIGHT := 1.6

## Quaternius's free "Universal Animation Library" (UAL1, non-root-motion
## variant -- our own tween already drives grid position, so we want the
## animation itself moving limbs in place, not also translating the root
## bone). Confirmed by direct comparison (not assumed from the "Retargetable"
## marketing tag) that its skeleton's bone NAMES match the hero model's
## exactly, and the monster model's bones are a strict subset of the same set
## -- so this one animation source can drive both. See _setup_animation().
const ANIMATION_SOURCE_PATH := "res://assets/creatures/animations/mannequin_animations.glb"
# Not "Idle_Loop"/"Walk_Loop" -- confirmed via this project's own diagnostic
# print() that Godot's glTF importer strips a trailing "_Loop" from an
# animation's name and folds that into the clip's own loop_mode property
# instead, so the actually-imported names are just "Idle"/"Walk".
const IDLE_ANIMATION := "Idle"
const WALK_ANIMATION := "Walk"

@onready var _model_root: Node3D = $Body/ModelRoot
@onready var _label: Label3D = $NameLabel
@onready var _selection_ring: MeshInstance3D = $SelectionRing
@onready var _body: StaticBody3D = $Body

var token_id := ""
var token_name := ""
var token_type := ""
var grid_x := 1
var grid_y := 1
var hp := 0
var max_hp := 1

var _initialized := false
var _move_tween: Tween
# Set only while the fallback capsule is the active visual (null once a real
# model is loaded) -- lets HP-driven color react every poll without rebuilding
# the whole model tree each time (see _update_fallback_color below).
var _fallback_mesh: MeshInstance3D

# Animation state -- see _setup_animation(). All null/empty whenever the
# fallback capsule is active (no skeleton to animate) or the animation source
# asset isn't present.
var _character_skeleton: Skeleton3D
var _anim_source_skeleton: Skeleton3D
var _anim_source_player: AnimationPlayer
var _bone_map := {} # character bone index -> animation-source bone index
var _idle_animation_key := "" # resolved AnimationPlayer key, see _resolve_animation_name()
var _walk_animation_key := ""

func _ready() -> void:
	_body.add_to_group("tokens")
	_body.set_meta("token", self)

## `data` is one token object straight out of the engine's own state.tokens array
## (see engine-server/engine/encounter.js) -- same field names, no translation layer.
func apply_data(data: Dictionary, grid: GridManager) -> void:
	token_id = str(data.get("id", token_id))
	token_name = str(data.get("name", token_name))
	var new_type: String = str(data.get("type", token_type))
	hp = int(data.get("hp", hp))
	max_hp = int(max(data.get("maxHp", max(hp, 1)), 1))

	_label.text = "%s\n%d/%d HP" % [token_name, hp, max_hp]

	if not _initialized or new_type != token_type:
		token_type = new_type
		_rebuild_model()
	_update_fallback_color() # a real model's own texture is left alone; only the fallback capsule reacts to HP

	# Grid cell -> world space directly, no extra vertical offset -- Body's own
	# children (the collision capsule, the fallback mesh) each carry whatever
	# local Y offset THEY need; adding one here too was a Phase 0/1 bug that
	# left every token floating 0.8m above the floor (harmless-looking with a
	# capsule, would have been obviously wrong once real ground-touching models
	# were added, so fixed now rather than papering over it with a matching
	# offset on the new models).
	var target: Vector3 = grid.cell_to_world(int(data.get("x", grid_x)), int(data.get("y", grid_y)))
	var moved := _initialized and (int(data.get("x", grid_x)) != grid_x or int(data.get("y", grid_y)) != grid_y)
	grid_x = int(data.get("x", grid_x))
	grid_y = int(data.get("y", grid_y))

	if moved:
		_animate_to(target)
	else:
		position = target
	_initialized = true

func _rebuild_model() -> void:
	for child in _model_root.get_children():
		child.queue_free()
	_fallback_mesh = null
	_character_skeleton = null
	_anim_source_skeleton = null
	_anim_source_player = null
	_bone_map.clear()
	_idle_animation_key = ""
	_walk_animation_key = ""

	var config: Dictionary = MODEL_CONFIG.get(token_type, {})
	var model_path: String = config.get("path", "")

	if model_path != "" and ResourceLoader.exists(model_path):
		var scene := load(model_path) as PackedScene
		var instance := scene.instantiate() as Node3D
		_model_root.add_child(instance)
		_ground_model(instance)
		_setup_animation(instance)
		_label.position.y = float(config.get("label_height", FALLBACK_LABEL_HEIGHT))
	else:
		_add_fallback_capsule()
		_label.position.y = FALLBACK_LABEL_HEIGHT

## Drives `instance`'s skeleton from a SEPARATE, hidden instance of the shared
## animation-source model (see ANIMATION_SOURCE_PATH), copying bone poses
## across every frame by matching bone NAMES between the two skeletons --
## deliberately not attempting to graft the source's Animation resources
## directly onto this model's own (nonexistent) AnimationPlayer via NodePath
## surgery, which would depend on Godot's glTF importer producing byte-for-byte
## identical scene structure across every different file, an assumption this
## project has already been burned by more than once this phase (see
## _ground_model's and GridManager.gd's own comments on trusting file
## structure over measuring the real thing). Copying bone-by-bone through each
## Skeleton3D's own pose API works regardless of how either scene happens to
## be structured around its skeleton.
func _setup_animation(instance: Node3D) -> void:
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_character_skeleton = skeletons[0] as Skeleton3D

	if not ResourceLoader.exists(ANIMATION_SOURCE_PATH):
		return
	var source_scene := load(ANIMATION_SOURCE_PATH) as PackedScene
	var source_instance := source_scene.instantiate() as Node3D
	source_instance.visible = false # only its skeleton/player matter -- never rendered itself
	_model_root.add_child(source_instance)

	var source_skeletons := source_instance.find_children("*", "Skeleton3D", true, false)
	var source_players := source_instance.find_children("*", "AnimationPlayer", true, false)
	if source_skeletons.is_empty() or source_players.is_empty():
		return
	_anim_source_skeleton = source_skeletons[0] as Skeleton3D
	_anim_source_player = source_players[0] as AnimationPlayer

	for char_idx in range(_character_skeleton.get_bone_count()):
		var bone_name := _character_skeleton.get_bone_name(char_idx)
		var source_idx := _anim_source_skeleton.find_bone(bone_name)
		if source_idx != -1:
			_bone_map[char_idx] = source_idx

	# Resolved once here rather than assumed as bare "Idle_Loop"/"Walk_Loop" --
	# a glTF import can namespace its animations under a named AnimationLibrary
	# (yielding a key like "somelib/Idle_Loop") rather than the default
	# unnamed one, and has_animation()/play() need the exact key either way.
	_idle_animation_key = _resolve_animation_name(_anim_source_player, IDLE_ANIMATION)
	_walk_animation_key = _resolve_animation_name(_anim_source_player, WALK_ANIMATION)

	# "_Loop"-suffixed clips in this pack aren't necessarily flagged to loop by
	# default on import -- force it so Idle/Walk actually repeat instead of
	# freezing on their last frame.
	for key in [_idle_animation_key, _walk_animation_key]:
		if key != "":
			_anim_source_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR

	print("Token %s: animation bone map covers %d/%d bones (%s); idle=%s walk=%s%s" % [
		token_name, _bone_map.size(), _character_skeleton.get_bone_count(),
		"looks complete" if _bone_map.size() == _character_skeleton.get_bone_count() else "some bones unmatched -- check names",
		_idle_animation_key if _idle_animation_key != "" else "NOT FOUND",
		_walk_animation_key if _walk_animation_key != "" else "NOT FOUND",
		"; available: %s" % [_anim_source_player.get_animation_list()] if _idle_animation_key == "" or _walk_animation_key == "" else ""
	])

	_play_source_animation(_idle_animation_key)

## `anim_name` is the bare clip name (e.g. "Idle_Loop"); returns the exact key
## `AnimationPlayer.play()`/`has_animation()` need, which may be namespaced
## under a library ("somelib/Idle_Loop") -- or "" if no match exists at all.
func _resolve_animation_name(player: AnimationPlayer, anim_name: String) -> String:
	for candidate in player.get_animation_list():
		if candidate == anim_name or candidate.ends_with("/" + anim_name):
			return candidate
	return ""

func _play_source_animation(anim_key: String) -> void:
	if anim_key != "" and _anim_source_player and _anim_source_player.current_animation != anim_key:
		_anim_source_player.play(anim_key)

func _process(_delta: float) -> void:
	if not (_character_skeleton and _anim_source_skeleton):
		return
	for char_idx in _bone_map:
		var source_idx: int = _bone_map[char_idx]
		_character_skeleton.set_bone_pose_position(char_idx, _anim_source_skeleton.get_bone_pose_position(source_idx))
		_character_skeleton.set_bone_pose_rotation(char_idx, _anim_source_skeleton.get_bone_pose_rotation(source_idx))
		_character_skeleton.set_bone_pose_scale(char_idx, _anim_source_skeleton.get_bone_pose_scale(source_idx))

## Shifts `instance` up/down so the lowest point of its actual rendered
## geometry sits exactly at this token's own ground level (y=0 in ModelRoot's
## local space, which has no offset of its own -- see the class comment).
##
## Deliberately NOT relying on the model file's own raw mesh vertex bounds --
## a first attempt at this trusted glTF accessor min/max values read directly
## from the file (feet at ~y=0 in mesh-local space) and still rendered
## floating in Godot. The actual cause: both character rigs used here have a
## skeleton root bone with a baked-in -90 degree rotation (a Z-up/Y-up
## conversion artifact from whatever tool exported them), which changes a
## skinned mesh's final bind-pose position in a way raw accessor data alone
## doesn't capture -- reproducing that math by hand for every differently
## authored rig would be fragile. Measuring the actual instantiated node's
## real AABB after Godot has already resolved the skin is robust regardless of
## why a given model doesn't start at its own local origin.
func _ground_model(instance: Node3D) -> void:
	var lowest_y := INF
	for visual in instance.find_children("*", "VisualInstance3D", true, false):
		var mesh_instance := visual as VisualInstance3D
		var aabb: AABB = mesh_instance.get_aabb()
		for i in range(8):
			var world_corner: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(i)
			lowest_y = min(lowest_y, world_corner.y)
	if is_finite(lowest_y):
		instance.position.y -= lowest_y

## Plain colored capsule -- Phase 0's original placeholder, now only used when
## the real model for this token type isn't available (see the class comment).
func _add_fallback_capsule() -> void:
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = FALLBACK_CAPSULE_RADIUS
	capsule.height = FALLBACK_CAPSULE_HEIGHT
	mesh_instance.mesh = capsule
	mesh_instance.position = Vector3(0, FALLBACK_CAPSULE_HEIGHT / 2.0, 0)
	mesh_instance.material_override = StandardMaterial3D.new()
	_model_root.add_child(mesh_instance)
	_fallback_mesh = mesh_instance

## Unlike a real model (which keeps its own textures untouched -- a real
## model's "dead" look is a later phase), the fallback capsule tints grey at 0
## HP. Runs every apply_data() call (cheap -- just a material color write), not
## only when the model is first built, so HP dropping to 0 later in play still
## updates it without needing a full model rebuild.
func _update_fallback_color() -> void:
	if not _fallback_mesh:
		return
	var color := Color(0.30, 0.52, 0.92) if token_type == "hero" else Color(0.82, 0.24, 0.22)
	if hp <= 0:
		color = Color(0.28, 0.28, 0.28)
	(_fallback_mesh.material_override as StandardMaterial3D).albedo_color = color

func set_selected(is_selected: bool) -> void:
	_selection_ring.visible = is_selected

func _animate_to(target: Vector3) -> void:
	if _move_tween:
		_move_tween.kill()
	_play_source_animation(_walk_animation_key)
	_face_direction(target - position)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, 0.35).set_trans(Tween.TRANS_SINE)
	_move_tween.finished.connect(_play_source_animation.bind(_idle_animation_key))

## Turns the whole token (an instant snap-turn, then the position tween moves
## it -- not a smooth turn-while-walking, a deliberately simpler first cut) to
## face the direction it's about to move. Uses Node3D's own look_at() rather
## than hand-derived trig specifically to remove one whole class of mistake
## this project has already hit more than once this phase (getting an axis/
## sign wrong by reasoning about it instead of using a well-tested built-in).
## The one thing look_at() can't remove: whether this model's own AUTHORED
## "forward" actually IS Godot's -Z convention look_at() assumes -- if
## characters turn out visibly backward or sideways once seen, that's the
## remaining possible mismatch, fixable with a single rotation.y += PI (or
## PI/2) here rather than reworking this function's logic.
func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	look_at(global_position + direction, Vector3.UP)
