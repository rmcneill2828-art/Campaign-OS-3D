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

## Character Creator (ROADMAP.md's "Seven requested features" 2026-09-19 entry, item 1)
## -- duplicated from engine-server/engine/characterCreator.js's own CLASS_LIST, same
## "no shared-module mechanism across these plain scripts" convention ABILITY_KEYS/
## SKILL_LIST above already document. Reuses this file's own ABILITY_KEYS/SKILL_LIST
## constants above for everything else -- characterCreator.js's own copies of those two
## lists happen to be identical to encounter.js's (same names, same order), so no
## separate duplicate is needed for them specifically.
const CHARACTER_CLASS_LIST: Array[String] = [
	"Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk",
	"Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"
]
## Same 4d6-drop-lowest convention ui/app.js's own rollAbilityScore() uses.
const STANDARD_ARRAY: Array[int] = [15, 14, 13, 12, 10, 8]

## AoE template tool (ROADMAP.md's "Seven requested features" 2026-09-19 entry, item 7)
## -- fixed option order, matches how TEMPLATE_SHAPES's own index is used as
## OptionButton.selected below (same "index, not id" convention ROLL_MODE_* already uses).
const TEMPLATE_SHAPES: Array[String] = ["circle", "cone", "line"]


## applyHealing (see engine-server/engine/encounter.js) clamps to the target's
## real maxHp server-side -- this client doesn't need to know that value
## itself to offer a "Full Heal" button, just send an amount large enough
## that the clamp is always what actually limits it, whatever the target's
## real max HP turns out to be.
const FULL_HEAL_AMOUNT := 9999

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
@onready var _open_player_window_button: Button = $HUD/OpenPlayerWindowButton

## Found live: a DM clicked Roll Initiative and saw no confirmation at all --
## the action DID succeed server-side (confirmed by checking /state directly),
## but _status_label only ever shows state.log[0], the single most recent
## entry, easy to miss and trivially pushed out by the very next action or
## poll tick. PlayerView.gd already solved this for the player-facing view
## with a real scrolling combat log; this mirrors that exact pattern
## (newest-first, matching state.log's own storage order) for the DM's own
## view too, rather than patching initiative specifically.
@onready var _combat_log_list: VBoxContainer = $HUD/CombatLogPanel/CombatLogScroll/CombatLogList

## Applies to whichever roll comes next for the selected token -- attack (right-click),
## saving throw, ability check, or a spell's own attack roll -- rather than a separate
## advantage/disadvantage control duplicated in each of those sections. Matches how a real
## table actually talks about it ("this attack has advantage") as one standing declaration,
## not a per-button-press setting; the DM resets it back to Normal themselves once whatever
## granted it stops applying (this client has no way to know that on its own). Deliberately
## NOT wired into cast_area_spell -- area spells resolve as saving throws per target, and
## rollSavingThrow's own advantage/disadvantage support is for a single declared target's
## save, not "everyone in the blast," which castAreaSpell doesn't expose per-target anyway.
@onready var _roll_mode_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/RollModeRow/RollModeOption

@onready var _initiative_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/InitiativeHeaderButton
@onready var _initiative_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/InitiativeBody
@onready var _roll_initiative_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/InitiativeBody/RollInitiativeButton
@onready var _set_initiative_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/InitiativeBody/SetInitiativeRow/SetInitiativeInput
@onready var _set_initiative_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/InitiativeBody/SetInitiativeRow/SetInitiativeButton

@onready var _checks_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksHeaderButton
@onready var _checks_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksBody
@onready var _save_ability_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksBody/SaveRow/SaveAbilityOption
@onready var _roll_save_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksBody/SaveRow/RollSaveButton
@onready var _check_skill_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksBody/CheckRow/CheckSkillOption
@onready var _roll_check_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksBody/CheckRow/RollCheckButton
@onready var _dc_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ChecksBody/DCRow/DCInput

@onready var _conditions_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ConditionsHeaderButton
@onready var _conditions_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ConditionsBody
@onready var _conditions_grid: GridContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ConditionsBody/ConditionsGrid

@onready var _spell_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellHeaderButton
@onready var _spell_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody
@onready var _spell_name_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/SpellNameRow/SpellNameInput
@onready var _spell_level_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/SpellLevelRow/SpellLevelInput
@onready var _spell_target_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/SpellTargetRow/SpellTargetOption
@onready var _spell_damage_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/SpellDamageRow/SpellDamageInput
@onready var _spell_damage_type_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/SpellDamageRow/SpellDamageTypeOption
@onready var _spell_concentration_check: CheckBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/SpellConcentrationCheck
@onready var _cast_spell_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/CastSpellButton
@onready var _area_targets_list: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/AreaSpellTargetsList
@onready var _area_save_ability_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/AreaSaveRow/AreaSaveAbilityOption
@onready var _area_save_dc_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/AreaSaveRow/AreaSaveDCInput
@onready var _area_half_on_save_check: CheckBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/AreaSaveRow/AreaHalfOnSaveCheck
@onready var _cast_area_spell_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/SpellBody/CastAreaSpellButton

@onready var _resource_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceHeaderButton
@onready var _resource_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody
@onready var _heal_amount_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/HealRow/HealAmountInput
@onready var _heal_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/HealRow/HealButton
@onready var _full_heal_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/HealRow/FullHealButton
@onready var _resource_name_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/ResourceRow/ResourceNameInput
@onready var _use_resource_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/ResourceRow/UseResourceButton
@onready var _long_rest_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/RestRow/LongRestButton
@onready var _short_rest_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/ResourceBody/RestRow/ShortRestButton

