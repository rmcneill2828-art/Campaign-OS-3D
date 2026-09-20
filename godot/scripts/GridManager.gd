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

## Generated wall geometry (see _build_walls()) -- a real wall-model piece per
## encounter.js's own {x1,y1,x2,y2} wall segment when one is available (see
## WALL_MODEL_PATH below), a plain stone-gray box otherwise. 10 ft is a
## typical room wall height, not an SRD rule this project models elsewhere.
const WALL_HEIGHT_FEET := 10.0
const WALL_THICKNESS := 0.15

## A real dungeon-wall .glb from this machine's Meshy model-sourcing library
## (I:\Campaign-OS-3D\Downloaded Static Models\, see that folder's own
## campaign-os-3d-models-progress.md) -- kept OUTSIDE this repo and loaded at
## RUNTIME via GLTFDocument (CharacterViewer.gd's own `_load_external_glb()`
## pattern), same as MapImagePath.gd's raster map images and for the same
## reason: Meshy-sourced content, unlike the Kenney/KayKit CC0 packs already
## committed under assets/Environment/, isn't safe to redistribute inside this
## git repo. EXPLICITLY PROVISIONAL and this-machine-specific, same as
## MapImagePath.gd's own resolution convention -- a clone on another machine
## just won't have this path, which _ready() below handles by falling back to
## the original plain-box wall (see _has_real_wall_model).
##
## This exact file is a Meshy "Resize" re-export of an earlier candidate
## (Height forced to exactly 4.0m, Origin: Bottom), specifically so its
## height would already be correct and _build_walls() would only ever need
## to scale the length axis -- the earlier, un-resized candidate was only
## ~0.77m tall, and non-uniformly stretching that ~5x to reach a real wall's
## height would have visibly distorted the stone texture (confirmed by
## measuring several candidates' real AABBs before picking one, not by
## eyeballing a thumbnail). Its real size is still measured at runtime into
## _wall_model_size below, not trusted from the resize dialog's own claimed
## number -- same "don't trust the file's claimed bounds" discipline
## _measure_top_offset() already established for the floor tiles.
const WALL_MODEL_PATH := "I:/Campaign-OS-3D/Downloaded Static Models/Environment/Walls/Meshy_AI_Meshy_AI_a_wall_made_rm_0920162632_texture.glb"

## Same external-library/runtime-loading story as WALL_MODEL_PATH above, for a
## real door instead of a real wall. Picked by rendering several candidates
## side by side (not from filenames) -- a sturdy iron-banded plank door read
## as the most "dungeon hideout" fitting of the set, over plainer or more
## ornate/gothic alternatives. The first (un-resized) version of this file
## was left at its own authored ~2.0m height -- looked believable as a door
## in isolation, but sitting in a full 4m-tall wall GAP (this engine has no
## separate lintel/archway geometry to visually cap a doorway) it read as a
## small door floating in an oversized hole. Re-exported via the same Meshy
## "Resize" step the wall used (Height forced to 4.0m, Origin: Bottom), so
## it now fills the gap floor-to-ceiling with no visible empty space above
## it, same fix for the same reason as the wall.
const DOOR_MODEL_PATH := "I:/Campaign-OS-3D/Downloaded Static Models/Environment/Doors/Meshy_AI_Meshy_AI_Ancient_wood_rm_0920173018_texture.glb"

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

## See WALL_MODEL_PATH's own doc comment. _wall_model_template is never itself
## added to the board -- only `.duplicate()`s of it are, one per wall segment --
## so it's kept in memory, not the scene tree, once loaded. _wall_model_size is
## its real measured (Width, Height, Depth) AABB, from _measure_scene_size().
var _wall_model_template: Node3D
var _wall_model_size := Vector3.ZERO
var _has_real_wall_model := false

