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
## name/HP label should float above this model's own feet, in meters}. Real
## models are authored with their feet at local y=0 already (confirmed by
# reading their glTF accessor bounds directly), so they need no extra offset
## when parented under Body/ModelRoot, unlike the fallback capsule below.
const MODEL_CONFIG := {
	"hero": {"path": "res://assets/creatures/hero/superhero_male.gltf", "label_height": 2.0},
	"monster": {"path": "res://assets/creatures/monster/imp.glb", "label_height": 1.9}
}
const FALLBACK_LABEL_HEIGHT := 1.9
const FALLBACK_CAPSULE_RADIUS := 0.4
const FALLBACK_CAPSULE_HEIGHT := 1.6

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

	var config: Dictionary = MODEL_CONFIG.get(token_type, {})
	var model_path: String = config.get("path", "")

	if model_path != "" and ResourceLoader.exists(model_path):
		var scene := load(model_path) as PackedScene
		_model_root.add_child(scene.instantiate())
		_label.position.y = float(config.get("label_height", FALLBACK_LABEL_HEIGHT))
	else:
		_add_fallback_capsule()
		_label.position.y = FALLBACK_LABEL_HEIGHT

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
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, 0.35).set_trans(Tween.TRANS_SINE)