@onready var _other_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherHeaderButton
@onready var _other_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody
## apply_damage/drop_concentration/spend_hit_die/remove_token were all
## already reachable through the DM Assistant's Claude round-trip (a real
## API call, not instant) but had no direct button -- see the feature
## parity audit in ROADMAP.md.
@onready var _damage_amount_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/DamageRow/DamageAmountInput
@onready var _damage_type_option: OptionButton = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/DamageRow/DamageTypeOption
@onready var _apply_damage_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/DamageRow/ApplyDamageButton
@onready var _drop_concentration_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/DropConcentrationButton
@onready var _hit_dice_type_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/HitDiceRow/HitDiceTypeInput
@onready var _hit_dice_count_input: SpinBox = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/HitDiceRow/HitDiceCountInput
@onready var _spend_hit_dice_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/HitDiceRow/SpendHitDiceButton
@onready var _remove_token_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/RemoveTokenButton
@onready var _death_save_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/DeathSaveButton
@onready var _exhaustion_minus_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/ExhaustionRow/ExhaustionMinusButton
@onready var _exhaustion_plus_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/ExhaustionRow/ExhaustionPlusButton
@onready var _legendary_action_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/LegendaryActionButton
@onready var _recharge_name_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/RechargeRow/RechargeNameInput
@onready var _use_recharge_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/RechargeRow/UseRechargeButton
@onready var _lair_description_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/LairRow/LairDescriptionInput
@onready var _trigger_lair_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/OtherBody/LairRow/TriggerLairButton

@onready var _dm_assistant_header: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DmAssistantHeaderButton
@onready var _dm_assistant_body: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DmAssistantBody
@onready var _dm_command_input: LineEdit = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DmAssistantBody/DmCommandInput
@onready var _send_dm_command_button: Button = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DmAssistantBody/SendDmCommandButton
@onready var _dm_response_label: Label = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList/DmAssistantBody/DmResponseLabel
@onready var _dm_command_request: HTTPRequest = $DmCommandRequest

@onready var _token_actions_list: VBoxContainer = $HUD/TokenActionsPanel/TokenActionsScroll/TokenActionsList

var _condition_buttons := {} # condition name (String) -> Button (toggle_mode)
var _area_target_checkboxes := {} # token name (String) -> CheckBox
var _last_target_names: Array[String] = [] # last set the spell-target UI was built from -- see _sync_spell_targets()

## AoE template tool -- shape math lives in AoeTemplate.gd (a port of encounter.js's own
## point-in-shape functions); these just track placement state, same "local UI concern,
## never persisted to server state" convention ui/app.js's own template*/ vars document
## for themselves. Built entirely in code (_build_template_controls(), called from
## _ready()) rather than hand-edited into Main.tscn, same convention the Conditions
## toggle-button grid already uses just below.
var _template_active := false
var _template_shape := "circle" # one of TEMPLATE_SHAPES
var _template_origin := Vector2.ZERO # cell units -- see AoeTemplate.gd's class doc comment
var _template_placed := false # false until a click/drag has actually set an origin
var _template_angle_rad := 0.0 # cone/line only
var _template_dragging := false
var _template_overlay: MeshInstance3D
var _template_shape_option: OptionButton
var _template_length_input: SpinBox
var _template_width_row: HBoxContainer
var _template_width_input: SpinBox
var _template_info_label: Label

## Character Creator -- POSTs to engine-server's own /create-character (see
## server.js's own doc comment on that endpoint), which runs the exact same
## engine/characterCreator.js compute+markdown logic the 2D app runs in-browser, then
## writes into dm-bridge/'s own SEPARATE create-character-request.json/
## create-character-response.json mailbox (distinct from /dm-command's request.json/
## response.json). Built entirely in code, same convention as the AoE Template
## controls above. A SEPARATE in-flight flag from _dm_command_in_flight/
## _action_in_flight -- this can take a few seconds (waiting on dm-bridge/watch.js to
## write the file), but there's no reason it should block ordinary combat actions or
## vice versa.
var _cc_in_flight := false
var _cc_name: LineEdit
var _cc_race: LineEdit
var _cc_class: OptionButton
var _cc_level: SpinBox
var _cc_background: LineEdit
var _cc_alignment: LineEdit
var _cc_ability_inputs := {} # ability key (String) -> SpinBox
var _cc_ac: LineEdit
var _cc_speed: SpinBox
var _cc_skill_checkboxes := {} # skill name (String) -> CheckBox
var _cc_languages: LineEdit
var _cc_tools: LineEdit
var _cc_features: TextEdit
var _cc_is_caster: CheckBox
var _cc_spell_ability: OptionButton
var _cc_spells_known: TextEdit
var _cc_weapon_name: LineEdit
var _cc_weapon_dice: LineEdit
var _cc_weapon_ability: OptionButton
var _cc_weapon_damage_type: OptionButton
var _cc_equipment: TextEdit
var _cc_traits: LineEdit
var _cc_ideals: LineEdit
var _cc_bonds: LineEdit
var _cc_flaws: LineEdit
var _cc_backstory: TextEdit
var _cc_status_label: Label
var _cc_create_button: Button
var _cc_request: HTTPRequest

var _tokens := {} # token id (String) -> Token node
var _selected_token_id := ""
var _last_centered_map_name := "" # not just a one-time flag -- see _apply_state()'s own use, below
var _action_in_flight := false

var _right_press_pos := Vector2.ZERO
var _right_press_active := false

## Phase 7 -- a SEPARATE in-flight flag from _action_in_flight: a DM-command
## round trip can take up to ~2 minutes (waiting on a real Claude call via
## dm-bridge/watch.js), and there's no reason ordinary button-driven actions
## (attack, cast a spell, next turn) should be blocked from working for that
## whole time just because a narration command is also pending.
var _dm_command_in_flight := false

## Phase 6 -- the "second monitor/TV" window. A real separate OS window (not
## embedded in this one), same technique the 2D app's own "Open Player
## Window" button uses in spirit (a second, independent view onto the same
## live game) -- Godot's default project setting already has subwindows NOT
## embedded, so a plain Window node showing a scene inside it IS a real,
## separately-draggable OS window. Tracked so a second click brings the
## existing window to front instead of spawning a duplicate.
var _player_window: Window

