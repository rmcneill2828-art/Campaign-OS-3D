extends SceneTree
## Throwaway sanity check -- instantiates Main.tscn headlessly to catch a
## GDScript parse/runtime error in Main.gd/GridManager.gd before ever opening
## the real editor (no live engine-server needed; the HTTPRequest calls will
## just fail to connect, which is fine -- this only checks that the scene
## loads and _ready() runs without error).

func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	var instance := scene.instantiate()
	get_root().add_child(instance)
	print("Main.tscn instantiated OK")
	quit()
