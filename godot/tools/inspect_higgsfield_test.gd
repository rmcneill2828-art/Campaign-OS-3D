extends SceneTree
## One-off inspection tool (not shipped) -- same "measure the real thing,
## don't trust the file's claimed bounds" discipline every other asset in
## this project has already used, applied to the 3 Higgsfield 3D Jutsu test
## imports. Checks real-world size (are these grid-scale, or some other
## scale entirely) and whether they carry a texture/material at all, since
## nothing about the Composio-side import process confirmed either.

const PIECES := [
	"res://assets/Environment/higgsfield-test/dun_wall_torch.glb",
	"res://assets/Environment/higgsfield-test/dun_treasure_chest.glb",
	"res://assets/Environment/higgsfield-test/dun_corridor_straight.glb",
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
		var has_texture := false
		var mesh_count := 0
		for visual in instance.find_children("*", "VisualInstance3D", true, false):
			var mesh_instance := visual as VisualInstance3D
			mesh_count += 1
			var aabb: AABB = mesh_instance.get_aabb()
			for i in range(8):
				var corner: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(i)
				lowest = lowest.min(corner)
				highest = highest.max(corner)
			if mesh_instance is MeshInstance3D:
				var mi := mesh_instance as MeshInstance3D
				for surf in range(mi.mesh.get_surface_count() if mi.mesh else 0):
					var mat := mi.get_active_material(surf)
					if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
						has_texture = true

		var size := highest - lowest
		print("%s -- size(x,y,z)=(%.3f, %.3f, %.3f) meshes=%d has_texture=%s lowest=%s highest=%s" % [
			path.get_file(), size.x, size.y, size.z, mesh_count, has_texture, lowest, highest
		])

	quit()
