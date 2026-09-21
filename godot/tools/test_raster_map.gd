extends SceneTree
## Functional check for the "Adventure map import" v1 slice (ROADMAP.md, 2026-09-19):
## MapImagePath's slug/resolve logic, and GridManager's new raster-floor + generated-
## wall-mesh rendering. Uses a real image already committed to this repo (Kenney's
## Sample.png) copied to a throwaway map-name slug under a TEMP maps directory --
## not the real engine-server/state/maps/ folder, so this test never touches (or
## depends on the contents of) whatever a real DM has actually placed there.
##
## See smoke_test_main.gd's own doc comment for why quit() is deferred to the first
## _process() tick rather than called synchronously in _init().

var _failures := 0
var _board
var _tmp_dir := ""

func _fail(message: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % message)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

func _test_slugify() -> void:
	_check(MapImagePath.slugify("Cragmaw Hideout") == "cragmaw_hideout", "slugify: spaces become underscores, lowercased")
	_check(MapImagePath.slugify("  Lost Mine of Phandelver!! ") == "lost_mine_of_phandelver", "slugify: punctuation collapses, edges trimmed")
	_check(MapImagePath.resolve("Definitely Not A Real Map Name XYZ") == "", "resolve: a map with no real image file on disk returns empty")

## Copies a real committed image (not a throwaway/generated fixture) to where
## MapImagePath's own convention expects one, under a temp directory standing in
## for engine-server/state/maps/ -- proves the actual resolve-a-real-file path end
## to end without touching the real maps folder.
func _make_test_image(slug: String) -> String:
	if _tmp_dir == "":
		_tmp_dir = "user://test_raster_map_%d" % Time.get_ticks_usec()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_tmp_dir))
	var source := ProjectSettings.globalize_path("res://assets/Environment/dungeon-kit/Sample.png")
	var dest := ProjectSettings.globalize_path(_tmp_dir).path_join("%s.png" % slug)
	DirAccess.copy_absolute(source, dest)
	return dest

func _test_raster_floor(board) -> void:
	var image_path := _make_test_image("test_raster_floor_map")
	_check(FileAccess.file_exists(image_path), "Sanity check: the copied test image actually exists")

	board.build(10, 6, 5.0, "", image_path, [])
	var floor_mesh: MeshInstance3D = null
	for child in board.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is PlaneMesh:
			floor_mesh = child
			break
	_check(floor_mesh != null, "A raster image path builds a real PlaneMesh floor")
	if floor_mesh:
		var plane: PlaneMesh = floor_mesh.mesh
		var expected_size := Vector2(10 * board.cell_size, 6 * board.cell_size)
		_check(plane.size.is_equal_approx(expected_size), "The floor plane is sized to exactly the board's own columns x rows x cell_size")
		var material: StandardMaterial3D = floor_mesh.material_override
		_check(material != null and material.albedo_texture != null, "The floor plane's material actually carries the loaded image as a texture")

	# A corrupt/nonexistent path shouldn't blank the board -- falls back to the
	# existing checkerboard, same "degrade, don't fail" precedent every other
	# missing-asset path in this project already follows.
	board.build(10, 6, 5.0, "", "", []) # empty path -- same code path build() itself already gates on FileAccess.file_exists()
	var has_any_floor := false
	for child in board.get_children():
		if child is MeshInstance3D:
			has_any_floor = true
			break
	_check(has_any_floor, "An empty/missing raster path still renders SOME floor (falls back), not a blank board")

## Distinguishes a real generated wall body from GridManager's OWN pre-existing
## `_floor_body` -- both are plain StaticBody3D nodes, but _floor_body (the
## invisible click-to-move collision plane _build_floor_collision() always adds,
## regardless of which floor path build() took) carries ONLY a CollisionShape3D
## (one child total), while a real wall body always carries a visual child too
## (two children total) -- a plain MeshInstance3D for the fallback BoxMesh, or a
## rotation wrapper around a real wall-model duplicate when one is available
## (see GridManager's own WALL_MODEL_PATH) -- so child COUNT, not the first
## child's specific type, is the reliable distinguishing feature to filter on
## across both cases.
func _is_wall_body(node: Node) -> bool:
	return node is StaticBody3D and node.get_child_count() > 1

