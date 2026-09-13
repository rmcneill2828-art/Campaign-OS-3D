extends SceneTree
## One-off fix tool (not shipped) -- Higgsfield's "3D Jutsu" GLB exports carry
## real, meaningful per-vertex color data (confirmed directly: 349 distinct
## wood-brown tones on the treasure chest alone, not flat white) but Godot's
## glTF importer leaves `vertex_color_use_as_albedo` false on the resulting
## StandardMaterial3D, so that color data is silently ignored at render time
## -- every piece comes in looking flat white/grey regardless of its real
## intended color. Confirmed by direct inspection (a script dumping the
## mesh's own ARRAY_COLOR data), not assumed from the flat-white look alone.
##
## Fixes this ONCE per piece by assigning each MeshInstance3D a fresh
## `material_override` (never mutating the imported mesh resource's own
## shared material -- same "don't mutate a shared resource" discipline this
## project already established for the HP bar) with the same properties
## Godot's importer already picked (metallic/roughness) plus
## `vertex_color_use_as_albedo = true`, then re-saves the whole instanced
## scene as a new GLB via the same `PackedScene.pack()` + `ResourceSaver.save()`
## technique `build_prototype_chamber.gd` already uses.

## Destinations are `.tscn`, not `.glb` -- `ResourceSaver.save()` only writes
## Godot-native formats (this project's own `build_prototype_chamber.gd`
## already established this exact pattern); writing an actual `.glb` back out
## needs the separate `GLTFDocument` export API instead, more machinery than
## this fix needs. A `.tscn` referencing the original glTF's meshes plus this
## corrected material is exactly as loadable from `Token.gd`/`GridManager.gd`
## as a plain `.glb` would be -- nothing downstream cares which.
const FIXES := {
	"res://assets/Environment/higgsfield-test/dun_wall_torch.glb": "res://assets/Environment/higgsfield-test/dun_wall_torch_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_treasure_chest.glb": "res://assets/Environment/higgsfield-test/dun_treasure_chest_fixed.tscn",
	"res://assets/Environment/higgsfield-test/dun_corridor_straight.glb": "res://assets/Environment/higgsfield-test/dun_corridor_straight_fixed.tscn",
}

func _init() -> void:
	for source_path in FIXES:
		var dest_path: String = FIXES[source_path]
		if not ResourceLoader.exists(source_path):
			print("MISSING: %s" % source_path)
			continue

		var scene := load(source_path) as PackedScene
		var instance := scene.instantiate() as Node3D

		var fixed_count := 0
		for visual in instance.find_children("*", "VisualInstance3D", true, false):
			if not (visual is MeshInstance3D):
				continue
			var mi := visual as MeshInstance3D
			for surf in range(mi.mesh.get_surface_count() if mi.mesh else 0):
				var original := mi.get_active_material(surf)
				var fixed_material := StandardMaterial3D.new()
				if original is BaseMaterial3D:
					var bm := original as BaseMaterial3D
					fixed_material.metallic = bm.metallic
					fixed_material.roughness = bm.roughness
					fixed_material.albedo_color = bm.albedo_color
				fixed_material.vertex_color_use_as_albedo = true
				mi.set_surface_override_material(surf, fixed_material)
				fixed_count += 1

		_set_owners_recursive(instance, instance)

		var packed := PackedScene.new()
		var pack_result := packed.pack(instance)
		if pack_result != OK:
			push_error("pack() failed for %s: %d" % [source_path, pack_result])
			continue
		var save_result := ResourceSaver.save(packed, dest_path)
		if save_result != OK:
			push_error("save() failed for %s: %d" % [dest_path, save_result])
			continue
		print("Fixed %d material(s) -- saved %s" % [fixed_count, dest_path])

	quit()

func _set_owners_recursive(node: Node, root_owner: Node) -> void:
	for child in node.get_children():
		child.owner = root_owner
		_set_owners_recursive(child, root_owner)
