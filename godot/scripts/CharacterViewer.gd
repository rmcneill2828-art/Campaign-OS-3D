extends Node3D
class_name CharacterViewer
## Item 3 of ROADMAP.md's "Seven requested features" (2026-09-19) -- a dedicated,
## larger 3D view of a single token opened from Main.gd's "Other Actions" section:
## an orbit camera around its current model (reusing the real Token scene/model-
## resolution logic the board itself uses, via preview_external_model()/apply_data()
## on an embedded Token -- so this can't drift from what the board actually shows)
## alongside a live stat-sheet panel, plus a way to preview an arbitrary external
## .glb file before it's ever wired into Token.gd's own MODEL_CONFIG -- see
## _load_external_glb()'s own doc comment for how and why only .glb, not .fbx.
##
## Entirely code-built (no .tscn) -- same convention Main.gd's own
## _build_template_controls()/_build_character_creator_controls() already use for UI,
## extended here to the 3D scene graph itself (camera rig, lighting, model root), so
## opening this needs nothing but CharacterViewer.new(). Polls engine-server on its
## OWN timer rather than being pushed updates by Main.gd -- same "a second independent
## poller is simpler and more robust than pushing updates into a child window"
## reasoning Main.gd's own _on_open_player_window_pressed() already documents for
## PlayerView.

const TokenScene := preload("res://scenes/Token.tscn")

@export var poll_interval_seconds := 1.0

var server_base_url := ""
var token_id := ""

var _camera_rig: CameraRig
var _model_token: Token
var _dummy_grid: GridManager # never build()'d/added to the tree -- just a cell_size source for apply_data()'s own cell_to_world() math; see _apply_token() for why the result is discarded anyway
var _stats_label: RichTextLabel
var _model_path_input: LineEdit
var _load_status_label: Label
var _sync_status_label: Label
var _state_request: HTTPRequest
var _poll_timer: Timer
var _custom_model_instance: Node3D # set only once a Load Model override succeeds

## Called by Main.gd right after instantiating this (and before adding it to the
## scene tree), so _ready() below sees these already set once it actually runs.
func open(base_url: String, id: String) -> void:
	server_base_url = base_url
	token_id = id

func _ready() -> void:
	_build_scene()
	_build_hud()
	_dummy_grid = GridManager.new() # not added to the tree -- see its own var comment
	_poll_timer = Timer.new()
	_poll_timer.wait_time = poll_interval_seconds
	_poll_timer.timeout.connect(_poll_state)
	add_child(_poll_timer)
	_poll_timer.start()
	_state_request = HTTPRequest.new()
	add_child(_state_request)
	_state_request.request_completed.connect(_on_state_response)
	_poll_state()

func _build_scene() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.12, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	environment.ambient_light_energy = 0.7
	env_node.environment = environment
	add_child(env_node)

	# Much tighter orbit range than the board's own CameraRig defaults (6-40) -- this
	# is one miniature filling the frame, not a whole room.
	_camera_rig = CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D" # CameraRig's own @onready var camera: Camera3D = $Camera3D needs this exact name
	_camera_rig.add_child(camera)
	_camera_rig.min_distance = 1.0
	_camera_rig.max_distance = 8.0
	_camera_rig.distance = 3.5
	_camera_rig.pitch_deg = 25.0
	add_child(_camera_rig)
	_camera_rig.center_on(Vector3(0, 1.0, 0)) # roughly chest height on a human-sized miniature, not its feet

	_model_token = TokenScene.instantiate() as Token
	add_child(_model_token)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0) # default top-left position/anchors are fine -- a single fixed-width panel, not a full-width bar
	canvas.add_child(panel)

	var layout := VBoxContainer.new()
	panel.add_child(layout)

	_sync_status_label = Label.new()
	_sync_status_label.text = "Connecting..."
	layout.add_child(_sync_status_label)

	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.custom_minimum_size = Vector2(300, 400)
	layout.add_child(_stats_label)

	var load_row := HBoxContainer.new()
	var load_label := Label.new()
	load_label.text = "Preview .glb file:"
	load_row.add_child(load_label)
	_model_path_input = LineEdit.new()
	_model_path_input.placeholder_text = "e.g. I:\\Campaign-OS-3D\\Downloaded Static Models\\...\\model.glb"
	_model_path_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_model_path_input)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_model_pressed)
	load_row.add_child(load_button)
	layout.add_child(load_row)

	_load_status_label = Label.new()
	_load_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_load_status_label)

func _poll_state() -> void:
	var error := _state_request.request(server_base_url + "/state")
	if error != OK:
		_sync_status_label.text = "Could not reach engine-server at %s (error %d)" % [server_base_url, error]

func _on_state_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_sync_status_label.text = "engine-server returned HTTP %d" % response_code
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("state"):
		_sync_status_label.text = "engine-server sent a response this client doesn't understand."
		return

	var state: Dictionary = parsed["state"]
	var data
	for token_data in state.get("tokens", []):
		if str(token_data.get("id", "")) == token_id:
			data = token_data
			break

	if data == null:
		_sync_status_label.text = "This token no longer exists (removed, or the encounter was reset)."
		return
	_sync_status_label.text = "Live"
	_apply_token(data)

## Drives the embedded Token through the exact same apply_data() the board itself
## calls -- model resolution/grounding/miniature-finish, HP bar, name label, all
## identical to what's on the board, just rendered close-up. Position is reset to the
## origin afterward: apply_data() places it via grid.cell_to_world(data.x, data.y),
## a meaningless coordinate here (no board, no grid) -- only the model/label/HP-bar
## SIDE EFFECTS of apply_data() matter to this viewer, not the resulting transform.
##
## A Load Model override is unconditionally re-applied every tick, cheap enough at
## this scale (one model, ~1s poll -- same "just rebuild, don't bother diffing"
## convention GridManager's grid lines/PlayerView's fog overlay already use) and
## simpler than tracking whether apply_data() happened to rebuild the model this
## particular tick. Safe specifically because preview_external_model() (see its own
## doc comment in Token.gd) defensively detaches its argument from whatever it's
## currently parented under before re-adding it -- without that, calling this on an
## already-attached override node would throw ("already has a parent").
func _apply_token(data: Dictionary) -> void:
	_model_token.apply_data(data, _dummy_grid)
	_model_token.position = Vector3.ZERO
	if _custom_model_instance and is_instance_valid(_custom_model_instance):
		_model_token.preview_external_model(_custom_model_instance)
	_stats_label.text = _format_stats(data)

func _format_stats(data: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % str(data.get("name", "")))
	lines.append("Type: %s" % str(data.get("type", "")))
	lines.append("HP: %d / %d    AC: %s" % [int(data.get("hp", 0)), int(data.get("maxHp", 0)), str(data.get("ac", "-"))])
	lines.append("Speed: %s ft." % str(data.get("speed", "-")))

	var ability_scores: Dictionary = data.get("abilityScores", {})
	if not ability_scores.is_empty():
		var ability_line: Array[String] = []
		for key in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
			if ability_scores.has(key):
				var score := int(ability_scores[key])
				var modifier := int(floor((score - 10) / 2.0))
				ability_line.append("%s %d (%s)" % [key, score, ("+%d" % modifier) if modifier >= 0 else str(modifier)])
		lines.append(", ".join(PackedStringArray(ability_line)))

	var conditions: Array = data.get("conditions", [])
	lines.append("Conditions: %s" % (", ".join(PackedStringArray(conditions)) if not conditions.is_empty() else "none"))

	if data.get("dying") != null:
		lines.append("[color=orange]Dying[/color]")
	if bool(data.get("dead", false)):
		lines.append("[color=red]Dead[/color]")

	var spellcasting = data.get("spellcasting")
	if spellcasting != null:
		lines.append("Spell save DC %s, attack +%s" % [str(spellcasting.get("saveDC", "-")), str(spellcasting.get("attackBonus", "-"))])

	var resources: Dictionary = data.get("resources", {})
	if not resources.is_empty():
		var resource_line: Array[String] = []
		for res_name in resources:
			var res = resources[res_name]
			resource_line.append("%s %s/%s" % [res_name, str(res.get("current", "-")), str(res.get("max", "-"))])
		lines.append("Resources: %s" % ", ".join(PackedStringArray(resource_line)))

	return "\n".join(PackedStringArray(lines))

## Loads an arbitrary .glb/.gltf file from anywhere on disk at RUNTIME, via
## GLTFDocument -- Godot's own importer-independent glTF reader -- rather than
## ResourceLoader.load(), which only works for files already inside this project's
## own res:// tree with a real .import already generated (everything under
## godot/assets/). This is specifically for previewing a candidate model BEFORE
## deciding to copy it into the project and wire it into Token.gd's own MODEL_CONFIG
## -- e.g. straight out of the model-sourcing library, which sits entirely outside
## this Godot project and was never going to have a real .import regardless.
## FBX isn't supported this way -- Godot's FBX pipeline is editor-import-time only
## (via the bundled FBX2glTF converter), with no runtime-loader equivalent -- so this
## only helps for .glb/.gltf files, the overwhelming majority of that library per its
## own sourcing notes ("models must be plain/static .glb, not rigged bipeds").
func _load_external_glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		return null
	return document.generate_scene(state) as Node3D

func _on_load_model_pressed() -> void:
	var path := _model_path_input.text.strip_edges()
	if path == "":
		_load_status_label.text = "Enter a .glb/.gltf file path first."
		return
	var lower := path.to_lower()
	if not (lower.ends_with(".glb") or lower.ends_with(".gltf")):
		_load_status_label.text = "Only .glb/.gltf can be previewed this way -- FBX needs the editor's own import step, see this button's own doc comment."
		return
	if not FileAccess.file_exists(path):
		_load_status_label.text = "File not found: %s" % path
		return

	var instance := _load_external_glb(path)
	if instance == null:
		_load_status_label.text = "Could not parse that file as glTF."
		return

	if _custom_model_instance and is_instance_valid(_custom_model_instance):
		_custom_model_instance.queue_free()
	_model_token.preview_external_model(instance)
	_custom_model_instance = instance
	_load_status_label.text = "Previewing %s (this session only -- not saved to MODEL_CONFIG)." % path.get_file()