## The visual geometry differs (plain BoxMesh vs. a real wall model, see
## GridManager's own _build_walls()), but every wall body always carries
## exactly one CollisionShape3D with a BoxShape3D -- the thing hasLineOfSight()
## consistency actually depends on -- regardless of which visual path was
## taken, so tests assert against THIS, not the visual mesh.
func _find_collision_shape(body: StaticBody3D) -> CollisionShape3D:
	for child in body.get_children():
		if child is CollisionShape3D:
			return child
	return null

func _test_walls(board) -> void:
	# A simple north wall spanning the whole width of a 12x8 board, plus a short
	# interior wall at an angle -- covers both the axis-aligned case and a case
	# where look_at()'s own orientation actually has to do real work.
	var walls := [
		{"x1": 0, "y1": 0, "x2": 12, "y2": 0},
		{"x1": 4, "y1": 2, "x2": 7, "y2": 5}
	]
	board.build(12, 8, 5.0, "", "", walls)

	var wall_bodies: Array = []
	for child in board.get_children():
		if _is_wall_body(child):
			wall_bodies.append(child)
	_check(wall_bodies.size() == 2, "One StaticBody3D per wall segment")

	var cell_size: float = board.cell_size
	var wall_height: float = GridManager.WALL_HEIGHT_FEET * GridManager.METERS_PER_FOOT
	# The wall's own endpoints sit at wall_height/2 (the whole box is vertically
	# centered there, see _build_walls()), not at y=0 -- comparing against the raw
	# input's own y=0 would fail even for a perfectly correct wall.
	var expected_p1 := Vector3(0, wall_height / 2.0, 0)
	var expected_p2 := Vector3(12 * cell_size, wall_height / 2.0, 0)
	var expected_length: float = expected_p1.distance_to(expected_p2)

	var straight_wall: StaticBody3D = wall_bodies[0]
	var collision: CollisionShape3D = _find_collision_shape(straight_wall)
	var box: BoxShape3D = collision.shape
	_check(is_equal_approx(box.size.z, expected_length), "The wall's own collision length (local Z, matching look_at()'s -Z-forward convention) matches the real distance between its two endpoints")

	# Verify the ACTUAL resulting orientation/position by transforming the collision
	# box's own local Z endpoints through its real global transform and checking they
	# land on the real input points, as a set (order-independent -- which endpoint is
	# local +Z vs -Z isn't the point; spanning the right two points in the world is).
	# Uses the collision shape's own global_transform, not the body's -- the body
	# itself sits at floor level for a real wall model (see _build_walls()'s own
	# comment on the bottom-vs-center pivot difference), with the collision child
	# carrying the wall_height/2 lift instead in that case.
	var half := box.size.z / 2.0
	var collision_transform: Transform3D = collision.global_transform
	var world_end_a: Vector3 = collision_transform * Vector3(0, 0, -half)
	var world_end_b: Vector3 = collision_transform * Vector3(0, 0, half)
	var matches_a := (world_end_a.is_equal_approx(expected_p1) and world_end_b.is_equal_approx(expected_p2))
	var matches_b := (world_end_a.is_equal_approx(expected_p2) and world_end_b.is_equal_approx(expected_p1))
	_check(matches_a or matches_b, "The wall's collision box real transformed endpoints land exactly on its two input vertex-space points, regardless of which local Z sign is which")
	_check(is_equal_approx(collision_transform.origin.y, (GridManager.WALL_HEIGHT_FEET * GridManager.METERS_PER_FOOT) / 2.0), "The wall's collision box is vertically centered at half its own height above the floor")

	# A zero-length ("degenerate") segment must not crash or produce a body with no
	# real geometry to speak of.
	board.build(12, 8, 5.0, "", "", [{"x1": 3, "y1": 3, "x2": 3, "y2": 3}])
	var degenerate_bodies := 0
	for child in board.get_children():
		if _is_wall_body(child):
			degenerate_bodies += 1
	_check(degenerate_bodies == 0, "A zero-length wall segment is skipped, not turned into a zero-size body")

