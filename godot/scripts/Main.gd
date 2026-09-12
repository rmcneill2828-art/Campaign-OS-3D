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

## Duplicated from engine-server/engine/encounter.js's own ABILITY_KEYS/
## SKILL_LIST rather than fetched at runtime -- same "no shared-module
## mechanism between these plain scripts" convention that project already
## uses to duplicate this exact list across encounter.js/campaign.js/
## dm-bridge/watch.js. Keep in sync by hand if the engine's list ever changes.
const ABILITY_KEYS: Array[String] = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const SKILL_LIST: Array[String] = [
	"Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception",
	"History", "Insight", "Intimidation", "Investigation", "Medicine",
	"Nature", "Perception", "Performance", "Persuasion", "Religion",
	"Sleight of Hand", "Stealth", "Survival"
]

## Duplicated from engine-server/engine/encounter.js's own conditionList --
## same convention as ABILITY_KEYS/SKILL_LIST above.
const CONDITION_LIST: Array[String] = [
	"Blinded", "Charmed", "Frightened", "Grappled", "Invisible", "Paralyzed",
	"Poisoned", "Prone", "Restrained", "Stunned", "Unconscious"
]

## Duplicated from engine-server/engine/encounter.js's own DAMAGE_TYPE_LIST --
## same convention as the lists above. "(none)" is this client's own addition
## (index 0), not the engine's -- damageType is optional on both cast actions
## (an untyped/flat amount is a valid, common case), so the dropdown needs a
## way to mean "don't set one" distinct from any of the 13 real types.
const DAMAGE_TYPE_NONE := "(none)"
const DAMAGE_TYPE_LIST: Array[String] = [
	DAMAGE_TYPE_NONE, "acid", "bludgeoning", "cold", "fire", "force",
	"lightning", "necrotic", "piercing", "poison", "psychic", "radiant",
	"slashing", "thunder"
]
const SPELL_TARGET_NONE := "(no target)"

@export var server_base_url := "http://127.0.0.1:8787"
@export var poll_interval_seconds := 1.0

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _board: GridManager = $Board
@onready var _tokens_root: Node3D = $TokensRoot
@onready var _state_request: HTTPRequest = $StateRequest
@onready var _action_request: HTTPRequest = $ActionRequest
@onready var _poll_timer: Timer = $PollTimer
@onready var _status_label: Label = $HUD/StatusLabel
@onready var _hint_label: Label = $HUD/HintLabel
@onready var _hint_timer: Timer = $HUD/HintTimer
@onready var _next_turn_button: Button = $HUD/NextTurnButton
@onready var _save_ability_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SaveRow/SaveAbilityOption
@onready var _roll_save_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SaveRow/RollSaveButton
@onready var _check_skill_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/CheckRow/CheckSkillOption
@onready var _roll_check_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/CheckRow/RollCheckButton
@onready var _dc_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DCRow/DCInput
@onready var _conditions_grid: GridContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ConditionsGrid

@onready var _spell_name_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellNameRow/SpellNameInput
@onready var _spell_level_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellLevelRow/SpellLevelInput
@onready var _spell_target_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellTargetRow/SpellTargetOption
@onready var _spell_damage_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellDamageRow/SpellDamageInput
@onready var _spell_damage_type_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellDamageRow/SpellDamageTypeOption
@onready var _spell_concentration_check: CheckBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellConcentrationCheck
@onready var _cast_spell_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/CastSpellButton
@onready var _area_targets_list: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/AreaSpellTargetsList
@onready var _area_save_ability_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/AreaSaveRow/AreaSaveAbilityOption
@onready var _area_save_dc_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/AreaSaveRow/AreaSaveDCInput
@onready var _area_half_on_save_check: CheckBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/AreaSaveRow/AreaHalfOnSaveCheck
@onready var _cast_area_spell_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/CastAreaSpellButton

