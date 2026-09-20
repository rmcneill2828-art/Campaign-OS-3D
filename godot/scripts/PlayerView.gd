extends Node3D
## Phase 6 -- the read-only, player-facing 3D view: a second, independent
## poller against the same engine-server (see Main.gd's own doc comment on
## why this doesn't just receive pushed updates from the DM window instead),
## rendering the same board/tokens but through the SAME two filters
## ui/playerView.js already established for the 2D app's own Player Window --
## `hiddenFromPlayers` and line-of-sight (`isVisibleToParty`) -- both already
## computed server-side into `visibility.visibleTokenIds` (see
## engine-server/server.js's computeVisibility()), not re-derived here, so
## this client can't drift from what the 2D app actually does by
## reimplementing the rule slightly differently.
##
## No action-sending code exists in this script AT ALL -- no click handling,
## no HUD buttons, nothing that calls POST /action. This is deliberate, not
## an oversight: this window is meant to sit on a second monitor/TV a player
## might be looking at, and should be physically incapable of mutating the
## encounter no matter what gets clicked in it. CameraRig's own orbit/pan/zoom
## still works (camera framing isn't a game action), matching the 2D app's
## camera-equivalent (its Player Window can't be repositioned by players
## either, but that's just because the 2D app never gave it one -- this
## client already had CameraRig, so leaving it on is a free, harmless
## convenience for a DM who walks over to the TV to adjust framing).

const TokenScene := preload("res://scenes/Token.tscn")

@export var server_base_url := "http://127.0.0.1:8787"
@export var poll_interval_seconds := 1.0

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _board: GridManager = $Board
@onready var _tokens_root: Node3D = $TokensRoot
@onready var _fog_root: Node3D = $FogRoot
@onready var _state_request: HTTPRequest = $StateRequest
@onready var _poll_timer: Timer = $PollTimer
@onready var _map_name_label: Label = $HUD/MapNameLabel
@onready var _turn_status_label: Label = $HUD/TurnStatusLabel
@onready var _sync_status_label: Label = $HUD/SyncStatusLabel
@onready var _initiative_list: VBoxContainer = $HUD/SidePanel/SidePanelScroll/SidePanelList/InitiativeList
@onready var _combat_log_list: VBoxContainer = $HUD/SidePanel/SidePanelScroll/SidePanelList/CombatLogList

var _tokens := {} # token id (String) -> Token node
var _last_centered_map_name := "" # not just a one-time flag -- see _apply_state()'s own use, below

func _ready() -> void:
	_poll_timer.wait_time = poll_interval_seconds
	_poll_timer.timeout.connect(_poll_state)
	_state_request.request_completed.connect(_on_state_response)
	_poll_state()

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
	# `visibility` only exists on responses from a server that's actually run
	# the Phase 5 computeVisibility() code -- defaults to "nothing visible"
	# rather than crashing if an older/mismatched server is somehow in front
	# of this client, same defensive-default spirit as Main.gd's own parsing.
	var visibility: Dictionary = parsed.get("visibility", {})
	_apply_state(parsed["state"], visibility)
	_sync_status_label.text = "Live"

func _apply_state(state: Dictionary, visibility: Dictionary) -> void:
	var map_name: String = state.get("mapName", "")
	if map_name == "":
		_map_name_label.text = "No map loaded"
		_turn_status_label.text = "No active turn"
		for child in _tokens_root.get_children():
			child.queue_free()
		_tokens.clear()
		for child in _fog_root.get_children():
			child.queue_free()
		_initiative_list_clear()
		_combat_log_list_clear()
		return

	_map_name_label.text = map_name
	var map_data: Dictionary = state.get("maps", {}).get(map_name, {})
	var columns: int = int(map_data.get("columns", 12))
	var rows: int = int(map_data.get("rows", 8))
	var feet_per_square: float = float(map_data.get("feetPerSquare", 5))
	_board.build(columns, rows, feet_per_square, MapScenes.resolve(map_name), MapImagePath.resolve(map_name), map_data.get("walls", []), map_data.get("doors", []))

	# Re-centers whenever the ACTIVE map actually changes -- same fix as
	# Main.gd's own _apply_state(), for the same reason: a one-shot flag left
	# this view's camera pointed at whichever map was active when it first
	# connected, forever, once a second differently-sized map existed to
	# switch to.
	if map_name != _last_centered_map_name:
		_camera_rig.center_on(_board.board_center())
		_last_centered_map_name = map_name

	# The one filter this entire client exists to apply: server-computed
	# visibleTokenIds already folds in BOTH hiddenFromPlayers and real line of
	# sight (see this file's own class doc comment) -- a token failing either
	# check just never gets instantiated here at all, not hidden via a
	# visibility toggle a curious player could someday flip back on.
	var visible_ids: Dictionary = {}
	for id in visibility.get("visibleTokenIds", []):
		visible_ids[str(id)] = true

	var filtered_tokens: Array = []
	var seen_ids := {}
	for token_data in state.get("tokens", []):
		if token_data.get("mapName", "") != map_name:
			continue
		var id: String = str(token_data.get("id", ""))
		if id == "" or not visible_ids.has(id):
			continue
		filtered_tokens.append(token_data)
		seen_ids[id] = true
		var token: Token = _tokens.get(id)
		if token == null:
			token = TokenScene.instantiate() as Token
			token.player_facing = true # redacts the floating label -- see Token.gd
			_tokens_root.add_child(token)
			_tokens[id] = token
		token.apply_data(token_data, _board)

	for id in _tokens.keys():
		if not seen_ids.has(id):
			_tokens[id].queue_free()
			_tokens.erase(id)

	var walls: Array = map_data.get("walls", [])
	_rebuild_fog(columns, rows, not walls.is_empty(), visibility.get("revealed", []), visibility.get("currentlyVisible", []))
	_update_turn_status(state, filtered_tokens)
	_update_initiative(filtered_tokens, state.get("turn", {}).get("tokenId"))
	_update_combat_log(state.get("log", []))

## Same three-state fog model ui/playerView.js's renderMapGrid() already
## established (never explored / explored-but-not-currently-visible /
## currently visible), and the same "only active on a map that actually has
## walls drawn" gate -- a wall-free map has no restriction at all
## (isVisibleToParty's own fast path), so it should render exactly as it
## always has, with no dimming, not "everything unexplored." A flat
## unshaded, semi-transparent PlaneMesh per fogged cell, cheap enough to
## fully rebuild every poll the same way this project's grid-line overlay
## already is (see GridManager._build_grid_lines()'s own precedent for
## "rebuild-from-scratch is fine at this scale").
func _rebuild_fog(columns: int, rows: int, fog_active: bool, revealed: Array, currently_visible: Array) -> void:
	for child in _fog_root.get_children():
		child.queue_free()
	if not fog_active:
		return

	var revealed_set := {}
	for cell in revealed:
		revealed_set["%d,%d" % [int(cell[0]), int(cell[1])]] = true
	var visible_set := {}
	for cell in currently_visible:
		visible_set["%d,%d" % [int(cell[0]), int(cell[1])]] = true

	for x in range(1, columns + 1):
		for y in range(1, rows + 1):
			var key := "%d,%d" % [x, y]
			var color: Color
			if not revealed_set.has(key):
				color = Color(0, 0, 0, 0.95) # never explored -- effectively solid
			elif not visible_set.has(key):
				color = Color(0, 0, 0, 0.55) # explored, not currently visible -- dimmed
			else:
				continue # currently visible -- no overlay at all

			var quad := MeshInstance3D.new()
			var mesh := PlaneMesh.new()
			mesh.size = Vector2(_board.cell_size, _board.cell_size)
			quad.mesh = mesh
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = color
			quad.material_override = material
			quad.position = _board.cell_to_world(x, y) + Vector3(0, 0.02, 0)
			_fog_root.add_child(quad)

## Mirrors ui/playerView.js's renderInitiative() exactly, including its one
## quirk: the active token is looked up in the ALREADY-FILTERED list, so a
## turn that's active on a token this window isn't allowed to show (hidden,
## or out of every hero's sight) reports "No active turn" rather than naming
## it -- a deliberate consequence of that precedent, not something to "fix"
## here and diverge from it.
func _update_turn_status(state: Dictionary, filtered_tokens: Array) -> void:
	var round_number: int = int(state.get("turn", {}).get("round", 0))
	var active_id = state.get("turn", {}).get("tokenId")
	var active_name := ""
	for token_data in filtered_tokens:
		if str(token_data.get("id", "")) == str(active_id):
			active_name = str(token_data.get("name", ""))
			break
	_turn_status_label.text = ("Round %d -- %s's turn" % [round_number, active_name]) if active_name != "" else "No active turn"

func _update_initiative(filtered_tokens: Array, active_id) -> void:
	_initiative_list_clear()
	var sorted := filtered_tokens.duplicate()
	sorted.sort_custom(func(a, b):
		var ia := int(a.get("initiative", 0))
		var ib := int(b.get("initiative", 0))
		if ia != ib:
			return ia > ib
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	for token_data in sorted:
		var line := "%s -- %d" % [token_data.get("name", ""), int(token_data.get("initiative", 0))]
		if bool(token_data.get("dead", false)):
			line += "  [DEAD]"
		elif token_data.get("dying") != null:
			line += "  [STABLE]" if bool(token_data.get("dying", {}).get("stable", false)) else "  [DYING]"
		var label := Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 16)
		if str(token_data.get("id", "")) == str(active_id):
			label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
		_initiative_list.add_child(label)

## Unredacted, matching ui/playerView.js's own documented gap: combat log
## text isn't scrubbed of a hidden token's name even though the token itself
## wouldn't render on the map -- a known, accepted limitation there, not
## something to silently "fix" (and possibly get wrong) here.
func _update_combat_log(log: Array) -> void:
	_combat_log_list_clear()
	if log.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No attacks yet."
		empty_label.add_theme_font_size_override("font_size", 14)
		_combat_log_list.add_child(empty_label)
		return
	for entry in log:
		var label := Label.new()
		label.text = str(entry)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		_combat_log_list.add_child(label)

func _initiative_list_clear() -> void:
	for child in _initiative_list.get_children():
		child.queue_free()

func _combat_log_list_clear() -> void:
	for child in _combat_log_list.get_children():
		child.queue_free()
