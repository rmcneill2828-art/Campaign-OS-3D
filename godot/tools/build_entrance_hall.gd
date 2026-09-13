extends SceneTree
## One-off scene-generation tool (not shipped) -- same "hand-authored via a
## script instead of the editor's mouse-and-gizmo workflow" pattern
## build_prototype_chamber.gd already established, this time composing
## Higgsfield "3D Jutsu" pieces (vertex-color-fixed .tscn versions, see
## fix_higgsfield_vertex_colors.gd) into a real entrance -> corridor -> room
## dungeon, matching Higgsfield's own confirmed 4m module size exactly onto
## 2x2 blocks of this project's own 2m grid cells (5 ft/square).
##
## Every position below is derived from real measurements
## (measure_higgsfield_dungeon.gd's own printed output), not guessed:
## dun_corridor_straight/dun_arch_doorway are self-contained 4x4x2.54m
## tunnel-segment modules (already walled on their own, no separate wall
## pieces needed); dun_room_floor is a bare 4x4m floor tile meant to be
## paired with separately-placed dun_room_wall (4m-wide, ~3m-tall slabs,
## long axis along local X by default) and dun_wall_corner pieces to close
## an open room. Layout (module units, 1 module = 2x2 grid cells = 4x4m):
##   module row 1 (cells y1-2): entrance (arch doorway)
##   module row 2 (cells y3-4): corridor (straight)
##   module rows 3-4 (cells y5-8), cols 1-2 (cells x1-4): the room
## Room's south wall has a doorway in the column aligned with the corridor
## (module col 1) and a solid wall in the other (module col 2) -- the only
## opening into the room is the one the corridor actually connects to.

const CELL_SIZE := 2.0 # 5 ft/square * GridManager's own METERS_PER_FOOT (0.4)
const COLUMNS := 4
const ROWS := 8

const ASSETS := "res://assets/Environment/higgsfield-test/"
const ARCH_DOORWAY := ASSETS + "dun_arch_doorway_fixed.tscn"
const CORRIDOR_STRAIGHT := ASSETS + "dun_corridor_straight_fixed.tscn"
const ROOM_FLOOR := ASSETS + "dun_room_floor_fixed.tscn"
const ROOM_WALL := ASSETS + "dun_room_wall_fixed.tscn"
const WALL_DOORWAY := ASSETS + "dun_wall_doorway_fixed.tscn"
const WALL_CORNER := ASSETS + "dun_wall_corner_fixed.tscn"
const WALL_TORCH := ASSETS + "dun_wall_torch_fixed.tscn"
const TREASURE_CHEST := ASSETS + "dun_treasure_chest_fixed.tscn"

# Real, Godot-resolved "how far below its own origin does this piece's lowest
# point sit" (measure_higgsfield_dungeon.gd's own printed lowest.y) -- only
# the small standalone props needed an explicit lift; the modular
# entrance/corridor/room-floor/wall/corner pieces all already sit flush
# (or with a deliberate few-cm embed matching how modular kits usually avoid
# a visible gap between a wall's base and the floor -- left alone, not
# "fixed," since that's the kit's own intended overlap, not a bug).
const PROP_GROUND_OFFSET := {
	WALL_TORCH: -0.06,
	TREASURE_CHEST: -0.030412,
}

var _root: Node3D

func _init() -> void:
	_root = Node3D.new()
	_root.name = "EntranceHall"

	_place_entrance_and_corridor()
	_place_room_floor()
	_place_room_walls()
	_place_props()

	_set_owners_recursive(_root, _root)
	var packed := PackedScene.new()
	var pack_result := packed.pack(_root)
	if pack_result != OK:
		push_error("pack() failed: %d" % pack_result)
		quit(1)
		return

	var maps_dir := DirAccess.open("res://scenes")
	if maps_dir and not maps_dir.dir_exists("maps"):
		maps_dir.make_dir("maps")

	var save_path := "res://scenes/maps/entrance_hall.tscn"
	var save_result := ResourceSaver.save(packed, save_path)
	if save_result != OK:
		push_error("ResourceSaver.save() failed: %d" % save_result)
		quit(1)
		return

	print("Saved %s (%d children)" % [save_path, _root.get_child_count()])
	quit()

