extends SceneTree
## One-off measurement pass for the Higgsfield dungeon-building pieces --
## same "measure the real thing, don't guess" discipline as every other
## piece placement in this project. Reports real AABB (footprint + height,
## and how far off-center the origin sits) for each of the 8 pieces
## involved in the entrance/corridor/room build.
##
## v2 -- the original version used MeshInstance3D.global_transform, which
## turned out to be UNRELIABLE in a bare --script SceneTree: Godot doesn't
## propagate a freshly add_child()-ed node's transform down through nested
## wrapper nodes without a real process frame, which this kind of tool
## never gets. It didn't error or return identity (which would have been
## obvious) -- it silently returned a PARTIALLY-composed transform, giving
## plausible-looking but WRONG numbers for any piece with real translation
## in its own internal node hierarchy (which every one of these 8 pieces
## has, from fix_higgsfield_vertex_colors.gd's own wrapper structure).
## Found live: this measurement said dun_corridor_straight_fixed.tscn's
## floor was flush at y=0 (lowest=0, highest=2.54); the REAL geometry is
## actually CENTERED on its own origin (y=[-1.27,1.27]) -- placed at
## position.y=0 per that wrong measurement, the module's real floor ended
## up 1.27m underground, exactly matching a live report of tokens standing
## at wall-top height over a visibly deep, dark recess. Every piece here
## needed re-measuring with this fix, not just the one that was reported.
##
## Fix: never trust global_transform in a bare --script tool for anything
## with meaningful nesting -- manually compose each node's own LOCAL
## .transform up through get_parent() instead (see _real_global_transform
## below). This reads plain already-resolved Transform3D data with no
## lazy/dirty propagation involved, so it's correct with zero process
## frames. Also samples real mesh vertex data directly (every 5th vertex)
## rather than get_aabb(), matching the same discipline other diagnostics
## in this project already moved to once whole-piece AABBs stopped being
## trusted at face value.

const PIECES := [
	"res://assets/Environment/higgsfield-test/dun_room_floor_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_room_wall_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_corridor_straight_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_arch_doorway_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_wall_corner_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_wall_doorway_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_wall_torch_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_treasure_chest_fixed.tscn",
]

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	for path in PIECES:
		if not ResourceLoader.exists(path):
			print("%s -- MISSING" % path)
			continue
		var scene := load(path) as PackedScene
		var instance := scene.instantiate() as Node3D
		root.add_child(instance)

		var lowest := Vector3(INF, INF, INF)
		var highest := Vector3(-INF, -INF, -INF)
		for visual in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := visual as MeshInstance3D
			var mesh := mesh_instance.mesh
			if not mesh:
				continue
			var xform := _real_global_transform(mesh_instance, root)
			for surface_idx in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface_idx)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < verts.size():
					var world_v: Vector3 = xform * verts[i]
					lowest = lowest.min(world_v)
					highest = highest.max(world_v)
					i += 5

		var size := highest - lowest
		var center_x := (lowest.x + highest.x) / 2.0
		var center_z := (lowest.z + highest.z) / 2.0
		print("%s" % path.get_file())
		print("  size(x,y,z)=(%.3f, %.3f, %.3f)" % [size.x, size.y, size.z])
		print("  lowest=%s highest=%s" % [lowest, highest])
		print("  center_x_offset=%.3f center_z_offset=%.3f (0 means origin is centered)" % [center_x, center_z])

	quit()

## Composes local .transform values from `node` up to (but not including)
## `stop_at`, entirely bypassing Godot's own cached global_transform --
## see this file's own header comment for why that cache can't be trusted
## here.
func _real_global_transform(node: Node3D, stop_at: Node) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent and parent != stop_at:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform
