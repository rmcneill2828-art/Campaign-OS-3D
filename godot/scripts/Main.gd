extends Node3D
## Ties the whole prototype together: polls engine-server/ for the live encounter
## state, builds/updates the 3D board and tokens from it, and turns clicks/button
## presses into actions sent back to the server. All 5e rules (can this move,
## does this attack hit, how much damage, whose turn is it) are decided
## server-side by the real, unmodified engine/*.js -- this script only ever
## renders what the server reports and asks it to do things, never computes a
## rule itself. See ../../ARCHITECTURE.md.
##
## Controls: left-click a token to select it (as the mover/attacker), then
## left-click a floor tile to move it, or right-click (a quick click, not a
## camera-orbit drag) a different token to attack it with the selected one.
## "Next Turn" in the HUD advances the turn tracker.

const TokenScene := preload("res://scenes/Token.tscn")

## A right-click is only treated as "attack" if the mouse barely moved between
## press and release -- otherwise a right-drag meant purely to orbit the camera
## (CameraRig.gd handles that independently) would also fire an attack.
const RIGHT_CLICK_DRAG_THRESHOLD_PX := 6.0

@export var server_base_url := "http://127.0.0.1:8787"
@export var poll_interval_seconds := 1.0

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _board: GridManager = $Board
@onready var _tokens_root: Node3D = $TokensRoot
@onready var _state_request: HTTPRequest = $StateRequest
@onready var _action_request: HTTPRequest = $ActionRequest
@onready var _poll_timer: Timer = $PollTimer
@onready var _status_label: Label = $HUD/StatusLabel
@onready var _next_turn_button: Button = $HUD/NextTurnButton

var _tokens := {} # token id (String) -> Token node
var _selected_token_id := ""
var _camera_centered := false
var _action_in_flight := false

var _right_press_pos := Vector2.ZERO
var _right_press_active := false

func _ready() -> void:
	_poll_timer.wait_time = poll_interval_seconds
	_poll_timer.timeout.connect(_poll_state)
	_state_request.request_completed.connect(_on_state_response)
	_action_request.request_completed.connect(_on_action_response)
	_next_turn_button.pressed.connect(_on_next_turn_pressed)
	_poll_state()

func _poll_state() -> void:
	var error := _state_request.request(server_base_url + "/state")
	if error != OK:
		_status_label.text = "Could not reach engine-server at %s -- is `node server.js` running? (error %d)" % [server_base_url, error]

func _on_state_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_status_label.text = "engine-server returned HTTP %d -- is it running the expected version?" % response_code
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("state"):
		_status_label.text = "engine-server sent a response this client doesn't understand."
		return
	_apply_state(parsed["state"])

func _apply_state(state: Dictionary) -> void:
	var map_name: String = state.get("mapName", "")
	var map_data: Dictionary = state.get("maps", {}).get(map_name, {})
	# Mirrors engine/encounter.js's own currentGrid()/feetPerSquare() fallbacks
	# (12x8, 5 ft/square) so an unconfigured map still renders something
	# sensible instead of a 0x0 board or the wrong-sized squares.
	var columns: int = int(map_data.get("columns", 12))
	var rows: int = int(map_data.get("rows", 8))
	var feet_per_square: float = float(map_data.get("feetPerSquare", 5))
	_board.build(columns, rows, feet_per_square)

	if not _camera_centered:
		_camera_rig.center_on(_board.board_center())
		_camera_centered = true

	var tokens_on_map: Array = []
	var seen_ids := {}
	for token_data in state.get("tokens", []):
		if token_data.get("mapName", "") != map_name:
			continue
		tokens_on_map.append(token_data)
		var id: String = str(token_data.get("id", ""))
		if id == "":
			continue
		seen_ids[id] = true
		var token: Token = _tokens.get(id)
		if token == null:
			token = TokenScene.instantiate() as Token
			_tokens_root.add_child(token)
			_tokens[id] = token
		token.apply_data(token_data, _board)
		token.set_selected(id == _selected_token_id)

	# Drop tokens that no longer exist on this map (removed, or the DM switched
	# maps) -- avoids ghost miniatures nothing in the state array explains anymore.
	for id in _tokens.keys():
		if not seen_ids.has(id):
			_tokens[id].queue_free()
			_tokens.erase(id)
			if id == _selected_token_id:
				_selected_token_id = ""

	_update_status_label(state, map_name, tokens_on_map)

