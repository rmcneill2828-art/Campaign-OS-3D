extends SceneTree
## One-off measurement tool (not part of the running game) -- instantiates each
## Kenney dungeon-kit piece being considered for Phase 4's hand-built map and
## prints its real, Godot-resolved AABB (size + how far its origin sits from
## the lowest point of its own geometry on each axis), the same "measure the
## real thing at runtime, don't trust the file's claimed bounds" discipline
## GridManager.gd's _measure_top_offset() and Token.gd's _ground_model()
## already established this project needed. Run via:
##   godot --headless --path godot --script res://tools/measure_pieces.gd
## then delete/ignore -- this is throwaway tooling for one planning pass, not
## shipped project logic.

const PIECES := [
	"res://assets/Environment/dungeon-kit/Models/GLB format/wall.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/wall-half.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/wall-narrow.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/wall-opening.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/gate.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/column.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/stairs.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/chest.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/barrel.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/banner.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/table.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/wood-support.glb",
	"res://assets/Environment/dungeon-kit/Models/GLB format/floor.glb",
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
		var found_any := false
		for visual in instance.find_children("*", "VisualInstance3D", true, false):
			var mesh_instance := visual as VisualInstance3D
			var aabb: AABB = mesh_instance.get_aabb()
			for i in range(8):
				var corner: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(i)
				lowest = lowest.min(corner)
				highest = highest.max(corner)
				found_any = true

		if found_any:
			var size := highest - lowest
			print("%s -- size(x,y,z)=(%.4f, %.4f, %.4f) origin-to-lowest=(%.4f, %.4f, %.4f) origin-to-highest=(%.4f, %.4f, %.4f)" % [
				path.get_file(), size.x, size.y, size.z,
				lowest.x, lowest.y, lowest.z,
				highest.x, highest.y, highest.z
			])
		else:
			print("%s -- no VisualInstance3D found" % path)

		root.remove_child(instance)
		instance.queue_free()

	quit()
