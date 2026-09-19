extends SceneTree
## Throwaway sanity check -- instantiates PlayerView.tscn headlessly to catch
## a GDScript parse/runtime error before ever opening the real editor. No
## live engine-server needed (HTTPRequest just fails to connect, which is
## fine and expected here).
##
## Fixed 2026-09-19: see smoke_test_main.gd's own doc comment for the full
## story -- quit() used to run before _ready() ever actually got to execute
## (that only happens on the tree's first real iteration, not synchronously
## inside add_child()), so this was never actually catching a _ready()-time
## error despite the comment above claiming it did. Deferring quit() to the
## first _process() tick fixes it the same way.

func _init() -> void:
	var scene := load("res://scenes/PlayerView.tscn") as PackedScene
	var instance := scene.instantiate()
	get_root().add_child(instance)

func _process(_delta: float) -> bool:
	print("PlayerView.tscn instantiated OK")
	quit()
	return true