func _update_status_label(state: Dictionary, map_name: String, tokens_on_map: Array) -> void:
	var turn_data: Dictionary = state.get("turn", {})
	var round_number: int = int(turn_data.get("round", 0))
	var active_token_id = turn_data.get("tokenId")

	var turn_line: String
	if round_number <= 0:
		turn_line = "Turn order not started -- Next Turn begins it."
	else:
		var active_name := ""
		for token_data in tokens_on_map:
			if str(token_data.get("id", "")) == str(active_token_id):
				active_name = str(token_data.get("name", ""))
				break
		turn_line = ("Round %d -- %s's turn." % [round_number, active_name]) if active_name != "" \
			else "Round %d." % round_number

	var selection_note := ""
	if _selected_token_id != "" and _tokens.has(_selected_token_id):
		selection_note = "\nSelected: %s -- left-click a tile to move, right-click another token to attack." % _tokens[_selected_token_id].token_name

	var last_log := ""
	var log: Array = state.get("log", [])
	if log.size() > 0:
		last_log = str(log[0])

	_status_label.text = "Connected -- %s\n%s%s\n%s" % [map_name, turn_line, selection_note, last_log]

func _on_next_turn_pressed() -> void:
	_send_action({"type": "next_turn"})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_press_pos = event.position
				_right_press_active = true
			elif _right_press_active:
				_right_press_active = false
				if event.position.distance_to(_right_press_pos) <= RIGHT_CLICK_DRAG_THRESHOLD_PX:
					_handle_right_click(event.position)

func _raycast_from_screen(screen_pos: Vector2) -> Dictionary:
	var camera: Camera3D = _camera_rig.camera
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 500.0
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return space_state.intersect_ray(query)

func _handle_left_click(screen_pos: Vector2) -> void:
	var hit := _raycast_from_screen(screen_pos)
	if hit.is_empty():
		return

	var collider: Node = hit["collider"]
	if collider.is_in_group("tokens"):
		_select_token(collider.get_meta("token"))
	elif collider.is_in_group("floor") and _selected_token_id != "":
		var cell: Vector2i = _board.world_to_cell(hit["position"])
		_send_move(_selected_token_id, cell.x, cell.y)

func _handle_right_click(screen_pos: Vector2) -> void:
	if _selected_token_id == "" or not _tokens.has(_selected_token_id):
		_status_label.text = "Left-click a token to select an attacker first, then right-click a target."
		return

	var hit := _raycast_from_screen(screen_pos)
	if hit.is_empty():
		return
	var collider: Node = hit["collider"]
	if not collider.is_in_group("tokens"):
		return

	var target: Token = collider.get_meta("token")
	if target.token_id == _selected_token_id:
		return

	var attacker_name: String = _tokens[_selected_token_id].token_name
	_send_action({"type": "attack", "attacker": attacker_name, "target": target.token_name})

func _select_token(token: Token) -> void:
	if _tokens.has(_selected_token_id):
		_tokens[_selected_token_id].set_selected(false)
	_selected_token_id = token.token_id
	token.set_selected(true)

func _send_move(token_id: String, x: int, y: int) -> void:
	if not _tokens.has(token_id):
		return
	# move_token (like every dm-bridge action) resolves its target by NAME, not id --
	# see engine-server/engine/dmBridge.js's findTokenByName.
	var token_name: String = _tokens[token_id].token_name
	_send_action({"type": "move_token", "target": token_name, "x": x, "y": y})

## One action in flight at a time -- good enough for a single-DM prototype; a busy
## flag here is simpler than queuing and avoids the server seeing two calls race
## against the same in-memory state.
func _send_action(action: Dictionary) -> void:
	if _action_in_flight:
		return
	_action_in_flight = true
	var body := JSON.stringify(action)
	var error := _action_request.request(
		server_base_url + "/action",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_action_in_flight = false
		_status_label.text = "Could not send action to engine-server (error %d)." % error

func _on_action_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_action_in_flight = false
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200:
		var error_text: String = "unknown error"
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
			error_text = str(parsed["error"])
		_status_label.text = "Action failed (HTTP %d): %s" % [response_code, error_text]
		return
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("state"):
		_apply_state(parsed["state"])
