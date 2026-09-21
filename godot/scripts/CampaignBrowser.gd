extends Control
class_name CampaignBrowser
## Item 4 of ROADMAP.md's "Seven requested features" (2026-09-19) -- Import campaigns,
## the spawn-ready half (map/asset generation is a fully separate, manual pipeline, see
## that item's own note). engine/campaign.js's importMarkdownFiles() already parses a
## folder of campaign markdown into characters/locations/sessions/notes -- it just takes
## a browser FileList, which neither Godot nor engine-server has. The real fix is on the
## other two layers (dm-bridge/watch.js's new import-campaign-request/response.json
## mailbox reads the real files server-side; engine-server's POST /import-campaign is
## the one round trip this panel needs) -- this script is purely the browsing/spawning
## UI on top of whatever that round trip hands back.
##
## Entirely code-built (no .tscn), same convention every other panel added this session
## uses (AoE Template controls, Character Creator, View Character's own HUD). One-shot
## import, not a live poll -- a campaign's markdown doesn't change out from under a DM
## mid-session the way encounter state does, so there's no reason to re-fetch on a timer
## the way Main.gd's own board poll or CharacterViewer's own stat poll do.

const CATEGORIES: Array[String] = ["characters", "locations", "sessions", "notes"]

var server_base_url := ""

var _import_button: Button
var _status_label: Label
var _search_input: LineEdit
var _tabs: TabContainer
var _category_lists: Dictionary = {} # category name (String) -> ItemList
var _detail_label: RichTextLabel
var _spawn_button: Button
var _spawn_status_label: Label
var _import_request: HTTPRequest
var _action_request: HTTPRequest

var _campaign: Dictionary = {} # last successfully imported campaign, or {} before the first import
var _selected_item: Dictionary = {} # the item currently shown in the detail pane, or {}

## Called by Main.gd right after instantiating this (and before adding it to the scene
## tree), same convention CharacterViewer.gd's own open() already establishes.
func open(base_url: String) -> void:
	server_base_url = base_url

func _ready() -> void:
	_build_ui()
	_import_request = HTTPRequest.new()
	add_child(_import_request)
	_import_request.request_completed.connect(_on_import_response)
	_action_request = HTTPRequest.new()
	add_child(_action_request)
	_action_request.request_completed.connect(_on_action_response)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var top_row := HBoxContainer.new()
	_import_button = Button.new()
	_import_button.text = "Import Campaign"
	_import_button.pressed.connect(_on_import_pressed)
	top_row.add_child(_import_button)
	_status_label = Label.new()
	_status_label.text = "Not imported yet -- click Import Campaign (needs DND_REPO_PATH set for dm-bridge/watch.js)."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_status_label)
	layout.add_child(top_row)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search titles and summaries..."
	_search_input.text_changed.connect(func(_text): _refresh_lists())
	layout.add_child(_search_input)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(320, 0)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for category in CATEGORIES:
		var list := ItemList.new()
		list.name = category.capitalize()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_selected.connect(_on_item_selected.bind(category))
		_tabs.add_child(list)
		_category_lists[category] = list
	split.add_child(_tabs)

	var detail_panel := VBoxContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = false
	_detail_label.scroll_active = true
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_label.text = "Select an item from a category on the left."
	detail_panel.add_child(_detail_label)

	var spawn_row := HBoxContainer.new()
	_spawn_button = Button.new()
	_spawn_button.text = "Spawn as Token"
	_spawn_button.visible = false
	_spawn_button.pressed.connect(_on_spawn_pressed)
	spawn_row.add_child(_spawn_button)
	_spawn_status_label = Label.new()
	spawn_row.add_child(_spawn_status_label)
	detail_panel.add_child(spawn_row)

	split.add_child(detail_panel)

func _on_import_pressed() -> void:
	_import_button.disabled = true
	_status_label.text = "Importing (dm-bridge/watch.js must be running)..."
	var error := _import_request.request(
		server_base_url + "/import-campaign",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		""
	)
	if error != OK:
		_status_label.text = "Could not reach engine-server (error %d)." % error
		_import_button.disabled = false

func _on_import_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_import_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_status_label.text = "Import request failed (%s) -- engine-server may be unresponsive." % result
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_status_label.text = "engine-server sent a response this client doesn't understand."
		return
	if response_code != 200:
		_status_label.text = "Import failed (HTTP %d): %s" % [response_code, str(parsed.get("error", "unknown error"))]
		return
	# ok can legitimately be false here (DND_REPO_PATH not set/not found on the machine
	# running dm-bridge/watch.js) without this being a transport-level failure -- same "a
	# miss isn't a 500" precedent Main.gd's own Create Character handling already follows.
	if not parsed.get("ok", false):
		_status_label.text = str(parsed.get("message", "Import failed."))
		return

	_campaign = parsed.get("campaign", {})
	_status_label.text = str(parsed.get("message", "Imported."))
	_refresh_lists()

