extends Node
func _ready() -> void:
	await get_tree().process_frame
	var grid := GridManager.new()
	add_child(grid)
	grid.build(12, 8, 5.0)
	var token_scene := load("res://scenes/Token.tscn") as PackedScene
	var token := token_scene.instantiate() as Token
	add_child(token)
	await get_tree().process_frame
	token.apply_data({"id": "orc-test-1", "name": "Orc 1", "type": "monster", "x": 5, "y": 5, "hp": 15, "maxHp": 15}, grid)
	print("RESULT token_type=%s model_children=%d death_key=%s hit_keys=%s walk_key=%s dying_key=%s" % [
		token.token_type, token.get_node("Body/ModelRoot").get_child_count(),
		token._death_animation_key, token._hit_animation_keys, token._walk_animation_key, token._dying_animation_key
	])
	get_tree().quit()
