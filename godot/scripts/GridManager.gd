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

## Kenney's Mini Dungeon floor piece -- CC0, committed to this repo (unlike the
## Quaternius character models), so this one CAN safely preload(). Its
## footprint is a 1x1 unit square, so a uniform scale of `cell_size` fills
## exactly one grid cell with no per-axis distortion -- but exactly where its
## top surface actually ends up after that scale is measured at runtime
## (_measure_top_offset), not assumed from the file's own raw bounds, which
## turned out not to match the real rendered result (see that function's
## comment). The goal either way is the same "floor top = ground level"
## convention every token/collision box in this project already assumes.
const FLOOR_TILE_PATH := "res://assets/Environment/dungeon-kit/Models/GLB format/floor.glb"
const FLOOR_DETAIL_TILE_PATH := "res://assets/Environment/dungeon-kit/Models/GLB format/floor-detail.glb"

var columns := 0
var rows := 0
var feet_per_square := 5.0
var cell_size := 5.0 * METERS_PER_FOOT

var _floor_body: StaticBody3D
var _light_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _tile_mesh: BoxMesh
var _floor_scene: PackedScene
var _floor_detail_scene: PackedScene

# Which hand-built map scene (if any, see build()'s own doc comment) is
# currently instantiated -- tracked separately from columns/rows/cell_size so
# build()'s own no-op-if-unchanged check also catches "same size map, but the
# DM switched to a different named map that happens to share that size,"
# which columns/rows/cell_size alone can't distinguish.
var _current_map_scene_path := ""
var _map_scene_instance: Node3D

func _ready() -> void:
	_light_material = StandardMaterial3D.new()
	_light_material.albedo_color = Color(0.78, 0.74, 0.66)
	_dark_material = StandardMaterial3D.new()
	_dark_material.albedo_color = Color(0.60, 0.56, 0.48)

	# Loaded once up front (not per-tile) since build() may instance dozens of
	# tiles -- checking/loading a resource that many times per rebuild would be
	# wasteful. Same missing-asset-safe pattern as Token.gd even though this
	# particular asset (CC0, committed to the repo) shouldn't normally be
	# missing -- cheap insurance against a future accidental gitignore mistake
	# or partial checkout, not expected to ever actually trigger the fallback.
	if ResourceLoader.exists(FLOOR_TILE_PATH):
		_floor_scene = load(FLOOR_TILE_PATH) as PackedScene
	if ResourceLoader.exists(FLOOR_DETAIL_TILE_PATH):
		_floor_detail_scene = load(FLOOR_DETAIL_TILE_PATH) as PackedScene

## Cell coordinates are 1-indexed, matching every token's x/y in the engine state.
func cell_to_world(x: int, y: int) -> Vector3:
	return Vector3((x - 0.5) * cell_size, 0.0, (y - 0.5) * cell_size)

func world_to_cell(world_pos: Vector3) -> Vector2i:
	var x := int(floor(world_pos.x / cell_size)) + 1
	var y := int(floor(world_pos.z / cell_size)) + 1
	return Vector2i(x, y)

func board_center() -> Vector3:
	return Vector3(columns * cell_size / 2.0, 0.0, rows * cell_size / 2.0)

## No-ops if nothing about the board's shape/scale/map has changed, so polling
## the same map every second doesn't rebuild (and visually flicker) the whole
## board on every tick.
##
## `map_scene_path` is the Phase 4 map-scene contract: when Main.gd resolves
## the server's current mapName to a real hand-built scene (see its own
## MAP_SCENES), that scene is instantiated here as the board's actual visual
## floor/walls/props, and this stops generating its own procedural floor
## tiles entirely -- but it still ALWAYS builds the invisible collision plane
## and the grid-line overlay itself, on top of whatever the map scene
## provides, exactly as planned: a hand-built map only needs to be geometry,
## not also reimplement click-to-move collision or grid readability. An
## empty path (any map name with no hand-built scene registered yet) falls
## back to the original fully-procedural floor, so a new/unmapped map still
## renders something instead of staying blank.
func build(new_columns: int, new_rows: int, new_feet_per_square: float = 5.0, map_scene_path: String = "") -> void:
	var new_cell_size := new_feet_per_square * METERS_PER_FOOT
	if new_columns == columns and new_rows == rows and is_equal_approx(new_cell_size, cell_size) \
			and map_scene_path == _current_map_scene_path and get_child_count() > 0:
		return
	columns = new_columns
	rows = new_rows
	feet_per_square = new_feet_per_square
	cell_size = new_cell_size
	_current_map_scene_path = map_scene_path

	for child in get_children():
		child.queue_free()
	_map_scene_instance = null

	if map_scene_path != "" and ResourceLoader.exists(map_scene_path):
		var map_scene := load(map_scene_path) as PackedScene
		_map_scene_instance = map_scene.instantiate() as Node3D
		add_child(_map_scene_instance)
	elif _floor_scene:
		_build_real_floor_tiles()
	else:
		_build_fallback_checkerboard()

	_build_grid_lines()
	_build_floor_collision()

## A real stone floor texture has no per-tile visual break the way the old
## flat-colored checkerboard did -- without this, a DM has no way to actually
## see where one grid cell ends and the next begins, which matters for reading
## movement/range at a glance. A thin unshaded line mesh just above the floor
## (GRID_LINE_HEIGHT keeps it from z-fighting with the floor surface) restores
## that regardless of which floor visual is active.
func _build_grid_lines() -> void:
	const GRID_LINE_HEIGHT := 0.01
	const GRID_LINE_COLOR := Color(1, 1, 1, 0.5)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	var width := columns * cell_size
	var depth := rows * cell_size
	for i in range(columns + 1):
		var x := i * cell_size
		surface.add_vertex(Vector3(x, GRID_LINE_HEIGHT, 0))
		surface.add_vertex(Vector3(x, GRID_LINE_HEIGHT, depth))
	for j in range(rows + 1):
		var z := j * cell_size
		surface.add_vertex(Vector3(0, GRID_LINE_HEIGHT, z))
		surface.add_vertex(Vector3(width, GRID_LINE_HEIGHT, z))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GRID_LINE_COLOR
	mesh_instance.material_override = material
	add_child(mesh_instance)

## Real Kenney floor pieces -- floor.glb everywhere, with floor-detail.glb
## dropped in on a fixed, deterministic subset of cells purely for visual
## variety (never randomized -- a random pick would reshuffle every time
## build() reruns, e.g. after a feetPerSquare change, which would look like the
## floor texture flickering/changing under the party for no in-fiction reason).
func _build_real_floor_tiles() -> void:
	# Measured once from the PLAIN floor tile only, then reused for
	# floor-detail too -- deliberately not measured per-scene. A first attempt
	# did measure floor-detail.glb separately and it came out visibly sunken
	# (a dark gap around every detail tile): that scene has raised rubble
	# props sitting ON TOP of the same base plate floor.glb has, so its own
	# highest point is the top of a rock, not the shared walkable surface --
	# using that as the seat reference pushed the whole tile down by the
	# rock's height. Both pieces are modular tile-kit-mates meant to sit at
	# the same base height so they tile interchangeably, so the plain tile's
	# measurement is the correct shared reference for both.
	var floor_offset := _measure_top_offset(_floor_scene)

	for gx in range(1, columns + 1):
		for gy in range(1, rows + 1):
			var use_detail := _floor_detail_scene and (gx * 7 + gy * 3) % 11 == 0
			var scene: PackedScene = _floor_detail_scene if use_detail else _floor_scene
			var tile := scene.instantiate() as Node3D
			tile.scale = Vector3(cell_size, cell_size, cell_size)
			tile.position = cell_to_world(gx, gy) - Vector3(0, floor_offset, 0)
			add_child(tile)

## Instantiates `scene` at the same scale real tiles use, just to measure how
## far above its own local origin its highest rendered point actually sits,
## then discards it. Deliberately NOT trusted from this model's raw glTF
## accessor bounds -- those suggested a plain 1x1x1 box with a bottom-center
## origin, which turned out to be wrong once actually rendered (same lesson
## Token.gd's _ground_model() learned the hard way: a file's authored
## coordinate space and Godot's final resolved position aren't guaranteed to
## match, e.g. via a parent node's own rotation/offset). Measuring the real
## thing after Godot has already resolved it is robust regardless of why.
func _measure_top_offset(scene: PackedScene) -> float:
	var probe := scene.instantiate() as Node3D
	probe.scale = Vector3(cell_size, cell_size, cell_size)
	add_child(probe)
	var highest_y := -INF
	for visual in probe.find_children("*", "VisualInstance3D", true, false):
		var mesh_instance := visual as VisualInstance3D
		var aabb: AABB = mesh_instance.get_aabb()
		for i in range(8):
			var world_corner: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(i)
			highest_y = max(highest_y, world_corner.y)
	remove_child(probe)
	probe.queue_free()
	return highest_y if is_finite(highest_y) else 0.0

## Only used if the real floor model is missing for some reason (see _ready())
## -- Phase 0's original flat-colored-box checkerboard.
func _build_fallback_checkerboard() -> void:
	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(cell_size - TILE_MARGIN, TILE_HEIGHT, cell_size - TILE_MARGIN)

	for gx in range(1, columns + 1):
		for gy in range(1, rows + 1):
			var tile := MeshInstance3D.new()
			tile.mesh = _tile_mesh
			tile.material_override = _light_material if (gx + gy) % 2 == 0 else _dark_material
			tile.position = cell_to_world(gx, gy) - Vector3(0, TILE_HEIGHT / 2.0, 0)
			add_child(tile)

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
