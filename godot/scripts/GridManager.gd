extends Node3D
class_name GridManager
## Builds the 3D board from the engine's own columns/rows (currentGrid() on the
## server side) and converts between grid cell coordinates (1..columns / 1..rows,
## matching engine/encounter.js's token.x/token.y convention exactly) and world
## space. Purely visual + geometry -- never talks to the server itself.
##
## NOTE: CELL_SIZE is a fixed visual scale (meters per square), independent of the
## engine's own feetPerSquare (Map Settings in the 2D app) -- movement RULES still
## come entirely from the server (gridMoveCost, speed, etc.), this only decides how
## big a square looks. Tying the two together is a good Phase-1 follow-up once the
## camera/grid/token pipeline itself is proven out -- see ../../ROADMAP.md.

const CELL_SIZE := 2.0
const TILE_MARGIN := 0.06
const TILE_HEIGHT := 0.1

var columns := 0
var rows := 0

var _floor_body: StaticBody3D
var _light_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _tile_mesh: BoxMesh

func _ready() -> void:
	_light_material = StandardMaterial3D.new()
	_light_material.albedo_color = Color(0.78, 0.74, 0.66)
	_dark_material = StandardMaterial3D.new()
	_dark_material.albedo_color = Color(0.60, 0.56, 0.48)
	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(CELL_SIZE - TILE_MARGIN, TILE_HEIGHT, CELL_SIZE - TILE_MARGIN)

## Cell coordinates are 1-indexed, matching every token's x/y in the engine state.
func cell_to_world(x: int, y: int) -> Vector3:
	return Vector3((x - 0.5) * CELL_SIZE, 0.0, (y - 0.5) * CELL_SIZE)

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var x := int(floor(world_pos.x / CELL_SIZE)) + 1
	var y := int(floor(world_pos.z / CELL_SIZE)) + 1
	return Vector2i(x, y)

func board_center() -> Vector3:
	return Vector3(columns * CELL_SIZE / 2.0, 0.0, rows * CELL_SIZE / 2.0)

## No-ops if the size hasn't changed, so polling the same map every second doesn't
## rebuild (and visually flicker) the whole board on every tick.
func build(new_columns: int, new_rows: int) -> void:
	if new_columns == columns and new_rows == rows and get_child_count() > 0:
		return
	columns = new_columns
	rows = new_rows

	for child in get_children():
		child.queue_free()

	for gx in range(1, columns + 1):
		for gy in range(1, rows + 1):
			var tile := MeshInstance3D.new()
			tile.mesh = _tile_mesh
			tile.material_override = _light_material if (gx + gy) % 2 == 0 else _dark_material
			tile.position = cell_to_world(gx, gy) - Vector3(0, TILE_HEIGHT / 2.0, 0)
			add_child(tile)

	_build_floor_collision()

## One flat collision box under the whole board, used only so Main.gd's click
## raycast has something to hit and read a world position back from -- not meant
## to model real 3D terrain height (a later phase, see ROADMAP.md).
func _build_floor_collision() -> void:
	if _floor_body:
		_floor_body.queue_free()
	_floor_body = StaticBody3D.new()
	_floor_body.add_to_group("floor")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(columns * CELL_SIZE, TILE_HEIGHT, rows * CELL_SIZE)
	shape.shape = box
	_floor_body.position = board_center() - Vector3(0, TILE_HEIGHT / 2.0, 0)
	_floor_body.add_child(shape)
	add_child(_floor_body)