@onready var _resource_name_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceRow/ResourceNameInput
@onready var _use_resource_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceRow/UseResourceButton
@onready var _long_rest_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/RestRow/LongRestButton
@onready var _short_rest_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/RestRow/ShortRestButton
@onready var _death_save_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DeathSaveButton
@onready var _exhaustion_minus_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ExhaustionRow/ExhaustionMinusButton
@onready var _exhaustion_plus_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ExhaustionRow/ExhaustionPlusButton
@onready var _legendary_action_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/LegendaryActionButton
@onready var _recharge_name_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/RechargeRow/RechargeNameInput
@onready var _use_recharge_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/RechargeRow/UseRechargeButton
@onready var _lair_description_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/LairRow/LairDescriptionInput
@onready var _trigger_lair_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/LairRow/TriggerLairButton

var _condition_buttons := {} # condition name (String) -> Button (toggle_mode)
var _area_target_checkboxes := {} # token name (String) -> CheckBox
var _last_target_names: Array[String] = [] # last set the spell-target UI was built from -- see _sync_spell_targets()

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

	for ability in ABILITY_KEYS:
		_save_ability_option.add_item(ability)
	for ability in ABILITY_KEYS:
		_check_skill_option.add_item(ability)
	for skill in SKILL_LIST:
		_check_skill_option.add_item(skill)
	_roll_save_button.pressed.connect(_on_roll_save_pressed)
	_roll_check_button.pressed.connect(_on_roll_check_pressed)
	_hint_timer.timeout.connect(func(): _hint_label.text = "")

	for condition in CONDITION_LIST:
		var button := Button.new()
		button.text = condition
		button.toggle_mode = true
		button.toggled.connect(_on_condition_toggled.bind(condition))
		_conditions_grid.add_child(button)
		_condition_buttons[condition] = button

	for damage_type in DAMAGE_TYPE_LIST:
		_spell_damage_type_option.add_item(damage_type)
	_spell_target_option.add_item(SPELL_TARGET_NONE)
	for ability in ABILITY_KEYS:
		_area_save_ability_option.add_item(ability)
	_cast_spell_button.pressed.connect(_on_cast_spell_pressed)
	_cast_area_spell_button.pressed.connect(_on_cast_area_spell_pressed)

	_use_resource_button.pressed.connect(_on_use_resource_pressed)
	_long_rest_button.pressed.connect(_on_long_rest_pressed)
	_short_rest_button.pressed.connect(_on_short_rest_pressed)
	_death_save_button.pressed.connect(_on_death_save_pressed)
	_exhaustion_plus_button.pressed.connect(_on_exhaustion_pressed.bind(1))
	_exhaustion_minus_button.pressed.connect(_on_exhaustion_pressed.bind(-1))
	_legendary_action_button.pressed.connect(_on_legendary_action_pressed)
	_use_recharge_button.pressed.connect(_on_use_recharge_pressed)
	_trigger_lair_button.pressed.connect(_on_trigger_lair_pressed)

	_poll_state()

## For one-off feedback about something the user just tried (a missing
## selection, a failed action) -- NOT for ongoing status (map/round/log),
## which stays on _status_label. These used to share one label, and the
## 1-second poll cycle overwrote a hint almost as soon as it appeared --
## found by the user trying to read the "select a token first" message and
## watching it vanish. A separate label with its own timer means a poll
## landing mid-hint can no longer erase it early.
func _show_hint(message: String) -> void:
	_hint_label.text = message
	_hint_timer.start()

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

	_sync_condition_buttons(tokens_on_map)
	_sync_spell_targets(tokens_on_map)
	_update_status_label(state, map_name, tokens_on_map)

## Reflects the selected token's real conditions array onto the toggle
## buttons -- set_pressed_no_signal(), not the plain button_pressed property,
## since assigning that would itself re-emit `toggled` and loop back into
## _on_condition_toggled(), sending a spurious toggle_condition action for
## every poll tick.
func _sync_condition_buttons(tokens_on_map: Array) -> void:
	var active_conditions: Array = []
	if _selected_token_id != "":
		for token_data in tokens_on_map:
			if str(token_data.get("id", "")) == _selected_token_id:
				active_conditions = token_data.get("conditions", [])
				break
	for condition in _condition_buttons:
		var button: Button = _condition_buttons[condition]
		button.set_pressed_no_signal(active_conditions.has(condition))