## Rebuilds every category's ItemList from _campaign + the current search text --
## cheap enough to just rebuild from scratch on every keystroke/import, same "don't
## bother diffing" convention GridManager's grid lines/PlayerView's fog overlay already
## use for a similarly small, infrequently-changing dataset. Each list entry's metadata
## is the real item Dictionary itself (title/path/text/draft/...), not just its index,
## so _on_item_selected() below never needs to re-look-it-up out of _campaign.
func _refresh_lists() -> void:
	var query := _search_input.text.to_lower()
	var categories: Dictionary = _campaign.get("categories", {})
	for category in CATEGORIES:
		var list: ItemList = _category_lists[category]
		list.clear()
		var items: Array = categories.get(category, [])
		for item in items:
			var title := str(item.get("title", ""))
			var summary := str(item.get("summary", ""))
			if query != "" and not title.to_lower().contains(query) and not summary.to_lower().contains(query):
				continue
			var index := list.add_item(title)
			list.set_item_metadata(index, item)

func _on_item_selected(index: int, category: String) -> void:
	var list: ItemList = _category_lists[category]
	var item: Dictionary = list.get_item_metadata(index)
	_selected_item = item
	_spawn_status_label.text = ""

	var header := "[b]%s[/b]\n%s" % [str(item.get("title", "")), str(item.get("path", ""))]
	var summary := str(item.get("summary", ""))
	if summary != "":
		header += "\n[i]%s[/i]" % summary
	_detail_label.text = "%s\n\n%s" % [header, str(item.get("text", ""))]

	_spawn_button.visible = bool(item.get("canSpawnToken", false)) and item.has("draft")

## Reuses the already-built add_token DM-bridge action (see ROADMAP.md's own
## "add_token DM-bridge action" entry) rather than a new one -- only forwards
## name/tokenType/hp/maxHp/ac/abilityScores, the same subset that action already
## accepts server-side. A real, deliberate scope decision, not an oversight: the richer
## fields tokenDraftFromItem() also extracts (attackBonus/damageDice/skills/
## savingThrows/spellcasting) aren't carried over this pass -- abilityScores alone is
## enough for saves/checks to resolve reasonably (encounter.js's own savingThrowBonus()/
## abilityCheckBonus() fall back to the raw ability modifier with no stated override),
## and the rest can be filled in by hand on the token sheet after spawning, same as any
## manually-added token. Widening add_token itself to carry the rest would mean editing
## the shared, sync-checked dmBridge.js -- a real, separate follow-up if this gap ever
## actually bites in play, not bundled into this pass.
## Pure and separate from the actual network call below specifically so it's directly
## testable (see test_campaign_browser.gd) without needing to intercept or mock an
## outgoing HTTPRequest -- same "parse/build in a pure function, send separately"
## separation Main.gd's own _apply_roll_mode() already follows.
func _build_spawn_action(draft: Dictionary) -> Dictionary:
	var action := {
		"type": "add_token",
		"name": draft.get("name", "Imported Character"),
		"tokenType": draft.get("type", "hero"),
		"hp": draft.get("hp"),
		"maxHp": draft.get("maxHp"),
		"ac": draft.get("ac")
	}
	if draft.has("abilityScores"):
		action["abilityScores"] = draft["abilityScores"]
	return action

func _on_spawn_pressed() -> void:
	if _selected_item.is_empty():
		return
	var draft: Dictionary = _selected_item.get("draft", {})
	if draft.is_empty():
		_spawn_status_label.text = "No spawnable data for this item."
		return

	var action := _build_spawn_action(draft)
	_spawn_button.disabled = true
	_spawn_status_label.text = "Spawning..."
	var body := JSON.stringify(action)
	var error := _action_request.request(
		server_base_url + "/action",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_spawn_button.disabled = false
		_spawn_status_label.text = "Could not reach engine-server (error %d)." % error

func _on_action_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_spawn_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_spawn_status_label.text = "Spawn request failed -- engine-server may be unresponsive."
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		_spawn_status_label.text = "Spawn failed (HTTP %d)." % response_code
		return
	var messages: Array = parsed.get("messages", [])
	_spawn_status_label.text = str(messages[0]) if not messages.is_empty() else "Spawned."
