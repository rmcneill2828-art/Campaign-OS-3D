extends SceneTree
## One-off scene-generation tool (not shipped/run as part of the game) --
## places real Kenney dungeon-kit pieces into a fixed 12x8 room shell
## (matching engine-server's seeded "Prototype Chamber" map: 12 columns x 8
## rows at the default 5 ft/square) and saves the result as a real Godot
## scene file, res://scenes/maps/prototype_chamber.tscn.
##
## This still counts as a HAND-AUTHORED map in the sense the Phase 3+
## planning pass meant it (a human decided exactly where every wall/door/prop
## goes -- floor/wall/column/prop placement below, cell by cell, not a
## generic "wall ring around whatever columns/rows a map happens to have"
## algorithm) -- the difference is this one-off generation script is the
## "paintbrush" instead of dragging pieces by hand in the Godot editor GUI
## (not available to drive interactively in this session), but the output is
## a normal, fixed scene file checked into the repo exactly like a
## hand-placed one would be. GridManager.gd never generates a room's SHAPE
## itself, at any point, past or future -- it only ever instantiates whatever
## finished scene a given map name points to (see MAP_SCENES in Main.gd).
## Every placement below uses each piece's real Godot-resolved AABB (see
## tools/measure_pieces.gd's output), not assumed/guessed dimensions --
## same discipline this project's GridManager/Token scripts already use at
## runtime, just applied once here to build the file instead of every frame.
##
## Run via (from the godot/ directory):
##   <path-to-Godot>.exe --headless --path . --script res://tools/build_prototype_chamber.gd
## Then delete/ignore -- this script is throwaway tooling for one planning
## pass, not part of the running game.

const CELL_SIZE := 2.0 # 5 ft/square * GridManager's own METERS_PER_FOOT (0.4) -- this
# scene is a fixed physical room built for that one specific map scale, not
# dynamically resizable at runtime the way the procedural floor was.
const COLUMNS := 12
const ROWS := 8
const DOOR_COLUMN := 7 # south wall gap, roughly centered along the 12-wide room

const DUNGEON_KIT := "res://assets/Environment/dungeon-kit/Models/GLB format/"
const FLOOR := DUNGEON_KIT + "floor.glb"
const FLOOR_DETAIL := DUNGEON_KIT + "floor-detail.glb"
const WALL := DUNGEON_KIT + "wall.glb"
const WALL_OPENING := DUNGEON_KIT + "wall-opening.glb"
const COLUMN := DUNGEON_KIT + "column.glb"
const CHEST := DUNGEON_KIT + "chest.glb"
const BARREL := DUNGEON_KIT + "barrel.glb"

# Real, Godot-resolved "how far below its own origin does this piece's lowest
# point sit" (see tools/measure_pieces.gd's printed origin-to-lowest.y) --
# only chest.glb measured non-zero here (-0.05); floor/wall/column/barrel all
# confirmed origin-at-base already, same convention Token.gd's models and
# GridManager's floor tiles already rely on.
const PROP_GROUND_OFFSET := {
	CHEST: -0.05,
}

var _root: Node3D

func _init() -> void:
	_root = Node3D.new()
	_root.name = "PrototypeChamber"

	_place_floor()
	_place_walls()
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

	var save_path := "res://scenes/maps/prototype_chamber.tscn"
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

## Same (x-0.5)*cell_size / (y-0.5)*cell_size cell-center convention as
## GridManager.gd's own cell_to_world() -- deliberately duplicated rather than
## imported (this tool runs standalone, outside the normal scene tree
## GridManager lives in) but must stay numerically identical, since this
## room's geometry only lines up with the server's real grid cells if it does.
func _place(path: String, gx: int, gy: int) -> void:
	var scene := load(path) as PackedScene
	var node := scene.instantiate() as Node3D
	node.scale = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	var ground_offset: float = PROP_GROUND_OFFSET.get(path, 0.0)
	node.position = Vector3(
		(gx - 0.5) * CELL_SIZE,
		-ground_offset * CELL_SIZE,
		(gy - 0.5) * CELL_SIZE
	)
	_root.add_child(node)

func _place_floor() -> void:
	# Same deterministic (not random -- see GridManager.gd's own comment on
	# why) floor/floor-detail mix GridManager's procedural builder already
	# uses, so a hand-built room and a procedural one read consistently.
	for gx in range(1, COLUMNS + 1):
		for gy in range(1, ROWS + 1):
			var use_detail := (gx * 7 + gy * 3) % 11 == 0
			_place(FLOOR_DETAIL if use_detail else FLOOR, gx, gy)

func _place_walls() -> void:
	# The perimeter ring sits one cell OUTSIDE the playable columns x rows
	# area (grid index 0, or columns+1/rows+1) so it never occupies a cell a
	# token could actually be standing on -- cell_to_world's own formula
	# already extends consistently to those out-of-range indices, no separate
	# math needed for the ring vs. the floor above.
	for gx in range(0, COLUMNS + 2):
		for gy in [0, ROWS + 1]:
			if _is_corner(gx, gy):
				continue
			var is_door: bool = (gx == DOOR_COLUMN and gy == ROWS + 1)
			_place(WALL_OPENING if is_door else WALL, gx, gy)
	for gy in range(1, ROWS + 1):
		_place(WALL, 0, gy)
		_place(WALL, COLUMNS + 1, gy)

	# Corners get a column instead of a wall block -- a cleaner joint where
	# two straight walls would otherwise meet at a right angle, and visually
	# distinct enough to read as "this is a corner" rather than just another
	# wall segment.
	_place(COLUMN, 0, 0)
	_place(COLUMN, COLUMNS + 1, 0)
	_place(COLUMN, 0, ROWS + 1)
	_place(COLUMN, COLUMNS + 1, ROWS + 1)

func _is_corner(gx: int, gy: int) -> bool:
	return (gx == 0 or gx == COLUMNS + 1) and (gy == 0 or gy == ROWS + 1)

## A few props in the inner corners only -- deliberately not the room's
## center, which is exactly where tokens most need clear floor to actually
## move/fight across on a battle map.
func _place_props() -> void:
	_place(CHEST, 2, 2)
	_place(BARREL, COLUMNS - 1, 2)
	_place(BARREL, 2, ROWS - 1)
	_place(CHEST, COLUMNS - 1, ROWS - 1)