## Freestanding room dressing -- see GridManager.gd's own PROP_MODEL_PATHS/
## _build_props() doc comments. Real assertions on real node positions only
## run when this machine actually has the external prop models loaded (same
## "EXPLICITLY PROVISIONAL and this-machine-specific" situation WALL_MODEL_PATH/
## DOOR_MODEL_PATH are already in -- a clone without I:\Campaign-OS-3D\... just
## won't exercise this part, same as it already doesn't for walls/doors), but
## the "unrecognized type is silently skipped" and "empty props array is a
## no-op" behaviors are asserted unconditionally either way.
func _test_props(board) -> void:
	var has_real_props: bool = board._prop_templates.has("table")

	# Baseline: same board, no props at all -- the child-count difference below
	# isolates exactly what _build_props() added, without needing to pick a real
	# prop instance back out from among the floor tiles/grid lines/etc. by
	# position (fragile: _build_real_floor_tiles() already puts a Node3D at
	# every cell, indistinguishable by class from a prop's own duplicated
	# template, so a position-based search could false-match a floor tile).
	board.build(10, 6, 5.0, "", "", [])
	var baseline: int = board.get_child_count()

	var props := [
		{"type": "table", "x": 3, "y": 2},
		{"type": "not_a_real_prop_type", "x": 5, "y": 5}
	]
	board.build(10, 6, 5.0, "", "", [], [], props)
	var with_props: int = board.get_child_count()

	if has_real_props:
		_check(with_props == baseline + 1, "Exactly one node added for the one recognized prop type -- the unrecognized type is silently skipped, not a crash or a fallback box")
	else:
		_check(with_props == baseline, "No real prop models loaded on this machine -- both entries (recognized type included) are silently skipped, same degrade-don't-fail precedent as a missing wall/door model")
		print("SKIP: no real prop models loaded on this machine -- can't assert a real prop node was actually added")

func _test_no_op_gate(board) -> void:
	var walls_a := [{"x1": 0, "y1": 0, "x2": 5, "y2": 0}]
	board.build(10, 6, 5.0, "", "", walls_a)
	var count_a: int = board.get_child_count()
	board.build(10, 6, 5.0, "", "", walls_a) # identical call -- should no-op, not rebuild
	_check(board.get_child_count() == count_a, "An unchanged build() call (same walls too) is a real no-op")

	var walls_b := [{"x1": 0, "y1": 0, "x2": 5, "y2": 0}, {"x1": 5, "y1": 0, "x2": 5, "y2": 5}]
	board.build(10, 6, 5.0, "", "", walls_b) # same size/scene, DIFFERENT walls -- must actually rebuild
	var straight_walls := 0
	for child in board.get_children():
		if _is_wall_body(child):
			straight_walls += 1

	# Same "no real prop models loaded on this machine" situation _test_props()
	# already guards -- when true, _build_props() silently skips every entry
	# (recognized type included), so removing a non-empty props array adds zero
	# visible nodes either way and the child count genuinely can't move. Without
	# this guard the assertion below is unwinnable on a machine (like CI) that
	# never had the real .glb loaded in the first place, regardless of whether
	# the no-op gate itself is working correctly.
	var has_real_props: bool = board._prop_templates.has("table")

	var props_a := [{"type": "table", "x": 1, "y": 1}]
	board.build(10, 6, 5.0, "", "", walls_b, [], props_a)
	var count_with_props: int = board.get_child_count()
	board.build(10, 6, 5.0, "", "", walls_b, [], props_a) # identical, props included -- still a no-op
	_check(board.get_child_count() == count_with_props, "An unchanged build() call (same props too) is a real no-op")

	board.build(10, 6, 5.0, "", "", walls_b, [], []) # same walls, props REMOVED -- must actually rebuild
	if has_real_props:
		_check(board.get_child_count() != count_with_props, "Changing only the props array (same walls) still triggers a real rebuild")
	else:
		print("SKIP: no real prop models loaded on this machine -- removing props has no visible node to lose, can't assert a real rebuild happened")
	_check(straight_walls == 2, "Changing only the walls array (same map size) still triggers a real rebuild")

func _init() -> void:
	_board = GridManager.new()
	get_root().add_child(_board)

var _ran := false
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_slugify()
	_test_raster_floor(_board)
	_test_walls(_board)
	_test_props(_board)
	_test_no_op_gate(_board)
	if _tmp_dir != "":
		# Best-effort cleanup of the one file this test creates -- the directory
		# itself is left behind (harmless: an ephemeral user:// path, not the real
		# project or engine-server folders, and never persists across CI runs
		# regardless).
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_dir).path_join("test_raster_floor_map.png"))
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All Adventure Map Import assertions passed")
		quit()
	return true