func _set_owners_recursive(node: Node, root_owner: Node) -> void:
	for child in node.get_children():
		child.owner = root_owner
		_set_owners_recursive(child, root_owner)

## Module-center world position for module column/row M/R (1-indexed, each
## module = 2x2 grid cells). Matches GridManager.gd's own
## cell_to_world()'s (x-0.5)*cell_size convention exactly -- a module
## spanning cells [2M-1, 2M] centers at world (2M-1)*CELL_SIZE.
func _module_center(module_col: int, module_row: int) -> Vector2:
	return Vector2((2 * module_col - 1) * CELL_SIZE, (2 * module_row - 1) * CELL_SIZE)

func _place(path: String, world_x: float, world_z: float, rotation_deg: float = 0.0) -> void:
	var scene := load(path) as PackedScene
	var node := scene.instantiate() as Node3D
	var ground_offset: float = PROP_GROUND_OFFSET.get(path, 0.0)
	node.position = Vector3(world_x, -ground_offset, world_z)
	node.rotation_degrees.y = rotation_deg
	_root.add_child(node)

func _place_entrance_and_corridor() -> void:
	var entrance := _module_center(1, 1)
	_place(ARCH_DOORWAY, entrance.x, entrance.y)
	var corridor := _module_center(1, 2)
	_place(CORRIDOR_STRAIGHT, corridor.x, corridor.y)

func _place_room_floor() -> void:
	for module_row in [3, 4]:
		for module_col in [1, 2]:
			var center := _module_center(module_col, module_row)
			_place(ROOM_FLOOR, center.x, center.y)

## Wall placement uses world-space boundary lines directly (not
## _module_center, which is for FLOOR-tile centers) -- a wall sits exactly
## ON the line between the room and whatever's outside it, matching how
## build_prototype_chamber.gd's own perimeter ring sat on cell boundaries
## rather than cell centers.
func _place_room_walls() -> void:
	# South wall (z=8 boundary, facing the corridor) -- module col 1 (x
	# center 2.0, aligned with the corridor above) gets the doorway; col 2
	# (x center 6.0) stays solid. This is the room's ONLY opening.
	_place(WALL_DOORWAY, 2.0, 8.0)
	_place(ROOM_WALL, 6.0, 8.0)

	# North wall (z=16, the room's far/back boundary) -- fully solid.
	_place(ROOM_WALL, 2.0, 16.0)
	_place(ROOM_WALL, 6.0, 16.0)

	# West wall (x=0) and east wall (x=8) -- rotated 90 degrees so the
	# piece's long (4m) axis runs along Z instead of its default X.
	for z_center in [10.0, 14.0]:
		_place(ROOM_WALL, 0.0, z_center, 90.0)
		_place(ROOM_WALL, 8.0, z_center, 90.0)

	# Corners -- systematically rotated 0/90/180/270 around the room rather
	# than left all-identical, the most defensible guess without being able
	# to see which way this piece is actually authored to face; flagged in
	# ROADMAP.md for a live look rather than assumed correct.
	_place(WALL_CORNER, 0.0, 8.0, 0.0)
	_place(WALL_CORNER, 8.0, 8.0, 90.0)
	_place(WALL_CORNER, 8.0, 16.0, 180.0)
	_place(WALL_CORNER, 0.0, 16.0, 270.0)

func _place_props() -> void:
	# Two torches against the room's side walls for atmosphere, one
	# treasure chest tucked near the back wall as a reward -- placement
	# is a reasonable guess (exact mounting rotation for the torches
	# especially), flagged for a live look same as the corners above.
	_place(WALL_TORCH, 0.5, 10.0, 90.0)
	_place(WALL_TORCH, 7.5, 14.0, -90.0)
	_place(TREASURE_CHEST, 6.0, 15.0)