## Rebuilds the single-target dropdown and the area-target checkbox list only
## when the actual set of token names on the map has changed -- rebuilding on
## every poll (every ~1s) would reset whatever the user was mid-way through
## picking, since OptionButton/CheckBox selection state doesn't survive
## clear()+re-add(). Self-targeting is left possible on purpose (e.g. a caster
## healing themselves) -- the list isn't filtered to exclude the caster.
func _sync_spell_targets(tokens_on_map: Array) -> void:
	var names: Array[String] = []
	for token_data in tokens_on_map:
		var name := str(token_data.get("name", ""))
		if name != "":
			names.append(name)
	names.sort()
	if names == _last_target_names:
		return
	_last_target_names = names

	var previous_single: String = ""
	if _spell_target_option.selected > 0:
		previous_single = _spell_target_option.get_item_text(_spell_target_option.selected)
	_spell_target_option.clear()
	_spell_target_option.add_item(SPELL_TARGET_NONE)
	for name in names:
		_spell_target_option.add_item(name)
		if name == previous_single:
			_spell_target_option.selected = _spell_target_option.item_count - 1

	var previously_checked := {}
	for name in _area_target_checkboxes:
		if _area_target_checkboxes[name].button_pressed:
			previously_checked[name] = true
	for child in _area_targets_list.get_children():
		child.queue_free()
	_area_target_checkboxes.clear()
	for name in names:
		var checkbox := CheckBox.new()
		checkbox.text = name
		checkbox.button_pressed = previously_checked.has(name)
		_area_targets_list.add_child(checkbox)
		_area_target_checkboxes[name] = checkbox

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
		selection_note = "\nSelected: %s -- left-click a tile to move, right-click another token to attack, Esc to deselect." % _tokens[_selected_token_id].token_name

	var last_log := ""
	var log: Array = state.get("log", [])
	if log.size() > 0:
		last_log = str(log[0])

	_status_label.text = "Connected -- %s\n%s%s\n%s" % [map_name, turn_line, selection_note, last_log]

func _on_next_turn_pressed() -> void:
	_send_action({"type": "next_turn"})

## rollSavingThrow (see engine-server/engine/encounter.js) uses the target's
## real ability modifier or a stated save-bonus override, rolls once, and
## only reports pass/fail -- no follow-up effect (e.g. half damage on a
## success) happens automatically; that's still a separate later action once
## the result is visible in the log, same as the 2D app's own documented
## behavior for this.
func _on_roll_save_pressed() -> void:
	if not _require_selected_token():
		return
	var ability: String = _save_ability_option.get_item_text(_save_ability_option.selected)
	_send_action({
		"type": "saving_throw",
		"target": _tokens[_selected_token_id].token_name,
		"ability": ability,
		"dc": int(_dc_input.value)
	})

## ability_check's `skill` accepts either a bare ability key or a named skill
## interchangeably (rollAbilityCheck resolves either) -- the same one
## dropdown lists both rather than needing two separate controls.
func _on_roll_check_pressed() -> void:
	if not _require_selected_token():
		return
	var skill: String = _check_skill_option.get_item_text(_check_skill_option.selected)
	_send_action({
		"type": "ability_check",
		"target": _tokens[_selected_token_id].token_name,
		"skill": skill,
		"dc": int(_dc_input.value)
	})

## cast_spell handles everything server-side: spends the caster's slot at
## `level` (0 = cantrip, never consumes one), and -- only when a target is
## given -- rolls a spell attack against it using the caster's own stated
## spell attack bonus. A save-based spell with no damage of its own (Hold
## Person) has no target/damage here; that's a separate saving_throw per
## target once this response is visible, same one-shot-batch limitation the
## Claude DM bridge itself documents for this action.
func _on_cast_spell_pressed() -> void:
	if not _require_selected_token():
		return
	var spell_name := _spell_name_input.text.strip_edges()
	if spell_name == "":
		_show_hint("Enter a spell name before casting.")
		return

	var action := {
		"type": "cast_spell",
		"caster": _tokens[_selected_token_id].token_name,
		"spell": spell_name,
		"level": int(_spell_level_input.value),
		"concentration": _spell_concentration_check.button_pressed
	}
	if _spell_target_option.selected > 0:
		action["target"] = _spell_target_option.get_item_text(_spell_target_option.selected)
	var damage := _spell_damage_input.text.strip_edges()
	if damage != "":
		action["damageDice"] = damage
		var damage_type := _spell_damage_type_option.get_item_text(_spell_damage_type_option.selected)
		if damage_type != DAMAGE_TYPE_NONE:
			action["damageType"] = damage_type
	_send_action(action)