func _ready() -> void:
	_poll_timer.wait_time = poll_interval_seconds
	_poll_timer.timeout.connect(_poll_state)
	_state_request.request_completed.connect(_on_state_response)
	_action_request.request_completed.connect(_on_action_response)
	_next_turn_button.pressed.connect(_on_next_turn_pressed)
	_open_player_window_button.pressed.connect(_on_open_player_window_pressed)

	for ability in ABILITY_KEYS:
		_save_ability_option.add_item(ability)
	for ability in ABILITY_KEYS:
		_check_skill_option.add_item(ability)
	for skill in SKILL_LIST:
		_check_skill_option.add_item(skill)
	_roll_save_button.pressed.connect(_on_roll_save_pressed)
	_roll_check_button.pressed.connect(_on_roll_check_pressed)
	_roll_initiative_button.pressed.connect(_on_roll_initiative_pressed)
	_set_initiative_button.pressed.connect(_on_set_initiative_pressed)
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
	for damage_type in DAMAGE_TYPE_LIST:
		_damage_type_option.add_item(damage_type)
	_spell_target_option.add_item(SPELL_TARGET_NONE)
	for ability in ABILITY_KEYS:
		_area_save_ability_option.add_item(ability)
	_cast_spell_button.pressed.connect(_on_cast_spell_pressed)
	_cast_area_spell_button.pressed.connect(_on_cast_area_spell_pressed)
	_build_template_controls()
	_build_character_creator_controls()

	_heal_button.pressed.connect(_on_heal_pressed)
	_full_heal_button.pressed.connect(_on_full_heal_pressed)
	_use_resource_button.pressed.connect(_on_use_resource_pressed)
	_long_rest_button.pressed.connect(_on_long_rest_pressed)
	_short_rest_button.pressed.connect(_on_short_rest_pressed)
	_apply_damage_button.pressed.connect(_on_apply_damage_pressed)
	_drop_concentration_button.pressed.connect(_on_drop_concentration_pressed)
	_spend_hit_dice_button.pressed.connect(_on_spend_hit_dice_pressed)
	_remove_token_button.pressed.connect(_on_remove_token_pressed)
	_death_save_button.pressed.connect(_on_death_save_pressed)
	_exhaustion_plus_button.pressed.connect(_on_exhaustion_pressed.bind(1))
	_exhaustion_minus_button.pressed.connect(_on_exhaustion_pressed.bind(-1))
	_legendary_action_button.pressed.connect(_on_legendary_action_pressed)
	_use_recharge_button.pressed.connect(_on_use_recharge_pressed)
	_trigger_lair_button.pressed.connect(_on_trigger_lair_pressed)
	_send_dm_command_button.pressed.connect(_on_send_dm_command_pressed)
	_dm_command_request.request_completed.connect(_on_dm_command_response)

	# Collapsible sections -- the panel grew large enough across Phase 3 that
	# showing everything open at once ran the whole thing off-screen (reported
	# directly, not guessed at). Each header toggle just shows/hides its own
	# body; all start collapsed so the panel opens compact.
	_wire_collapsible_section(_initiative_header, _initiative_body, "Initiative")
	_wire_collapsible_section(_checks_header, _checks_body, "Saving Throws / Checks")
	_wire_collapsible_section(_conditions_header, _conditions_body, "Conditions")
	_wire_collapsible_section(_spell_header, _spell_body, "Spellcasting")
	_wire_collapsible_section(_resource_header, _resource_body, "Resources & Rests")
	_wire_collapsible_section(_other_header, _other_body, "Other Actions")
	_wire_collapsible_section(_dm_assistant_header, _dm_assistant_body, "DM Assistant (Claude)")

	_poll_state()

## `label` is the plain section name (no arrow) -- the header's displayed
## text is rebuilt with a ▸/▾ prefix reflecting the body's current
## visibility, so the arrow can never drift out of sync with what's actually
## shown the way a hand-maintained separate label could.
func _wire_collapsible_section(header: Button, body: Control, label: String) -> void:
	var set_text := func(expanded: bool):
		header.text = ("▾ " if expanded else "▸ ") + label
	header.toggled.connect(func(pressed: bool):
		body.visible = pressed
		set_text.call(pressed)
	)
	set_text.call(header.button_pressed)

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
	_board.build(columns, rows, feet_per_square, MapScenes.resolve(map_name))

	# Re-centers whenever the ACTIVE map actually changes, not just once ever --
	# the original one-shot flag correctly centered on whichever map happened
	# to be active when the client first connected, then never again, so
	# switching to a second map with a different board size/position (Phase 4's
	# "Entrance Hall", much smaller than "Prototype Chamber") left the camera
	# pointed at the OLD map's board_center() forever after, which read as a
	# baffling "everything is floating/misaligned" visual (reported live as
	# "floor level" wrong, though the actual saved scene geometry was already
	# correct -- confirmed by direct measurement before this fix) rather than
	# the camera-framing bug it actually was. A named map switch is the right
	# trigger to re-center on (matches how a real DM's view would jump to the
	# new scene), not e.g. every state poll, which would fight the player's
	# own manual pan/orbit/zoom on the map they're currently looking at.
	if map_name != _last_centered_map_name:
		_camera_rig.center_on(_board.board_center())
		_last_centered_map_name = map_name

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
	_update_template_overlay() # keeps the covered-token set live even when a token moves via the DM Assistant, not just a local drag
	_update_status_label(state, map_name, tokens_on_map)
	_update_combat_log(state.get("log", []))

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

## Mirrors PlayerView.gd's own _update_combat_log() exactly -- see this
## project's own note on _combat_log_list above for why the DM's view needed
## this too, not just the player-facing one. Newest-first, matching
## state.log's own storage order (see engine-server/engine/dmBridge.js's
## appendLog), so the log reads top-to-bottom the same direction a DM's eye
## naturally lands after an action.
func _update_combat_log(log: Array) -> void:
	for child in _combat_log_list.get_children():
		child.queue_free()
	if log.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No actions yet."
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_combat_log_list.add_child(empty_label)
		return
	for entry in log:
		var label := Label.new()
		label.text = str(entry)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		_combat_log_list.add_child(label)

func _on_next_turn_pressed() -> void:
	_send_action({"type": "next_turn"})

