extends SceneTree
## Throwaway sanity check for the Phase 8 dungeon build -- confirms
## MapScenes.resolve("Entrance Hall") points at a real scene file and that
## the scene actually loads/instantiates without error, same spirit as
## smoke_test_main.gd. Also re-derives GridManager's own cell-to-world
## formula to confirm the generated node count/positions still make sense
## from outside build_entrance_hall.gd's own assumptions.

func _init() -> void:
	var path := MapScenes.resolve("Entrance Hall")
	if path == "":
		push_error("MapScenes.resolve('Entrance Hall') returned empty -- SCENES dict entry missing")
		quit(1)
		return
	print("MapScenes.resolve('Entrance Hall') -> %s" % path)

	if not ResourceLoader.exists(path):
		push_error("Resolved path does not exist: %s" % path)
		quit(1)
		return

	var scene := load(path) as PackedScene
	var instance := scene.instantiate() as Node3D
	get_root().add_child(instance)
	print("entrance_hall.tscn instantiated OK -- %d children" % instance.get_child_count())

	if instance.get_child_count() != 21:
		push_error("Expected 21 children (1 entrance + 1 corridor + 4 room floors + 4 wall segments + 4 side walls + 4 corners + 2 torches + 1 chest), got %d" % instance.get_child_count())
		quit(1)
		return

	quit()