## cast_area_spell resolves a save-for-half effect (Fireball, Burning Hands)
## against every checked target in one call: one damage roll for the whole
## area, one save per target, full damage on a failure or half (or none, if
## "Half on save" is unchecked) on a success -- computed entirely
## server-side. Shares the spell name/level/damage/damage-type/concentration
## fields with the single-target form above rather than duplicating them.
func _on_cast_area_spell_pressed() -> void:
	if not _require_selected_token():
		return
	var spell_name := _spell_name_input.text.strip_edges()
	if spell_name == "":
		_show_hint("Enter a spell name before casting.")
		return
	var damage := _spell_damage_input.text.strip_edges()
	if damage == "":
		_show_hint("An area spell needs a damage dice value (e.g. 3d6).")
		return
	var targets: Array[String] = []
	for name in _area_target_checkboxes:
		if _area_target_checkboxes[name].button_pressed:
			targets.append(name)
	if targets.is_empty():
		_show_hint("Check at least one target for an area spell.")
		return

	var action := {
		"type": "cast_area_spell",
		"caster": _tokens[_selected_token_id].token_name,
		"spell": spell_name,
		"level": int(_spell_level_input.value),
		"targets": targets,
		"damageDice": damage,
		"saveAbility": _area_save_ability_option.get_item_text(_area_save_ability_option.selected),
		"saveDC": int(_area_save_dc_input.value),
		"halfOnSave": _area_half_on_save_check.button_pressed,
		"concentration": _spell_concentration_check.button_pressed
	}
	var damage_type := _spell_damage_type_option.get_item_text(_spell_damage_type_option.selected)
	if damage_type != DAMAGE_TYPE_NONE:
		action["damageType"] = damage_type
	_send_action(action)

## use_resource spends one charge of a named resource (Rage, Ki Points, etc.)
## shown on the target's own sheet -- fails outright server-side if it
## doesn't have one by that name or none are left. There is deliberately no
## "Restore" control here: unlike every other action on this panel,
## restoreResource() has no use_resource-style counterpart in the DM bridge's
## action vocabulary at all (checked directly in dmBridge.js, not assumed) --
## the 2D app's own Restore button calls the engine function straight from
## its UI code, bypassing the bridge entirely, since restoring mid-scene is a
## DM correction rather than something narration would ever ask for. Same
## amount-omitted-means-1 convention as the 2D app's own Use button.
func _on_use_resource_pressed() -> void:
	if not _require_selected_token():
		return
	var resource_name := _resource_name_input.text.strip_edges()
	if resource_name == "":
		_show_hint("Enter a resource name (e.g. Rage) before using it.")
		return
	_send_action({
		"type": "use_resource",
		"target": _tokens[_selected_token_id].token_name,
		"resource": resource_name
	})

func _on_long_rest_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({"type": "long_rest", "target": _tokens[_selected_token_id].token_name})

func _on_short_rest_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({"type": "short_rest", "target": _tokens[_selected_token_id].token_name})

## rollDeathSave is a no-op server-side (not an error) if the target isn't
## currently making death saves -- safe to always show this button rather
## than gate it on the token's own dying status.
func _on_death_save_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({"type": "roll_death_save", "target": _tokens[_selected_token_id].token_name})

## addExhaustion's `amount` is signed -- positive adds levels, negative
## removes them (both go through the same action, matching the 2D app's own
## +1/-1 buttons over the same field).
func _on_exhaustion_pressed(amount: int) -> void:
	if not _require_selected_token():
		return
	_send_action({
		"type": "add_exhaustion",
		"target": _tokens[_selected_token_id].token_name,
		"amount": amount
	})