## Opens (or re-focuses) the read-only Phase 6 player-facing view as a real
## second OS window, draggable to a second monitor/TV -- mirrors the 2D app's
## own "Open Player Window" button. Deliberately just a window spawn: this
## script never talks to that window directly after opening it (no shared
## state push) -- PlayerView.gd polls engine-server on its own, completely
## independently, same reasoning `dm-bridge/watch.js`'s own poll loop already
## established for this project: a second independent poller is simpler and
## more robust than this window pushing updates into it.
func _on_open_player_window_pressed() -> void:
	if _player_window and is_instance_valid(_player_window):
		_player_window.grab_focus()
		return
	if not ResourceLoader.exists("res://scenes/PlayerView.tscn"):
		_show_hint("Player view scene not found (res://scenes/PlayerView.tscn missing).")
		return
	var player_view_scene := load("res://scenes/PlayerView.tscn") as PackedScene
	_player_window = Window.new()
	_player_window.title = "Campaign OS 3D -- Player View"
	_player_window.size = Vector2i(1280, 800)
	_player_window.close_requested.connect(func():
		_player_window.queue_free()
		_player_window = null
	)
	_player_window.add_child(player_view_scene.instantiate())
	get_tree().root.add_child(_player_window)
	_player_window.show()
	_player_window.grab_focus()

## rollInitiative (see engine-server/engine/encounter.js) rolls 1d20 + the
## target's real DEX modifier (RAW) and sets its initiative directly --
## no Roll mode support here (advantage/disadvantage on an initiative roll
## isn't a thing outside a specific feat this engine doesn't model, unlike
## attacks/saves/checks/spells).
func _on_roll_initiative_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({
		"type": "roll_initiative",
		"target": _tokens[_selected_token_id].token_name
	})

## set_initiative -- the 2D app's own equivalent is a plain number field
## on the token sheet (no roll, no log message); this mirrors that exactly
## for a player who rolls their own physical d20 and just reports the
## total, or a DM correcting/tie-breaking an already-rolled value.
func _on_set_initiative_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({
		"type": "set_initiative",
		"target": _tokens[_selected_token_id].token_name,
		"value": int(_set_initiative_input.value)
	})

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
	_send_action(_apply_roll_mode({
		"type": "saving_throw",
		"target": _tokens[_selected_token_id].token_name,
		"ability": ability,
		"dc": int(_dc_input.value)
	}))

## ability_check's `skill` accepts either a bare ability key or a named skill
## interchangeably (rollAbilityCheck resolves either) -- the same one
## dropdown lists both rather than needing two separate controls.
func _on_roll_check_pressed() -> void:
	if not _require_selected_token():
		return
	var skill: String = _check_skill_option.get_item_text(_check_skill_option.selected)
	_send_action(_apply_roll_mode({
		"type": "ability_check",
		"target": _tokens[_selected_token_id].token_name,
		"skill": skill,
		"dc": int(_dc_input.value)
	}))

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
	_send_action(_apply_roll_mode(action))

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

## Builds the AoE Template controls entirely in code -- same convention the Conditions
## toggle-button grid above already uses -- rather than hand-editing Main.tscn's XML.
## Inserted into the existing Spell section right above the Area Spell Targets list this
## tool feeds (not appended after Cast Area Spell), so the panel reads top-to-bottom as
## "aim, then see targets, then cast."
func _build_template_controls() -> void:
	var shape_row := HBoxContainer.new()
	var shape_label := Label.new()
	shape_label.text = "AoE Template:"
	shape_row.add_child(shape_label)
	_template_shape_option = OptionButton.new()
	for shape_name in TEMPLATE_SHAPES:
		_template_shape_option.add_item(shape_name.capitalize())
	_template_shape_option.item_selected.connect(_on_template_shape_selected)
	shape_row.add_child(_template_shape_option)
	_template_toggle_button_setup(shape_row)

	var size_row := HBoxContainer.new()
	var length_label := Label.new()
	length_label.text = "Size (ft):"
	size_row.add_child(length_label)
	_template_length_input = SpinBox.new()
	_template_length_input.min_value = 5
	_template_length_input.max_value = 300
	_template_length_input.step = 5
	_template_length_input.value = 20
	_template_length_input.value_changed.connect(func(_v): _update_template_overlay())
	size_row.add_child(_template_length_input)

	_template_width_row = HBoxContainer.new()
	var width_label := Label.new()
	width_label.text = "Width (ft):"
	_template_width_row.add_child(width_label)
	_template_width_input = SpinBox.new()
	_template_width_input.min_value = 5
	_template_width_input.max_value = 60
	_template_width_input.step = 5
	_template_width_input.value = 5
	_template_width_input.value_changed.connect(func(_v): _update_template_overlay())
	_template_width_row.add_child(_template_width_input)
	_template_width_row.visible = false # circle/cone don't take a separate width -- see AoeTemplate.gd's shape_cells()

	_template_info_label = Label.new()
	_template_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_template_info_label.add_theme_font_size_override("font_size", 13)

	_spell_body.add_child(shape_row)
	_spell_body.add_child(size_row)
	_spell_body.add_child(_template_width_row)
	_spell_body.add_child(_template_info_label)
	var insert_at := _area_targets_list.get_index()
	_spell_body.move_child(shape_row, insert_at)
	_spell_body.move_child(size_row, insert_at + 1)
	_spell_body.move_child(_template_width_row, insert_at + 2)
	_spell_body.move_child(_template_info_label, insert_at + 3)

	_update_template_overlay() # sets the initial hint text

func _template_toggle_button_setup(parent: HBoxContainer) -> void:
	var button := Button.new()
	button.text = "Draw Template"
	button.toggle_mode = true
	button.toggled.connect(_on_template_toggle.bind(button))
	parent.add_child(button)

func _on_template_shape_selected(index: int) -> void:
	_template_shape = TEMPLATE_SHAPES[index]
	_template_width_row.visible = _template_shape == "line"
	_template_placed = false # shape changed -- start fresh rather than reinterpreting stale placement
	_update_template_overlay()

func _on_template_toggle(pressed: bool, button: Button) -> void:
	_template_active = pressed
	button.text = "Template On" if pressed else "Draw Template"
	if not pressed:
		_template_placed = false
		_template_dragging = false
	_update_template_overlay()

