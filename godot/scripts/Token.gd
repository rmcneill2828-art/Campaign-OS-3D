extends Node3D
class_name Token
## One 3D miniature. Deliberately dumb -- it only renders whatever `apply_data()`
## is given each poll and reports its own click via the "Body" StaticBody3D's group
## membership; Main.gd owns all selection/movement decisions and talks to the
## server. Placeholder geometry only (a capsule + a floating name/HP label) -- swap
## the mesh for a real glTF model per creature type once the pipeline is proven out
## (see ../../ROADMAP.md's asset-pipeline phase).

@onready var _mesh_instance: MeshInstance3D = $Body/MeshInstance3D
@onready var _label: Label3D = $NameLabel
@onready var _selection_ring: MeshInstance3D = $SelectionRing
@onready var _body: StaticBody3D = $Body

var token_id := ""
var token_name := ""
var token_type := "hero"
var grid_x := 1
var grid_y := 1
var hp := 0
var max_hp := 1

var _initialized := false
var _move_tween: Tween

func _ready() -> void:
	_body.add_to_group("tokens")
	_body.set_meta("token", self)

## `data` is one token object straight out of the engine's own state.tokens array
## (see engine-server/engine/encounter.js) -- same field names, no translation layer.
func apply_data(data: Dictionary, grid: GridManager) -> void:
	token_id = str(data.get("id", token_id))
	token_name = str(data.get("name", token_name))
	token_type = str(data.get("type", token_type))
	hp = int(data.get("hp", hp))
	max_hp = int(max(data.get("maxHp", max(hp, 1)), 1))

	_label.text = "%s\n%d/%d HP" % [token_name, hp, max_hp]

	var color := Color(0.30, 0.52, 0.92) if token_type == "hero" else Color(0.82, 0.24, 0.22)
	if hp <= 0:
		color = Color(0.28, 0.28, 0.28) # a dead/unconscious token reads as visibly greyed out
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	_mesh_instance.material_override = material

	var new_x := int(data.get("x", grid_x))
	var new_y := int(data.get("y", grid_y))
	var target: Vector3 = grid.cell_to_world(new_x, new_y) + Vector3(0, 0.8, 0)
	var moved := _initialized and (new_x != grid_x or new_y != grid_y)
	grid_x = new_x
	grid_y = new_y

	if moved:
		_animate_to(target)
	else:
		position = target
	_initialized = true

func set_selected(is_selected: bool) -> void:
	_selection_ring.visible = is_selected

func _animate_to(target: Vector3) -> void:
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, 0.35).set_trans(Tween.TRANS_SINE)