## `cost` is omitted -- useLegendaryAction() defaults it to 1 server-side,
## same as the 2D app's own Use button never asks for a cost either.
func _on_legendary_action_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({"type": "use_legendary_action", "target": _tokens[_selected_token_id].token_name})

## Recharge abilities are named per-monster (a hell hound's "Fire Breath",
## etc.) with no fixed list to offer as a dropdown -- free text, same as the
## spell name field above.
func _on_use_recharge_pressed() -> void:
	if not _require_selected_token():
		return
	var ability_name := _recharge_name_input.text.strip_edges()
	if ability_name == "":
		_show_hint("Enter a recharge ability name (e.g. Fire Breath) before using it.")
		return
	_send_action({
		"type": "use_recharge_ability",
		"target": _tokens[_selected_token_id].token_name,
		"ability": ability_name
	})

## trigger_lair_action is the one action on this whole panel that ISN'T
## per-token -- it fires against the whole encounter (RAW: initiative count
## 20, not any one creature's turn), so it deliberately does NOT go through
## _require_selected_token().
func _on_trigger_lair_pressed() -> void:
	var description := _lair_description_input.text.strip_edges()
	if description == "":
		_show_hint("Describe what the lair action does before triggering it.")
		return
	_send_action({"type": "trigger_lair_action", "description": description})

## Shared guard for every "acts on the selected token" HUD control (rolls,
## condition toggles) -- same "show a status hint, don't just silently no-op"
## convention _handle_right_click already uses for the no-attacker-selected
## case.
func _require_selected_token() -> bool:
	if _selected_token_id == "" or not _tokens.has(_selected_token_id):
		_show_hint("Left-click a token first to select it, then use its controls.")
		return false
	return true

## toggleCondition (see engine-server/engine/encounter.js) is a true flip --
## add if absent, remove if present -- matching a toggle button exactly.
## Godot flips the button's own pressed state immediately on click (before
## this handler runs), so if there's no selection to act on, explicitly
## revert it via set_pressed_no_signal() rather than leaving a visual toggle
## that didn't actually do anything until the next poll silently corrects it.
func _on_condition_toggled(pressed: bool, condition: String) -> void:
	if not _require_selected_token():
		_condition_buttons[condition].set_pressed_no_signal(not pressed)
		return
	_send_action({
		"type": "toggle_condition",
		"target": _tokens[_selected_token_id].token_name,
		"condition": condition
	})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_deselect_token()
	elif event is InputEventMouseButton:
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
		# Clicked past the board entirely (e.g. the sky above the horizon) --
		# there was previously no way to deselect a token at all once picked,
		# a real gap (found by the user trying to test the "nothing selected"
		# hint message and discovering they couldn't get back to that state).
		_deselect_token()
		return

	var collider: Node = hit["collider"]
	if collider.is_in_group("tokens"):
		var token: Token = collider.get_meta("token")
		if token.token_id == _selected_token_id:
			_deselect_token() # clicking the already-selected token again toggles it off
		else:
			_select_token(token)
	elif collider.is_in_group("floor") and _selected_token_id != "":
		var cell: Vector2i = _board.world_to_cell(hit["position"])
		_send_move(_selected_token_id, cell.x, cell.y)

func _handle_right_click(screen_pos: Vector2) -> void:
	if _selected_token_id == "" or not _tokens.has(_selected_token_id):
		_show_hint("Left-click a token to select an attacker first, then right-click a target.")
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

## Three ways to reach this: clicking past the board entirely, clicking the
## already-selected token again, or pressing Escape (see _unhandled_input).
## The status label's "Selected: ..." line catches up on the next poll (up to
## poll_interval_seconds later) rather than being force-refreshed here --
## acceptable since that's already how every other state change reaches it.
func _deselect_token() -> void:
	if _tokens.has(_selected_token_id):
		_tokens[_selected_token_id].set_selected(false)
	_selected_token_id = ""

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
		_show_hint("Could not send action to engine-server (error %d)." % error)

func _on_action_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_action_in_flight = false
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200:
		var error_text: String = "unknown error"
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
			error_text = str(parsed["error"])
		_show_hint("Action failed (HTTP %d): %s" % [response_code, error_text])
		return
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("state"):
		_apply_state(parsed["state"])