## Circle is placed with a plain click (matching the 2D app's own precedent); Cone/Line
## need a click-DRAG instead, since a direction has to come from somewhere -- this just
## sets the origin/apex and starts the drag, _handle_template_drag (mouse motion, while
## _template_dragging) continuously re-aims it, and a plain mouseup (see
## _unhandled_input) just ends the drag -- the placement itself already happened live,
## there's nothing left to commit.
func _handle_template_left_press(screen_pos: Vector2) -> void:
	var cell = _template_cell_units_from_screen(screen_pos)
	if cell == null:
		return
	_template_origin = cell
	_template_placed = true
	if _template_shape != "circle":
		_template_dragging = true
	_update_template_overlay()

func _handle_template_drag(screen_pos: Vector2) -> void:
	var cell = _template_cell_units_from_screen(screen_pos)
	if cell == null:
		return
	var delta: Vector2 = cell - _template_origin
	if delta.length_squared() > 0.0001: # ignore jitter right at mousedown, before a real direction exists
		_template_angle_rad = atan2(delta.y, delta.x)
	_update_template_overlay()

## Raycasts the same way every click-to-move already does, then converts straight to
## AoeTemplate's own cell-unit space -- a world position divided by cell_size IS a
## cell-unit coordinate already (see AoeTemplate.gd's class doc comment), continuous
## rather than snapped to a whole grid cell, so this reads real sub-cell placement/
## angles directly from the 3D scene rather than leaning on the 2D app's own "screen
## pixels approximate real angles" assumption. Accepts a hit against a token just as
## happily as the floor -- both sit at board height, and only the hit's x/z (not y)
## is ever used here.
func _template_cell_units_from_screen(screen_pos: Vector2) -> Variant:
	var hit := _raycast_from_screen(screen_pos)
	if hit.is_empty():
		return null
	var world_pos: Vector3 = hit["position"]
	return Vector2(world_pos.x, world_pos.z) / _board.cell_size

## Rebuilds the 3D shape overlay, the info label, and the Area Spell Targets checkboxes
## from the current template placement -- called on every relevant change (toggle,
## shape switch, size input, drag, and every state poll so a token moving elsewhere --
## e.g. via the DM Assistant -- keeps the covered set live too). Cheap enough to just
## rebuild from scratch every time, same convention GridManager._build_grid_lines()/
## PlayerView._rebuild_fog() already use. Mirrors ui/app.js's own
## renderTemplateOverlay(), translated from an SVG overlay + floating label to a real
## 3D mesh + an in-panel label (no natural place to billboard 3D text at an arbitrary
## polygon centroid the way the 2D app anchors its label there).
func _update_template_overlay() -> void:
	if _template_overlay:
		_template_overlay.queue_free()
		_template_overlay = null

	if not _template_active or not _template_placed:
		if _template_info_label:
			_template_info_label.text = "Toggle \"Draw Template\", then click (Circle) or click-drag (Cone/Line) on the board."
		return

	var length_cells: float = _template_length_input.value / _board.feet_per_square
	var width_cells: float = _template_width_input.value / _board.feet_per_square
	var shape := AoeTemplate.shape_cells(_template_shape, _template_origin, _template_angle_rad, length_cells, width_cells)

	var tokens: Array = []
	for token in _tokens.values():
		tokens.append({"name": token.token_name, "x": token.grid_x, "y": token.grid_y})
	var covered := AoeTemplate.covered_token_names(tokens, _template_shape, _template_origin, _template_angle_rad, length_cells, width_cells)

	_template_overlay = _build_template_mesh(shape)
	add_child(_template_overlay)

	var size_label := ("%d ft radius" % int(_template_length_input.value)) if _template_shape == "circle" \
		else ("%d ft %s" % [int(_template_length_input.value), _template_shape])
	# String.join() wants a PackedStringArray, not a generic Array -- same explicit
	# conversion Token.gd's own conditions-line building already uses, for the same reason.
	_template_info_label.text = ("%s -- %s" % [size_label, ", ".join(PackedStringArray(covered))]) if not covered.is_empty() else size_label

	# Auto-check exactly the covered set (both directions -- uncheck a name that just
	# left the shape, not only check ones that entered it) rather than only ever adding:
	# a DM re-aiming a cone should see the target list track the shape live, the whole
	# point of this tool over the previous "check each box by hand" requirement. Toggling
	# "Draw Template" off stops this loop from running at all (see _on_template_toggle),
	# freezing whatever's checked for final manual adjustment before Cast Area Spell.
	for name in _area_target_checkboxes:
		_area_target_checkboxes[name].button_pressed = covered.has(name)

## Builds the translucent 3D shape mesh itself from AoeTemplate.shape_cells()'s output --
## a triangle fan for a circle, a plain fan triangulation for a cone's triangle or a
## line's quad (valid for both -- a triangle needs no further split, and a convex quad
## fans cleanly from any one corner).
func _build_template_mesh(shape: Dictionary) -> MeshInstance3D:
	const OVERLAY_HEIGHT := 0.03 # just above GridManager's own grid-line overlay (0.01) so this draws on top, not z-fighting with it
	const SEGMENTS := 32
	var cell_size: float = _board.cell_size
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	if shape["kind"] == "circle":
		var center: Vector2 = shape["center"]
		var radius_world: float = float(shape["radius_cells"]) * cell_size
		var center_world := Vector3(center.x * cell_size, OVERLAY_HEIGHT, center.y * cell_size)
		for i in range(SEGMENTS):
			var a0 := (float(i) / SEGMENTS) * TAU
			var a1 := (float(i + 1) / SEGMENTS) * TAU
			var p0 := center_world + Vector3(cos(a0) * radius_world, 0.0, sin(a0) * radius_world)
			var p1 := center_world + Vector3(cos(a1) * radius_world, 0.0, sin(a1) * radius_world)
			surface.add_vertex(center_world)
			surface.add_vertex(p0)
			surface.add_vertex(p1)
	else:
		var points: Array = shape["points"]
		var world_points: Array[Vector3] = []
		for point in points:
			world_points.append(Vector3(point.x * cell_size, OVERLAY_HEIGHT, point.y * cell_size))
		for i in range(1, world_points.size() - 1):
			surface.add_vertex(world_points[0])
			surface.add_vertex(world_points[i])
			surface.add_vertex(world_points[i + 1])

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.45, 0.1, 0.35) # translucent orange -- reads as "template," distinct from the grid-line white and fog's black
	mesh_instance.material_override = material
	return mesh_instance

