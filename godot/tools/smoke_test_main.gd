extends SceneTree
## Throwaway sanity check -- instantiates Main.tscn headlessly to catch a
## GDScript parse/runtime error in Main.gd/GridManager.gd before ever opening
## the real editor (no live engine-server needed; the HTTPRequest calls will
## just fail to connect, which is fine -- this only checks that the scene
## loads and _ready() runs without error).
##
## Fixed 2026-09-19: quit() used to run synchronously at the end of _init(),
## before the tree had processed even a single iteration -- and @onready
## assignments/_ready() itself only actually run during that first
## iteration, not synchronously inside add_child(). Confirmed directly:
## probing a known @onready-adjacent value (Main.gd's own
## _template_shape_option, built by _ready()'s _build_template_controls()
## call) came back null right after add_child(), but populated by the first
## _process() tick. This test was therefore only ever catching a scene-file/
## parse error, never a genuine _ready()-time runtime error, despite this
## file's own doc comment above already claiming otherwise -- found while
## adding the AoE Template tool (ROADMAP.md's "Seven requested features"
## 2026-09-19 entry, item 7) needed a real way to verify its own
## _ready()-time setup actually ran. Deferring quit() to the first
## _process() tick gives the tree one real iteration to run _ready() on
## every node added during _init() before this test ends.

func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	var instance := scene.instantiate()
	get_root().add_child(instance)

func _process(_delta: float) -> bool:
	print("Main.tscn instantiated OK")
	quit()
	return true
