extends Node3D
class_name GridManager
## Builds the 3D board from the engine's own columns/rows/feetPerSquare
## (currentGrid()/feetPerSquare() on the server side) and converts between grid
## cell coordinates (1..columns / 1..rows, matching engine/encounter.js's
## token.x/token.y convention exactly) and world space. Purely visual +
## geometry -- never talks to the server itself.

## Meters per foot of in-fiction distance -- the D&D default of 5 ft/square
## therefore renders as a 2.0m tile, matching this project's original fixed
## visual scale exactly (Phase 0 shipped with CELL_SIZE = 2.0 hardcoded; this is
## that same number, now derived instead of assumed). A map with an unusual
## scale (Map Settings in the 2D app, e.g. 10 ft/square) renders bigger tiles
## instead of silently pretending everything is still 5 ft.
const METERS_PER_FOOT := 0.4
const TILE_MARGIN := 0.06
const TILE_HEIGHT := 0.1

var columns := 0
var rows := 0
var feet_per_square := 5.0
var cell_size := 5.0 * METERS_PER_FOOT

var _floor_body: StaticBody3D
var _light_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _tile_mesh: BoxMesh

func _ready() -> void:
	_light_material = StandardMaterial3D.new()
	_light_material.albedo_color = Color(0.78, 0.74, 0.66)
	_dark_material = StandardMaterial3D.new()
	_dark_material.albedo_color = Color(0.60, 0.56, 0.48)

## Cell coordinates are 1-indexed, matching every token's x/y in the engine state.
func cell_to_world(x: int, y: int) -> Vector3:
	return Vector3((x - 0.5) * cell_size, 0.0, (y - 0.5) * cell_size)

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var x := int(floor(world_pos.x / cell_size)) + 1
	var y := int(floor(world_pos.z / cell_size)) + 1
	return Vector2i(x, y)

func board_center() -> Vector3:
	return Vector3(columns * cell_size / 2.0, 0.0, rows * cell_size / 2.0)

## No-ops if nothing about the board's shape/scale has changed, so polling the
## same map every second doesn't rebuild (and visually flicker) the whole board
## on every tick.
func build(new_columns: int, new_rows: int, new_feet_per_square: float = 5.0) -> void:
	var new_cell_size := new_feet_per_square * METERS_PER_FOOT
	if new_columns == columns and new_rows == rows and is_equal_approx(new_cell_size, cell_size) and get_child_count() > 0:
		return
	columns = new_columns
	rows = new_rows
	feet_per_square = new_feet_per_square
	cell_size = new_cell_size

	for child in get_children():
		child.queue_free()

	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(cell_size - TILE_MARGIN, TILE_HEIGHT, cell_size - TILE_MARGIN)

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
	box.size = Vector3(columns * cell_size, TILE_HEIGHT, rows * cell_size)
	shape.shape = box
	_floor_body.position = board_center() - Vector3(0, TILE_HEIGHT / 2.0, 0)
	_floor_body.add_child(shape)
	add_child(_floor_body)