## Same role as the three _wall_model_* vars above, for DOOR_MODEL_PATH.
## _door_model_lift is the amount to raise the model so its lowest point sits
## at Y=0 -- measured, not assumed, because different Meshy exports of what's
## nominally "the same asset" have turned out to use different pivots (the
## resized wall model came out bottom-pivoted, needing 0 lift; the ORIGINAL
## un-resized door model was center-pivoted, needing height/2; the RESIZED
## door model then came out bottom-pivoted again, needing 0) -- see
## _measure_scene_lift()'s own doc comment.
var _door_model_template: Node3D
var _door_model_size := Vector3.ZERO
var _door_model_lift := 0.0
var _has_real_door_model := false

# Which hand-built map scene (if any, see build()'s own doc comment) is
# currently instantiated -- tracked separately from columns/rows/cell_size so
# build()'s own no-op-if-unchanged check also catches "same size map, but the
# DM switched to a different named map that happens to share that size,"
# which columns/rows/cell_size alone can't distinguish.
var _current_map_scene_path := ""
var _map_scene_instance: Node3D

## Same "part of the no-op-if-unchanged signature" role as _current_map_scene_path
## above, for the two ROADMAP.md "Adventure map import" additions -- a DM adding a
## wall via the DM Assistant mid-session (same map, same size) needs to actually
## rebuild the generated wall meshes, which columns/rows/cell_size/map_scene_path
## alone wouldn't catch.
var _current_raster_image_path := ""
var _current_walls: Array = []
var _current_doors: Array = []

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

	# Same "degrade, don't fail" precedent every other optional/external asset in
	# this project already follows -- WALL_MODEL_PATH/DOOR_MODEL_PATH are both
	# this-machine-specific and won't exist on another clone, so _build_walls()/
	# _build_doors() fall back to their original plain-geometry (or no-op, for
	# doors) behavior whenever the corresponding _has_real_*_model is false.
	_wall_model_template = _load_external_model(WALL_MODEL_PATH)
	if _wall_model_template:
		_wall_model_size = _measure_scene_size(_wall_model_template)
		_has_real_wall_model = _wall_model_size.x > 0.01 and _wall_model_size.y > 0.01

	_door_model_template = _load_external_model(DOOR_MODEL_PATH)
	if _door_model_template:
		_door_model_size = _measure_scene_size(_door_model_template)
		_door_model_lift = _measure_scene_lift(_door_model_template)
		_has_real_door_model = _door_model_size.x > 0.01 and _door_model_size.y > 0.01