## --- Character Creator: small row-builder helpers, reducing the boilerplate every ---
## field below would otherwise repeat (same reasoning _build_template_controls() above
## already applies at a smaller scale).

func _cc_row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	parent.add_child(row)
	return row

func _cc_line_edit_row(parent: Control, label_text: String) -> LineEdit:
	var row := _cc_row(parent, label_text)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit

func _cc_spinbox_row(parent: Control, label_text: String, min_v: float, max_v: float, default_v: float) -> SpinBox:
	var row := _cc_row(parent, label_text)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = default_v
	row.add_child(spin)
	return spin

func _cc_option_row(parent: Control, label_text: String, items: Array) -> OptionButton:
	var row := _cc_row(parent, label_text)
	var option := OptionButton.new()
	for item in items:
		option.add_item(str(item))
	row.add_child(option)
	return option

func _cc_text_block(parent: Control, label_text: String) -> TextEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = 50
	parent.add_child(edit)
	return edit

## Builds the whole Character Creator panel in code (same convention as the AoE
## Template controls above and the Conditions grid further up) and adds it as a new
## collapsible section at the end of the Token Actions accordion -- not gated on a
## selected token (matches "DM Assistant"/trigger_lair_action's own precedent; a new
## character isn't acting through an existing one). Mirrors ui/app.js's own Create
## Character form field-for-field (see its own characterDraftFromForm()) so the draft
## _character_draft_from_form() below builds matches exactly what
## characterCreator.js's validateDraft()/computeCharacter() already expect -- see
## engine-server/server.js's own POST /create-character doc comment for the rest of
## this round trip.
func _build_character_creator_controls() -> void:
	var header := Button.new()
	header.toggle_mode = true
	var body := VBoxContainer.new()
	body.visible = false
	_token_actions_list.add_child(header)
	_token_actions_list.add_child(body)
	_wire_collapsible_section(header, body, "Create Character")

	_cc_name = _cc_line_edit_row(body, "Name:")
	_cc_race = _cc_line_edit_row(body, "Race:")
	_cc_class = _cc_option_row(body, "Class:", CHARACTER_CLASS_LIST)
	_cc_level = _cc_spinbox_row(body, "Level:", 1, 20, 1)
	_cc_background = _cc_line_edit_row(body, "Background:")
	_cc_alignment = _cc_line_edit_row(body, "Alignment:")

	var scores_label := Label.new()
	scores_label.text = "Ability Scores:"
	body.add_child(scores_label)
	var scores_row := HBoxContainer.new()
	for ability in ABILITY_KEYS:
		var column := VBoxContainer.new()
		var ability_label := Label.new()
		ability_label.text = ability
		column.add_child(ability_label)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = 30
		spin.value = 10
		column.add_child(spin)
		scores_row.add_child(column)
		_cc_ability_inputs[ability] = spin
	body.add_child(scores_row)

	var scores_buttons_row := HBoxContainer.new()
	var standard_array_button := Button.new()
	standard_array_button.text = "Standard Array"
	standard_array_button.pressed.connect(_on_cc_standard_array_pressed)
	scores_buttons_row.add_child(standard_array_button)
	var roll_scores_button := Button.new()
	roll_scores_button.text = "Roll Scores (4d6 drop lowest)"
	roll_scores_button.pressed.connect(_on_cc_roll_scores_pressed)
	scores_buttons_row.add_child(roll_scores_button)
	body.add_child(scores_buttons_row)

	_cc_ac = _cc_line_edit_row(body, "AC (blank = auto):")
	_cc_speed = _cc_spinbox_row(body, "Speed (ft):", 0, 120, 30)

	var skills_label := Label.new()
	skills_label.text = "Proficient Skills:"
	body.add_child(skills_label)
	var skills_grid := GridContainer.new()
	skills_grid.columns = 2
	for skill in SKILL_LIST:
		var checkbox := CheckBox.new()
		checkbox.text = skill
		skills_grid.add_child(checkbox)
		_cc_skill_checkboxes[skill] = checkbox
	body.add_child(skills_grid)

	_cc_languages = _cc_line_edit_row(body, "Languages:")
	_cc_tools = _cc_line_edit_row(body, "Tools/Weapons/Armor:")
	_cc_features = _cc_text_block(body, "Features & Traits (one per line):")

	_cc_is_caster = CheckBox.new()
	_cc_is_caster.text = "Spellcaster"
	body.add_child(_cc_is_caster)
	_cc_spell_ability = _cc_option_row(body, "Spellcasting Ability:", ABILITY_KEYS)
	_cc_spells_known = _cc_text_block(body, "Spells Known/Prepared:")

	var attack_label := Label.new()
	attack_label.text = "Attack:"
	body.add_child(attack_label)
	_cc_weapon_name = _cc_line_edit_row(body, "Weapon Name:")
	_cc_weapon_dice = _cc_line_edit_row(body, "Damage Dice (e.g. 1d8):")
	_cc_weapon_ability = _cc_option_row(body, "Attack Ability:", ["STR", "DEX"])
	_cc_weapon_damage_type = _cc_option_row(body, "Damage Type:", DAMAGE_TYPE_LIST.filter(func(t): return t != DAMAGE_TYPE_NONE))

	_cc_equipment = _cc_text_block(body, "Equipment (one per line):")

	var personality_label := Label.new()
	personality_label.text = "Personality:"
	body.add_child(personality_label)
	_cc_traits = _cc_line_edit_row(body, "Traits:")
	_cc_ideals = _cc_line_edit_row(body, "Ideals:")
	_cc_bonds = _cc_line_edit_row(body, "Bonds:")
	_cc_flaws = _cc_line_edit_row(body, "Flaws:")

	_cc_backstory = _cc_text_block(body, "Backstory:")

	_cc_create_button = Button.new()
	_cc_create_button.text = "Create Character"
	_cc_create_button.pressed.connect(_on_create_character_pressed)
	body.add_child(_cc_create_button)

	_cc_status_label = Label.new()
	_cc_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_cc_status_label)

	_cc_request = HTTPRequest.new()
	add_child(_cc_request)
	_cc_request.request_completed.connect(_on_create_character_response)

