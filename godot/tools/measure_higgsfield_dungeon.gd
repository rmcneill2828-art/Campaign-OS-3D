extends SceneTree
## One-off measurement pass for the Higgsfield dungeon-building pieces --
## same "measure the real thing, don't guess" discipline as every other
## piece placement in this project. Reports real AABB (footprint + height,
## and how far off-center the origin sits, since some pieces may not be
## centered the way floor.glb/wall.glb were) for each of the 8 pieces
## involved in the entrance/corridor/room build.

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
		for visual in instance.find_children("*", "VisualInstance3D", true, false):
			var mesh_instance := visual as VisualInstance3D
			var aabb: AABB = mesh_instance.get_aabb()
			for i in range(8):
				var corner: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(i)
				lowest = lowest.min(corner)
				highest = highest.max(corner)

		var size := highest - lowest
		var center_x := (lowest.x + highest.x) / 2.0
		var center_z := (lowest.z + highest.z) / 2.0
		print("%s" % path.get_file())
		print("  size(x,y,z)=(%.3f, %.3f, %.3f)" % [size.x, size.y, size.z])
		print("  lowest=%s highest=%s" % [lowest, highest])
		print("  center_x_offset=%.3f center_z_offset=%.3f (0 means origin is centered)" % [center_x, center_z])

	quit()