## Loads an arbitrary .glb file from anywhere on disk at RUNTIME, via
## GLTFDocument -- the exact same technique CharacterViewer.gd's own
## _load_external_glb() already established for the same reason (a file
## outside this project's own res:// tree, with no real .import generated for
## it, so ResourceLoader.load() can't be used). Shared by both the wall and
## door models above -- nothing about it is wall- or door-specific.
func _load_external_model(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		return null
	return document.generate_scene(state) as Node3D

## Instantiates `scene` briefly (unscaled) just to measure its real rendered
## (Width, Height, Depth) AABB, then removes it from the tree again -- same
## "measure the real thing after Godot has already resolved it, don't trust
## the file's claimed bounds" technique _measure_top_offset() already uses,
## generalized from "just the top Y" to the full box.
func _measure_scene_size(scene: Node3D) -> Vector3:
	add_child(scene)
	var combined := AABB()
	var first := true
	for visual in scene.find_children("*", "VisualInstance3D", true, false):
		var vi := visual as VisualInstance3D
		var aabb: AABB = vi.get_aabb()
		for i in range(8):
			var world_corner: Vector3 = vi.global_transform * aabb.get_endpoint(i)
			if first:
				combined = AABB(world_corner, Vector3.ZERO)
				first = false
			else:
				combined = combined.expand(world_corner)
	remove_child(scene)
	return combined.size

## Companion to _measure_scene_size() -- how far the model's lowest rendered
## point sits BELOW its own local origin. A true bottom-pivoted export (see
## DOOR_MODEL_PATH's own doc comment on this not being a safe assumption
## across different exports of "the same" asset) measures ~0 here, needing no
## lift to sit on the floor; a center-pivoted one measures ~height/2. Same
## "measure the real thing, don't assume the pivot" discipline as
## _measure_scene_size() itself, just for the vertical anchor instead of the
## box dimensions.
func _measure_scene_lift(scene: Node3D) -> float:
	add_child(scene)
	var lowest_y := INF
	for visual in scene.find_children("*", "VisualInstance3D", true, false):
		var vi := visual as VisualInstance3D
		var aabb: AABB = vi.get_aabb()
		for i in range(8):
			var world_corner: Vector3 = vi.global_transform * aabb.get_endpoint(i)
			lowest_y = min(lowest_y, world_corner.y)
	remove_child(scene)
	return -lowest_y if is_finite(lowest_y) else 0.0

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
##
## `raster_image_path` (ROADMAP.md's "Adventure map import" entry) -- a real image
## file already resolved by the caller (see MapImagePath.gd), used INSTEAD of the
## procedural floor when there's no hand-built map_scene_path; a hand-built scene
## always wins if both happen to be present, same "the hand-authored version is the
## intentionally better one" precedent already implicit in map_scene_path's own
## priority over the plain procedural floor. `walls` (encounter.js's own
## {x1,y1,x2,y2} segments) generates real 3D wall geometry -- but ONLY alongside a
## raster or procedural floor, never a hand-built scene, which already carries its
## own hand-placed wall geometry; doubling it here would just draw ugly overlapping
## boxes on top of it. `doors` is NOT an encounter.js/engine concept at all --
## purely decorative (see _build_doors()), a {x1,y1,x2,y2} pair marking a specific
## wall gap to visually fill with a door model, sourced from a map's own extra
## `doors` field (added by import-redbrand-hideout.js, ignored harmlessly by both
## the 2D app and the server's own line-of-sight math, which only ever reads `walls`).
func build(new_columns: int, new_rows: int, new_feet_per_square: float = 5.0, map_scene_path: String = "", raster_image_path: String = "", walls: Array = [], doors: Array = []) -> void:
	var new_cell_size := new_feet_per_square * METERS_PER_FOOT
	if new_columns == columns and new_rows == rows and is_equal_approx(new_cell_size, cell_size) \
			and map_scene_path == _current_map_scene_path and raster_image_path == _current_raster_image_path \
			and walls == _current_walls and doors == _current_doors and get_child_count() > 0:
		return
	columns = new_columns
	rows = new_rows
	feet_per_square = new_feet_per_square
	cell_size = new_cell_size
	_current_map_scene_path = map_scene_path
	_current_raster_image_path = raster_image_path
	_current_walls = walls
	_current_doors = doors

	# free(), not queue_free() -- queue_free() only SCHEDULES removal for the next
	# idle frame, so an old child is still technically present in get_children()
	# at the exact moment a SECOND build() call runs before that frame ever
	# happens (confirmed directly: this bit a test that called build() several
	# times in a row with no frame in between, undercounting how many old
	# children had really been replaced). Nothing outside this function holds a
	# reference to these children past this point, and get_children() below is
	# already a snapshot array, not a live view, so freeing immediately while
	# iterating it is safe.
	for child in get_children():
		remove_child(child)
		child.free()
	_map_scene_instance = null
	# _floor_body is also one of these children (see _build_floor_collision() below),
	# so the loop above just freed it too -- leaving this reference un-nulled means
	# _build_floor_collision()'s own `if _floor_body:` check later in this same
	# build() call sees a stale, already-freed Object instead of null, erroring on
	# every second-and-later build() call (any map switch or wall edit).
	_floor_body = null

	if map_scene_path != "" and ResourceLoader.exists(map_scene_path):
		var map_scene := load(map_scene_path) as PackedScene
		_map_scene_instance = map_scene.instantiate() as Node3D
		add_child(_map_scene_instance)
	elif raster_image_path != "" and FileAccess.file_exists(raster_image_path):
		_build_raster_floor(raster_image_path)
		_build_walls(walls)
		_build_doors(doors)
	elif _floor_scene:
		_build_real_floor_tiles()
		_build_walls(walls)
		_build_doors(doors)
	else:
		_build_fallback_checkerboard()
		_build_walls(walls)
		_build_doors(doors)

	_build_grid_lines()
	_build_floor_collision()

## Renders a single large textured floor plane from an external image file loaded at
## RUNTIME from an absolute OS path -- Image.load() + ImageTexture, the same "load
## real content from outside this project's own res:// tree" idea
## CharacterViewer.gd's GLTFDocument use already established for external .glb
## files, simpler here since a plain raster image needs no scene-graph parsing.
func _build_raster_floor(image_path: String) -> void:
	var image := Image.new()
	var error := image.load(image_path)
	if error != OK:
		# A corrupt/unreadable file shouldn't blank the whole board -- same
		# "degrade, don't fail" precedent every other missing-asset path here
		# already follows (Token.gd's fallback capsule, this class's own
		# checkerboard fallback just below).
		_build_fallback_checkerboard()
		return

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(columns * cell_size, rows * cell_size)
	mesh_instance.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	# Unshaded -- a real scanned/photographed map already has its own baked
	# lighting; letting this project's own DirectionalLight3D (angled for
	# miniatures, not a flat floor) also light it would just darken/tint it
	# unpredictably by view angle, the same reasoning the grid-line overlay
	# material below already uses unshaded for a flat, angle-independent look.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material
	# PlaneMesh lies flat on XZ already (faces +Y) -- centered at board_center()
	# exactly spans the board's own [0, columns*cell_size] x [0, rows*cell_size]
	# extent, the same coordinate space cell_to_world()/world_to_cell() use, no
	# extra offset math needed.
	mesh_instance.position = board_center()
	add_child(mesh_instance)

## Generates a StaticBody3D per {x1,y1,x2,y2} wall segment (encounter.js's own
## addWall() shape) -- vertex-space coordinates where a vertex sits at an
## INTEGER cell-unit coordinate (world = vertex * cell_size, no extra 0.5 offset the
## way a cell CENTER needs; see AoeTemplate.gd's own class doc comment for the same
## convention already proven there). Generated fresh from the exact data the server
## already uses for real line-of-sight, so this can never disagree with what
## hasLineOfSight() itself sees, unlike a hand-authored map scene's own separately
## modeled walls (which a DM editing walls via the DM Assistant wouldn't update).
## Uses Node3D's own look_at() to orient each wall, not hand-derived trig/
## rotation -- see Token.gd's _face_direction() for why this project specifically
## avoids reasoning out a rotation sign by hand.
##
## When a real wall model is available (_has_real_wall_model, see WALL_MODEL_PATH),
## each segment gets a duplicate of it instead of a plain box. The model's own
## local X is its "along the wall" axis as authored (confirmed by measuring it,
## not assumed), but this project's own wall convention runs length along local Z
## (matching look_at()'s -Z-forward and the fallback BoxMesh below) -- so a
## wrapper child with a fixed 90-degree Y rotation swaps which axis is which,
## and the model itself is scaled in ITS OWN pre-rotation local space, only
## along X (the length axis). Height and thickness are left at their real
## authored proportions (scale 1.0) rather than also being stretched to fit --
## the model was specifically resized at the source (see WALL_MODEL_PATH) so its
## height would already be correct, precisely to avoid that distortion.
func _build_walls(walls: Array) -> void:
	var wall_height := WALL_HEIGHT_FEET * METERS_PER_FOOT
	var fallback_material := StandardMaterial3D.new()
	fallback_material.albedo_color = Color(0.42, 0.4, 0.38) # only used without a real wall model

	for wall in walls:
		var p1 := Vector3(float(wall.get("x1", 0)) * cell_size, 0.0, float(wall.get("y1", 0)) * cell_size)
		var p2 := Vector3(float(wall.get("x2", 0)) * cell_size, 0.0, float(wall.get("y2", 0)) * cell_size)
		var length := p1.distance_to(p2)
		if length < 0.001:
			continue
		var midpoint := (p1 + p2) / 2.0

		var body := StaticBody3D.new()
		# The real wall model is bottom-pivoted (Meshy "Origin: Bottom" export),
		# so the body sits directly at floor level and the model grows upward
		# from there; the fallback BoxMesh is center-pivoted, so IT needs the
		# classic half-height lift instead.
		body.position = midpoint if _has_real_wall_model else midpoint + Vector3(0, wall_height / 2.0, 0)
		add_child(body) # look_at() needs this node genuinely in the tree first, so its own global_transform resolves correctly against a real (already-_ready()'d) parent chain
		body.look_at(Vector3(p2.x, body.position.y, p2.z), Vector3.UP) # local -Z now points from this wall's own midpoint toward p2

		var collision_thickness := WALL_THICKNESS
		if _has_real_wall_model:
			collision_thickness = _wall_model_size.z
			var wrapper := Node3D.new()
			wrapper.rotation_degrees.y = 90
			body.add_child(wrapper)
			var instance: Node3D = _wall_model_template.duplicate()
			wrapper.add_child(instance)
			instance.scale = Vector3(length / _wall_model_size.x, 1.0, 1.0)
		else:
			var mesh_instance := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(WALL_THICKNESS, wall_height, length) # length on local Z, matching look_at()'s own -Z-forward convention
			mesh_instance.mesh = box
			mesh_instance.material_override = fallback_material
			body.add_child(mesh_instance)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(collision_thickness, wall_height, length)
		collision.position = Vector3(0, wall_height / 2.0, 0) if _has_real_wall_model else Vector3.ZERO
		collision.shape = shape
		body.add_child(collision)

## Places a real door model (see DOOR_MODEL_PATH) at each {x1,y1,x2,y2} entry in
## `doors` -- unlike _build_walls(), this is a no-op with no fallback box when
## _has_real_door_model is false: a door is purely decorative (not an
## encounter.js/line-of-sight concept at all -- see build()'s own doc comment
## on the `doors` parameter), so skipping it on a machine without the asset
## just means one less prop, not a missing wall. Deliberately NOT stretched to
## fill its gap's exact width the way a wall is stretched to its segment's
## exact length -- the door model's own real width already reads as a
## believable door within a typically 2m-wide gap, and non-uniformly
## stretching a single recognizable object (not a repeating stone/brick
## texture) would look far more obviously wrong than mild wall-length
## stretching does. No collision shape either -- movement/line-of-sight are
## both purely server-side (hasLineOfSight is plain segment math against
## `walls`; `doors` never reaches the server at all), so there's nothing here
## for Godot physics to enforce.
func _build_doors(doors: Array) -> void:
	if not _has_real_door_model:
		return

	for door in doors:
		var p1 := Vector3(float(door.get("x1", 0)) * cell_size, 0.0, float(door.get("y1", 0)) * cell_size)
		var p2 := Vector3(float(door.get("x2", 0)) * cell_size, 0.0, float(door.get("y2", 0)) * cell_size)
		if p1.distance_to(p2) < 0.001:
			continue
		var midpoint := (p1 + p2) / 2.0

		# Same positioner -> wrapper -> instance structure _build_walls() uses,
		# and for the same reason: the outer node gets look_at()'d toward p2
		# (orienting its own local -Z along the gap), then the wrapper's fixed
		# 90-degree Y rotation swaps the door model's own local X ("across the
		# doorway," as measured -- same convention the wall model uses) onto
		# that -Z-facing axis. _door_model_lift (measured, not assumed -- see
		# its own doc comment) raises the model so its real lowest point sits
		# on the floor, whatever pivot this particular export happens to use.
		var positioner := Node3D.new()
		positioner.position = midpoint + Vector3(0, _door_model_lift, 0)
		add_child(positioner) # look_at() needs this node genuinely in the tree first, same reason _build_walls()'s body is added before being oriented
		positioner.look_at(Vector3(p2.x, positioner.position.y, p2.z), Vector3.UP)

		var wrapper := Node3D.new()
		wrapper.rotation_degrees.y = 90
		positioner.add_child(wrapper)
		var instance: Node3D = _door_model_template.duplicate()
		wrapper.add_child(instance)

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