func _on_cc_standard_array_pressed() -> void:
	for i in range(ABILITY_KEYS.size()):
		_cc_ability_inputs[ABILITY_KEYS[i]].value = STANDARD_ARRAY[i]

## Matches ui/app.js's own rollAbilityScore() exactly: roll four d6, drop the lowest.
func _roll_ability_score() -> int:
	var rolls: Array[int] = []
	for i in range(4):
		rolls.append(1 + randi() % 6)
	rolls.sort()
	return rolls[1] + rolls[2] + rolls[3]

func _on_cc_roll_scores_pressed() -> void:
	for ability in ABILITY_KEYS:
		_cc_ability_inputs[ability].value = _roll_ability_score()

## Mirrors ui/app.js's own characterDraftFromForm() field-for-field -- the exact draft
## shape engine-server's POST /create-character (CharacterCreator.validateDraft()/
## computeCharacter()) expects. Pure/no side effects beyond reading control values, so
## this is unit-testable without a live server (see godot/tools/test_character_creator.gd).
func _character_draft_from_form() -> Dictionary:
	var proficient_skills: Array[String] = []
	for skill in _cc_skill_checkboxes:
		if _cc_skill_checkboxes[skill].button_pressed:
			proficient_skills.append(skill)

	var draft := {
		"name": _cc_name.text,
		"race": _cc_race.text,
		"className": CHARACTER_CLASS_LIST[_cc_class.selected],
		"level": int(_cc_level.value),
		"background": _cc_background.text,
		"alignment": _cc_alignment.text,
		"abilityScores": {},
		"ac": _cc_ac.text,
		"speed": int(_cc_speed.value),
		"proficientSkills": proficient_skills,
		"languages": _cc_languages.text,
		"toolsWeaponsArmor": _cc_tools.text,
		"features": _cc_features.text,
		"equipment": _cc_equipment.text,
		"personality": {
			"traits": _cc_traits.text,
			"ideals": _cc_ideals.text,
			"bonds": _cc_bonds.text,
			"flaws": _cc_flaws.text
		},
		"backstory": _cc_backstory.text,
		"attack": {
			"weaponName": _cc_weapon_name.text,
			"diceSize": _cc_weapon_dice.text,
			"ability": _cc_weapon_ability.get_item_text(_cc_weapon_ability.selected),
			"damageType": _cc_weapon_damage_type.get_item_text(_cc_weapon_damage_type.selected)
		}
	}
	for ability in ABILITY_KEYS:
		draft["abilityScores"][ability] = int(_cc_ability_inputs[ability].value)
	if _cc_is_caster.button_pressed:
		draft["spellcasting"] = {
			"isCaster": true,
			"ability": ABILITY_KEYS[_cc_spell_ability.selected],
			"spellsKnown": _cc_spells_known.text
		}
	return draft

