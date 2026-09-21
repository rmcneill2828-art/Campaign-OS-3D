extends SceneTree
## Functional check for the Campaign Browser (ROADMAP.md's "Seven requested features"
## 2026-09-19 entry, item 4, built 2026-09-21). Drives CampaignBrowser.gd through a
## synthetic campaign dict (the real shape dm-bridge/watch.js's own new
## import-campaign-response.json produces -- see that file's own handleImportCampaignRequest,
## verified live separately against a throwaway fake campaign folder) rather than a real
## engine-server/watch.js round trip, the same "synthetic state, no real server needed"
## approach test_aoe_template.gd's own _test_main_integration() already established.
##
## See smoke_test_main.gd's own doc comment for why quit() is deferred to the first
## _process() tick rather than called synchronously in _init().

var _failures := 0
var _main
var _browser

func _fail(message: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % message)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

func _fake_campaign() -> Dictionary:
	return {
		"name": "Test Campaign",
		"importedAt": "2026-09-21T00:00:00.000Z",
		"categories": {
			"characters": [
				{
					"id": "characters/Kestrel.md-1", "title": "Kestrel", "path": "characters/Kestrel.md",
					"category": "characters", "canSpawnToken": true, "isTemplate": false,
					"summary": "A ranger.", "wordCount": 2, "text": "# Kestrel\nA ranger.",
					"draft": {"name": "Kestrel", "type": "hero", "hp": 28, "maxHp": 28, "ac": 15, "abilityScores": {"DEX": 17}}
				},
				{
					"id": "npcs/Villain.md-2", "title": "The Villain", "path": "npcs/Villain.md",
					"category": "characters", "canSpawnToken": true, "isTemplate": false,
					"summary": "A recurring antagonist.", "wordCount": 3, "text": "# The Villain\nA recurring antagonist.",
					"draft": {"name": "The Villain", "type": "monster", "hp": 40, "maxHp": 40, "ac": 14}
				}
			],
			"locations": [
				{
					"id": "locations/Town.md-3", "title": "Quiet Town", "path": "locations/Town.md",
					"category": "locations", "canSpawnToken": false, "isTemplate": false,
					"summary": "A quiet town.", "wordCount": 3, "text": "# Quiet Town\nA quiet town."
				}
			],
			"sessions": [],
			"notes": []
		}
	}

func _test_main_builds_button(main) -> void:
	var found := false
	for child in main.get("_hud").get_children():
		if child is Button and child.text == "Campaign Browser":
			found = true
			break
	_check(found, "Main._ready() built the Campaign Browser button under $HUD")

func _test_refresh_lists(browser) -> void:
	browser.set("_campaign", _fake_campaign())
	browser.call("_refresh_lists")

	var lists: Dictionary = browser.get("_category_lists")
	var characters_list: ItemList = lists["characters"]
	var locations_list: ItemList = lists["locations"]
	_check(characters_list.item_count == 2, "Both character/NPC items land in the Characters list")
	_check(locations_list.item_count == 1, "The one location lands in the Locations list")
	_check(lists["sessions"].item_count == 0 and lists["notes"].item_count == 0, "Empty categories stay empty, not an error")

	# Search filters by title OR summary, case-insensitively, across the currently
	# imported campaign -- re-running _refresh_lists() (not a separate filter function)
	# rebuilds every list from scratch each time, matching the class doc comment's own
	# "cheap enough to just rebuild" reasoning.
	browser.get("_search_input").text = "antagonist"
	browser.call("_refresh_lists")
	_check(characters_list.item_count == 1, "Searching by a summary word filters down to the matching item")
	_check(characters_list.get_item_text(0) == "The Villain", "The surviving item after search is the right one")

	browser.get("_search_input").text = ""
	browser.call("_refresh_lists")
	_check(characters_list.item_count == 2, "Clearing the search restores every item")

func _test_item_selection(browser) -> void:
	var lists: Dictionary = browser.get("_category_lists")
	var characters_list: ItemList = lists["characters"]

	browser.call("_on_item_selected", 0, "characters")
	_check(browser.get("_detail_label").text.contains("Kestrel"), "Selecting an item shows its title in the detail pane")
	_check(browser.get("_detail_label").text.contains("A ranger."), "The detail pane also shows the item's own text")
	_check(browser.get("_spawn_button").visible, "A spawnable character item (canSpawnToken + a real draft) shows the Spawn button")

	browser.call("_on_item_selected", 1, "characters")
	_check(browser.get("_detail_label").text.contains("The Villain"), "Selecting a second item replaces the detail pane, not appends to it")

	var lists2: Dictionary = browser.get("_category_lists")
	browser.call("_on_item_selected", 0, "locations")
	_check(not browser.get("_spawn_button").visible, "A non-character item (canSpawnToken: false) hides the Spawn button")

func _test_build_spawn_action(browser) -> void:
	var hero_action: Dictionary = browser.call("_build_spawn_action", {"name": "Kestrel", "type": "hero", "hp": 28, "maxHp": 28, "ac": 15, "abilityScores": {"DEX": 17}})
	_check(hero_action["type"] == "add_token", "The built action is a real add_token action")
	_check(hero_action["tokenType"] == "hero" and hero_action["name"] == "Kestrel", "Name/type carry through from the draft")
	_check(hero_action["abilityScores"] == {"DEX": 17}, "abilityScores carries through when the draft has one -- the one field that makes saves/checks resolve reasonably without a full add_token widening")

	var monster_action: Dictionary = browser.call("_build_spawn_action", {"name": "The Villain", "type": "monster", "hp": 40, "maxHp": 40, "ac": 14})
	_check(monster_action["tokenType"] == "monster", "A monster-type draft (an npcs/ sheet) builds a monster tokenType")
	_check(not monster_action.has("abilityScores"), "A draft with no abilityScores at all doesn't fabricate one")

func _test_import_response_parsing(browser) -> void:
	var ok_body := JSON.stringify({"ok": true, "message": "Imported 2 file(s) from the campaign repo.", "campaign": _fake_campaign()}).to_utf8_buffer()
	browser.call("_on_import_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), ok_body)
	_check(browser.get("_status_label").text == "Imported 2 file(s) from the campaign repo.", "A successful import response updates the status label with the real message")
	var lists: Dictionary = browser.get("_category_lists")
	_check((lists["characters"] as ItemList).item_count == 2, "A successful import response also repopulates the lists")

	var fail_body := JSON.stringify({"ok": false, "message": "DND_REPO_PATH isn't set.", "campaign": null}).to_utf8_buffer()
	browser.call("_on_import_response", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), fail_body)
	_check(browser.get("_status_label").text == "DND_REPO_PATH isn't set.", "An ok:false response (a real, correctly-answered failure, not a transport error) surfaces its own message")

func _init() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_main = scene.instantiate()
	get_root().add_child(_main)
	_browser = CampaignBrowser.new()
	get_root().add_child(_browser)

var _ran := false
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_main_builds_button(_main)
	_test_refresh_lists(_browser)
	_test_item_selection(_browser)
	_test_build_spawn_action(_browser)
	_test_import_response_parsing(_browser)
	print("")
	if _failures > 0:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)
	else:
		print("All Campaign Browser assertions passed")
		quit()
	return true
