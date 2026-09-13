extends Node
## Throwaway functional check -- run as an actual scene (not a bare
## --script SceneTree, whose _init() fires before children ever get a real
## _ready() pass) so Token.gd's @onready vars are genuinely populated before
## apply_data() runs, the same way Main.gd would drive it for a real
## server-spawned "Skeleton 1" token.

func _ready() -> void:
	await get_tree().process_frame

	var grid := GridManager.new()
	add_child(grid)
	grid.build(12, 8, 5.0)

	var token_scene := load("res://scenes/Token.tscn") as PackedScene
	var token := token_scene.instantiate() as Token
	add_child(token)
	await get_tree().process_frame

	token.apply_data({
		"id": "skeleton-test-1", "name": "Skeleton 1", "type": "monster",
		"x": 5, "y": 5, "hp": 13, "maxHp": 13
	}, grid)

	print("RESULT token_type=%s model_children=%d" % [token.token_type, token.get_node("Body/ModelRoot").get_child_count()])
	print("RESULT death_key=%s hit_keys=%s" % [token._death_animation_key, token._hit_animation_keys])
	get_tree().quit()