func _on_create_character_pressed() -> void:
	if _cc_in_flight:
		return
	if _cc_name.text.strip_edges() == "":
		_cc_status_label.text = "Enter a name before creating the character."
		return

	var draft := _character_draft_from_form()
	_cc_in_flight = true
	_cc_create_button.disabled = true
	_cc_status_label.text = "Writing the character sheet (needs \"node dm-bridge/watch.js\" running, with DND_REPO_PATH set on it)..."

	var body := JSON.stringify(draft)
	var error := _cc_request.request(
		server_base_url + "/create-character",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_cc_in_flight = false
		_cc_create_button.disabled = false
		_cc_status_label.text = "Could not send to engine-server (error %d)." % error

func _on_create_character_response(_result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
	_cc_in_flight = false
	_cc_create_button.disabled = false
	var parsed = JSON.parse_string(response_body.get_string_from_utf8())

	# validateDraft() failures land here as a real 400, distinct from a 500/504
	# transport-level problem below -- surfaces the actual reasons (e.g. "Name is
	# required.") rather than a generic error string.
	if response_code == 400 and typeof(parsed) == TYPE_DICTIONARY and parsed.has("errors"):
		_cc_status_label.text = ", ".join(PackedStringArray(parsed["errors"]))
		return
	if response_code != 200:
		var error_text: String = "unknown error"
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
			error_text = str(parsed["error"])
		_cc_status_label.text = "Create Character error (HTTP %d): %s" % [response_code, error_text]
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_cc_status_label.text = "engine-server sent a response this client doesn't understand."
		return

	# {ok, message, fileName, character} -- ok can legitimately be false (a filename
	# collision, DND_REPO_PATH not set on the watcher) without this being an HTTP-level
	# error; see server.js's own doc comment on this endpoint for why.
	var message: String = str(parsed.get("message", ""))
	_cc_status_label.text = message if message != "" else ("Something went wrong." if not parsed.get("ok", false) else "Done.")

## apply_healing (see engine-server/engine/dmBridge.js) adds a flat amount,
## clamped to the target's own maxHp server-side, and clears dying/dead if it
## brings the target back above 0 HP -- so this doubles as the "revive/
## stabilize" control too, not just topping up HP on an already-conscious
## target.
func _on_heal_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({
		"type": "apply_healing",
		"target": _tokens[_selected_token_id].token_name,
		"amount": int(_heal_amount_input.value)
	})

## Same action as above with a deliberately oversized amount -- the server's
## own clamp to maxHp is what actually limits it, so this client never needs
## to know the target's real max HP to offer a one-click "top them off"
## button.
func _on_full_heal_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({
		"type": "apply_healing",
		"target": _tokens[_selected_token_id].token_name,
		"amount": FULL_HEAL_AMOUNT
	})

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

## applyDamage takes flat damage with no attack roll -- a trap, a fall, a
## DM ruling -- distinct from attack()'s own roll-to-hit-then-damage flow.
## damageType is only sent when a real type is picked (matching cast_spell's
## own DAMAGE_TYPE_NONE convention) since resistances/vulnerabilities only
## apply when a type is actually known.
func _on_apply_damage_pressed() -> void:
	if not _require_selected_token():
		return
	var action := {
		"type": "apply_damage",
		"target": _tokens[_selected_token_id].token_name,
		"amount": int(_damage_amount_input.value)
	}
	var damage_type := _damage_type_option.get_item_text(_damage_type_option.selected)
	if damage_type != DAMAGE_TYPE_NONE:
		action["damageType"] = damage_type
	_send_action(action)

## dropConcentration is a no-op server-side (not an error) if the target
## isn't concentrating on anything -- same "safe to always show" reasoning
## as the death save button below.
func _on_drop_concentration_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({"type": "drop_concentration", "target": _tokens[_selected_token_id].token_name})

## spend_hit_die's `die` is a free-text die type (e.g. "d10") rather than a
## dropdown -- a token's own Hit Dice pool varies by class/level, same
## reasoning the Recharge Abilities row's free-text name field already
## uses for per-monster data with no fixed list to draw from.
func _on_spend_hit_dice_pressed() -> void:
	if not _require_selected_token():
		return
	var die := _hit_dice_type_input.text.strip_edges()
	if die == "":
		_show_hint("Enter a Hit Dice type first (e.g. d10).")
		return
	_send_action({
		"type": "spend_hit_die",
		"target": _tokens[_selected_token_id].token_name,
		"die": die,
		"count": int(_hit_dice_count_input.value)
	})

## removeToken deletes the token outright -- no confirmation dialog, matching
## this client's existing minimal-friction convention for every other
## action here (Full Heal, dropping to 0 HP, etc. have none either); the DM
## is trusted the same way at the table.
func _on_remove_token_pressed() -> void:
	if not _require_selected_token():
		return
	_send_action({"type": "remove_token", "target": _tokens[_selected_token_id].token_name})

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

## Phase 7 -- POSTs free-text DM narration to engine-server's /dm-command,
## which does the entire "ask Claude what should happen" round trip in one
## call (write dm-bridge/request.json, wait for dm-bridge/watch.js to answer,
## apply the actions through the real engine, hand back updated state) --
## same contract ui/app.js's own DM-command box uses against the 2D app's
## identical dm-bridge/watch.js. Deliberately NOT gated on a selected token
## (narration is scene-wide, same as trigger_lair_action above) and uses its
## own in-flight flag so ordinary button actions keep working while this is
## pending -- it can take up to ~2 minutes for a real Claude response.
func _on_send_dm_command_pressed() -> void:
	if _dm_command_in_flight:
		return
	var command := _dm_command_input.text.strip_edges()
	if command == "":
		_show_hint("Type a DM command/narration line before sending it.")
		return

	_dm_command_in_flight = true
	_send_dm_command_button.disabled = true
	_dm_command_input.editable = false
	_dm_response_label.text = "Waiting for Claude Code (run \"node dm-bridge/watch.js\" if it isn't already running) -- can take up to 2 minutes..."

	var body := JSON.stringify({"command": command})
	var error := _dm_command_request.request(
		server_base_url + "/dm-command",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_dm_command_in_flight = false
		_send_dm_command_button.disabled = false
		_dm_command_input.editable = true
		_dm_response_label.text = "Could not send to engine-server (error %d)." % error

func _on_dm_command_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_dm_command_in_flight = false
	_send_dm_command_button.disabled = false
	_dm_command_input.editable = true
	var parsed = JSON.parse_string(body.get_string_from_utf8())

	if response_code != 200:
		var error_text: String = "unknown error"
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
			error_text = str(parsed["error"])
		_dm_response_label.text = "DM Assistant error (HTTP %d): %s" % [response_code, error_text]
		return

	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("state"):
		_dm_response_label.text = "engine-server sent a response this client doesn't understand."
		return

	_dm_command_input.text = ""
	var message: String = str(parsed.get("message", ""))
	_dm_response_label.text = message if message != "" else "(The DM assistant didn't include a narration.)"
	# Refresh immediately rather than waiting up to poll_interval_seconds for the
	# next tick -- the actions this response applied (moves, attacks, spawns)
	# should be visible on the board right away, same as every other action
	# response already does via _on_action_response.
	_apply_state(parsed["state"])

## Shared guard for every "acts on the selected token" HUD control (rolls,
## condition toggles) -- same "show a status hint, don't just silently no-op"
## convention _handle_right_click already uses for the no-attacker-selected
## case.
func _require_selected_token() -> bool:
	if _selected_token_id == "" or not _tokens.has(_selected_token_id):
		_show_hint("Left-click a token first to select it, then use its controls.")
		return false
	return true

## RollModeOption's fixed item order (see Main.tscn) -- index, not id, since a plain
## OptionButton's `selected` is an index into however items were added.
const ROLL_MODE_NORMAL := 0
const ROLL_MODE_ADVANTAGE := 1
const ROLL_MODE_DISADVANTAGE := 2

func _roll_mode_advantage() -> bool:
	return _roll_mode_option.selected == ROLL_MODE_ADVANTAGE

func _roll_mode_disadvantage() -> bool:
	return _roll_mode_option.selected == ROLL_MODE_DISADVANTAGE

## Merges the shared roll-mode selector's advantage/disadvantage into an action
## dict already built by a caller -- only adds the keys when actually set, so
## a Normal roll's action payload looks exactly like it did before this
## control existed (no stray `"advantage": false` clutter for the server/log
## to ignore).
func _apply_roll_mode(action: Dictionary) -> Dictionary:
	if _roll_mode_advantage():
		action["advantage"] = true
	if _roll_mode_disadvantage():
		action["disadvantage"] = true
	return action

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
			if _template_active:
				_handle_template_left_press(event.position)
			else:
				_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_template_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_press_pos = event.position
				_right_press_active = true
			elif _right_press_active:
				_right_press_active = false
				if event.position.distance_to(_right_press_pos) <= RIGHT_CLICK_DRAG_THRESHOLD_PX:
					_handle_right_click(event.position)
	elif event is InputEventMouseMotion and _template_dragging:
		_handle_template_drag(event.position)

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
	_send_action(_apply_roll_mode({"type": "attack", "attacker": attacker_name, "target": target.token_name}))

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
