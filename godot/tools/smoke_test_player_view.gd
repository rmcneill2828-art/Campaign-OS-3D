extends SceneTree
## Throwaway sanity check -- instantiates PlayerView.tscn headlessly to catch
## a GDScript parse/runtime error before ever opening the real editor. No
## live engine-server needed (HTTPRequest just fails to connect, which is
## fine and expected here).

func _init() -> void:
	var scene := load("res://scenes/PlayerView.tscn") as PackedScene
	var instance := scene.instantiate()
	get_root().add_child(instance)
	print("PlayerView.tscn instantiated OK")
	quit()
