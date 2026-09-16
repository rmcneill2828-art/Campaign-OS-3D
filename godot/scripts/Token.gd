extends Node3D
class_name Token
## One 3D miniature. Deliberately dumb -- it only renders whatever `apply_data()`
## is given each poll and reports its own click via the "Body" StaticBody3D's group
## membership; Main.gd owns all selection/movement decisions and talks to the
## server.
##
## Model loading is intentionally NOT preload() -- the real creature models
## (Quaternius, Phase 2) are licensed for use but NOT committed to this git repo
## (see godot/assets/README.md: their license permits using them in a game,
## but not redistributing the raw asset files themselves, which committing them
## to a repo would risk). A fresh clone without those files re-downloaded must
## still open and run -- just with the plain colored-capsule placeholder Phase 0
## shipped with -- rather than fail to load the scene at all. `load()` +
## `ResourceLoader.exists()` achieves that; `preload()` would not.

## Lookup key -> a full "model family" config: which model to instance, where
## its name/HP label floats (label_height, meters above its own feet --
## whatever vertical offset the model actually needs to stand on the floor is
## figured out at runtime regardless, see _ground_model()), which shared
## animation-source file drives its skeleton (see _setup_animation()), and
## the bare clip names (post Godot-import, see IDLE/WALK's own comment below)
## for idle/walk/death/dying/hit reactions within it.
##
## Keys are either a bare token type ("hero", "monster" -- the fallback used
## when no more specific entry matches) or "monster:<stat-block name>"
## (lowercased, e.g. "monster:skeleton") for a real per-monster-name model --
## see _stat_block_key() and _rebuild_model()'s own lookup order. Phase 8's
## first per-name entry (skeleton) is what proved this two-tier lookup was
## worth having at all; before it, every monster silently rendered as the
## Imp regardless of which SRD stat block it actually was (a known,
## documented gap since Phase 2).
##
## Any of idle/walk/death/dying, or one entry of hits, may be EITHER a plain
## clip name (String, resolved against animation_source -- the simple case
## every Quaternius/KayKit entry below uses) OR a `{"clip": <name>, "source":
## <path>}` Dictionary, meaning that one clip actually lives in a DIFFERENT
## file entirely and needs importing into animation_source's own player
## first (see _setup_animation()'s _resolve_or_import() helper). The Orc
## entry below needs this for literally every field -- Meshy's per-clip
## animation API hands back one full skinned model per requested clip, not
## one shared library file the way Quaternius/KayKit ship theirs.
##
## An entry may also carry an optional `bone_name_map` (Dictionary, character
## bone name -> animation-source bone name) for a model/animation-source pair
## whose skeletons don't share bone names at all -- confirmed to actually be
## the case between a Meshy auto-rig and every free pack here (Meshy's rig
## uses Mixamo-style names like "LeftUpLeg"; Quaternius uses "thigh_l",
## KayKit uses "upperleg.l" -- zero names in common, checked directly by
## extracting both skeletons' real bone lists, not assumed). Without a map,
## _setup_animation()'s bone-matching loop requires an EXACT name match
## (every existing entry above relies on this -- Quaternius's own pack
## sharing names with itself, KayKit's own pack sharing names with itself),
## which is why a Meshy-rigged model paired with a free-pack animation source
## needs this field to animate at all; omitting it (every entry above) keeps
## today's exact-match behavior byte-for-byte unchanged.
##
## TWO separate Meshy bone-naming conventions have shown up already, not one
## -- checked directly rather than assumed to still hold from the first
## rigged model, and good thing: they're genuinely different.
## `MESHY_API_RIG_TO_QUATERNIUS_UAL1_BONE_MAP` is from `orc_warrior.glb`,
## rigged via the Composio-connected `MESHY_CREATE_RIGGING_TASK` API (no
## skeleton-template choice exposed there) -- Mixamo-STYLE names but no
## `mixamorig:` prefix, "Spine01"/"Spine02", lowercase "neck". 22 of its 24
## bones map cleanly; the 2 left out (`head_end`, `headfront`) are small
## Meshy-specific attachment bones with no Quaternius equivalent, not part
## of the walk/idle/attack silhouette -- harmless to leave unmapped, they
## just stay in their bind pose.
## `MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP` is from a model rigged
## through Meshy's website Rigging tool with "Skeleton template: Mixamo"
## explicitly selected (a dropdown the API path doesn't expose) -- genuine
## `mixamorig:`-prefixed names matching real Adobe Mixamo output exactly
## ("mixamorig:Hips", "mixamorig:Spine1"/"Spine2", capitalized "Neck"). 26 of
## its 28 bones map cleanly; only `mixamorig:HeadTop_End` and the same stray
## `headfront` are left out. This is the path an ordinary website download +
## manual rig (not the API) actually produces, so it's the one to expect for
## most future models.
## Both verified the same way: every target name confirmed to actually exist
## in `mannequin_animations.glb`'s real skeleton, no duplicate targets, no
## typo'd source keys -- see godot/tools/inspect_bone_name_map.gd. Don't
## assume either map still applies to a DIFFERENT future rig (a different
## creature, a quadruped, a different "Skeleton template" choice) without
## re-running that check -- this project has already been burned once this
## same phase by assuming one rigged model's bone names would generalize.
##
## A real gotcha already hit once, not hypothetical: `MESHY_MIXAMO_TEMPLATE_
## TO_QUATERNIUS_UAL1_BONE_MAP`'s keys were originally written with a colon
## ("mixamorig:Hips"), matching the raw glTF file's own bone names exactly
## (confirmed by extracting them directly) -- but the FIRST live Godot run
## (`inspect_bone_name_map.gd`, not assumed) came back 0/28 matched. Cause:
## Godot's glTF importer replaces ":" with "_" when it turns each joint into
## a Skeleton3D bone, something only visible by actually running it in Godot,
## never by reading the source file. Keys below use "mixamorig_" for exactly
## that reason -- if a future rig's own real prefix ever needs checking
## again, check the LIVE Godot bone names via the inspect tool, not the raw
## file.
const MESHY_API_RIG_TO_QUATERNIUS_UAL1_BONE_MAP := {
	"Hips": "pelvis",
	"Spine": "spine_01", "Spine01": "spine_02", "Spine02": "spine_03",
	"neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r"
}
## Keys use "mixamorig_" (underscore), NOT "mixamorig:" (colon) -- the raw
## glTF file's own bone names really do use a colon (confirmed by direct
## extraction, see this constant's own doc comment above), but Godot's glTF
## importer replaces ":" with "_" when it turns each joint into a Skeleton3D
## bone entry, a real, confirmed-live behavior (godot/tools/
## inspect_bone_name_map.gd run against a real Godot 4.7.2 install reported
## 0/28 matched with colon-keyed names, then 26/28 once corrected to
## underscores) -- not something the raw file itself or a script reading it
## directly would ever reveal, only Godot's own import pipeline. Don't
## "fix" this back to colons without re-confirming live first.
const MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP := {
	"mixamorig_Hips": "pelvis",
	"mixamorig_Spine": "spine_01", "mixamorig_Spine1": "spine_02", "mixamorig_Spine2": "spine_03",
	"mixamorig_Neck": "neck_01", "mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "clavicle_l", "mixamorig_LeftArm": "upperarm_l", "mixamorig_LeftForeArm": "lowerarm_l", "mixamorig_LeftHand": "hand_l",
	"mixamorig_RightShoulder": "clavicle_r", "mixamorig_RightArm": "upperarm_r", "mixamorig_RightForeArm": "lowerarm_r", "mixamorig_RightHand": "hand_r",
	"mixamorig_LeftUpLeg": "thigh_l", "mixamorig_LeftLeg": "calf_l", "mixamorig_LeftFoot": "foot_l", "mixamorig_LeftToeBase": "ball_l", "mixamorig_LeftToe_End": "ball_leaf_l",
	"mixamorig_RightUpLeg": "thigh_r", "mixamorig_RightLeg": "calf_r", "mixamorig_RightFoot": "foot_r", "mixamorig_RightToeBase": "ball_r", "mixamorig_RightToe_End": "ball_leaf_r",
	"mixamorig_LeftHandMiddle4": "middle_04_leaf_l", "mixamorig_RightHandMiddle4": "middle_04_leaf_r"
}
const MODEL_CONFIG := {
	"hero": {
		"path": "res://assets/creatures/hero/superhero_male.gltf", "label_height": 2.0,
		"animation_source": "res://assets/creatures/animations/mannequin_animations.glb",
		"idle": "Idle", "walk": "Walk", "death": "Death01", "dying": "Crouch_Idle",
		"hits": ["Hit_Chest", "Hit_Head"]
	},
	## First per-name HERO entry (mirrors "monster:skeleton"/"monster:orc"
	## below) -- a hero token literally named "Barbarian" now gets this model
	## instead of the generic superhero_male fallback every hero shared until
	## now. Model: a free static download from Meshy's library, rigged
	## through Meshy's WEBSITE Rigging tool with "Skeleton template: Mixamo"
	## selected -- genuine mixamorig:-prefixed bone names, a different
	## convention than orc_warrior.glb's own API-rigged skeleton (see
	## MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP's own doc comment
	## above for why two different maps exist). animation_source/clip names
	## reuse the plain "hero" entry's own Quaternius UAL1 source verbatim --
	## same file, same clips, only the model and its bone_name_map differ.
	## label_height reuses "hero"'s own 2.0 as a starting default (this
	## specific model's real proportions haven't been measured live) --
	## revisit once actually seen in Godot, same as every other
	## not-yet-live-verified number in this project's own history.
	"hero:barbarian": {
		"path": "res://assets/creatures/hero/barbarian.glb", "label_height": 2.0,
		"animation_source": "res://assets/creatures/animations/mannequin_animations.glb",
		"bone_name_map": MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP,
		"idle": "Idle", "walk": "Walk", "death": "Death01", "dying": "Crouch_Idle",
		"hits": ["Hit_Chest", "Hit_Head"]
	},
	"monster": {
		"path": "res://assets/creatures/monster/imp.glb", "label_height": 1.9,
		"animation_source": "res://assets/creatures/animations/mannequin_animations.glb",
		"idle": "Idle", "walk": "Walk", "death": "Death01", "dying": "Crouch_Idle",
		"hits": ["Hit_Chest", "Hit_Head"]
	},
	## KayKit Skeletons (godot/assets/README.md) -- a genuine per-name match for
	## the SRD "Skeleton" stat block, not a reuse of something else. Bone-name
	## compatibility against this specific animation pack was verified directly
	## (godot/tools/inspect_kaykit_skeleton.gd: 23/23 bones match across every
	## file checked), not assumed from a shared "Rig_Medium" folder name --
	## exactly the check godot/assets/README.md's own KayKit section flagged as
	## still outstanding before wiring anything in. idle/walk/death/dying all
	## come from the pack's own SKELETON-SPECIFIC clip set (Skeletons_Idle,
	## Skeletons_Walking, Skeletons_Death, Skeletons_Inactive_Floor_Pose --
	## e.g. that pack visibly authored a creature literally rising from an
	## inert heap on the floor, a much better fit than a generic humanoid
	## idle), found by listing that file's real clips rather than guessing;
	## hits reuse the pack's generic Hit_A/Hit_B (no skeleton-specific hit
	## reaction exists) from a separate sibling file in the same pack.
	"monster:skeleton": {
		"path": "res://assets/creatures/monster/skeleton_warrior.glb", "label_height": 1.9,
		"animation_source": "res://assets/creatures/animations/kaykit_rig_medium_special.glb",
		"idle": "Skeletons_Idle", "walk": "Skeletons_Walking", "death": "Skeletons_Death",
		"dying": "Skeletons_Inactive_Floor_Pose",
		"hits": [
			{"clip": "Hit_A", "source": "res://assets/creatures/animations/kaykit_rig_medium_general.glb"},
			{"clip": "Hit_B", "source": "res://assets/creatures/animations/kaykit_rig_medium_general.glb"}
		]
	},
	## Meshy AI (Phase 8, 2026-09-13) -- a custom-generated model for the SRD
	## "Orc" stat block, no free pre-made pack covered it. Generated via the
	## Composio-connected Meshy API: text-to-3D preview -> remesh to under the
	## 320k-face rigging limit -> rig (biped) with the preview's own texture
	## baked on -> one MESHY_CREATE_ANIMATION_TASK per needed clip against
	## Meshy's own preset animation library (its own search turned up
	## thematically-fitting picks: "Slow_Orc_Walk" already exists in that
	## library by name, and "Fall_Dead_from_Abdominal_Injury" is a real death
	## clip -- neither guessed at). Bone-name compatibility confirmed directly
	## (godot/tools/inspect_meshy_orc.gd: 24/24 bones match across every
	## animation file), same discipline as every other family here -- expected
	## to hold since Meshy retargets each requested clip onto the exact rig it
	## generated, but checked rather than assumed anyway.
	##
	## Every clip below needs the `{clip, source}` import form: Meshy's
	## animation API returns one full skinned model per requested clip
	## (`Armature|<ClipName>|baselayer`, its own export naming, not a
	## Godot-namespacing thing), not one shared multi-clip file the way
	## Quaternius/KayKit ship theirs -- animation_source (idle) is the only
	## clip that needs no import, since its own file already has a usable
	## skeleton+player pair to serve as the primary one _process() drives.
	## No good held "kneeling/wounded" pose exists in Meshy's preset library
	## (checked directly, not assumed) -- "dying" reuses a kneel-then-stand
	## transition clip as an imperfect stand-in, looped like the other
	## families' real held poses; revisit if it reads oddly at the table.
	"monster:orc": {
		"path": "res://assets/creatures/monster/orc_warrior.glb", "label_height": 2.1,
		"animation_source": "res://assets/creatures/animations/meshy_orc_idle.glb",
		"idle": "Armature|Idle|baselayer",
		"walk": {"clip": "Armature|Slow_Orc_Walk_inplace|baselayer", "source": "res://assets/creatures/animations/meshy_orc_walk.glb"},
		"death": {"clip": "Armature|Fall_Dead_from_Abdominal_Injury|baselayer", "source": "res://assets/creatures/animations/meshy_orc_death.glb"},
		"dying": {"clip": "Armature|Kneel_on_One_Knee_and_Stand|baselayer", "source": "res://assets/creatures/animations/meshy_orc_kneel.glb"},
		"hits": [
			{"clip": "Armature|Hit_Reaction|baselayer", "source": "res://assets/creatures/animations/meshy_orc_hit1.glb"},
			{"clip": "Armature|Hit_Reaction_1|baselayer", "source": "res://assets/creatures/animations/meshy_orc_hit2.glb"}
		]
	}
}
const FALLBACK_LABEL_HEIGHT := 1.9
const FALLBACK_CAPSULE_RADIUS := 0.4
const FALLBACK_CAPSULE_HEIGHT := 1.6

@onready var _model_root: Node3D = $Body/ModelRoot
@onready var _label: Label3D = $NameLabel
@onready var _selection_ring: MeshInstance3D = $SelectionRing
@onready var _body: StaticBody3D = $Body
@onready var _hp_bar_root: Node3D = $HPBarRoot
@onready var _hp_bar_fill_wrapper: Node3D = $HPBarRoot/HPBarFillWrapper
@onready var _hp_bar_fill: MeshInstance3D = $HPBarRoot/HPBarFillWrapper/HPBarFill

## Phase 6: set true only by PlayerView.gd, immediately after instantiating a
## Token for its own read-only board, never by Main.gd -- redacts the
## floating text label to match ui/playerView.js's own exact precedent (no
## name, no exact HP numbers, no conditions text visible on the map itself;
## a name only ever surfaces there via a hover tooltip, and conditions don't
## surface on the 2D player board at all). The HP BAR mesh (_update_hp_bar)
## is left untouched either way -- it was already numberless, just a
## color-banded quad, exactly the "rough health bar, no exact numbers"
## middle ground ui/playerView.js's own token-hp-bar already settled on.
var player_facing := false

var token_id := ""
var token_name := ""
var token_type := ""
var grid_x := 1
var grid_y := 1
var hp := 0
var max_hp := 1
var _last_hp := -1 # -1 means "no previous value yet" -- distinguishes first-ever apply_data from a real HP change
var _was_dead := false
var _was_dying := false

var _initialized := false
var _move_tween: Tween
# Set only while the fallback capsule is the active visual (null once a real
# model is loaded) -- lets HP-driven color react every poll without rebuilding
# the whole model tree each time (see _update_fallback_color below).
var _fallback_mesh: MeshInstance3D

# Animation state -- see _setup_animation(). All null/empty whenever the
# fallback capsule is active (no skeleton to animate) or the animation source
# asset isn't present.
var _character_skeleton: Skeleton3D
var _anim_source_skeleton: Skeleton3D
var _anim_source_player: AnimationPlayer
var _bone_map := {} # character bone index -> animation-source bone index
var _idle_animation_key := "" # resolved AnimationPlayer key, see _resolve_animation_name()
var _walk_animation_key := ""
var _death_animation_key := ""
var _dying_animation_key := ""
var _hit_animation_keys: Array[String] = []

func _ready() -> void:
	_body.add_to_group("tokens")
	_body.set_meta("token", self)
	# Fresh material per instance, not the .tscn's own shared sub-resource --
	# mutating a shared resource's color from one token's script would
	# visibly recolor every other token's HP bar too (the same class of
	# shared-resource gotcha this project already hit with animations).
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_fill.material_override = fill_material

## `data` is one token object straight out of the engine's own state.tokens array
## (see engine-server/engine/encounter.js) -- same field names, no translation layer.
func apply_data(data: Dictionary, grid: GridManager) -> void:
	token_id = str(data.get("id", token_id))
	token_name = str(data.get("name", token_name))
	var new_type: String = str(data.get("type", token_type))
	hp = int(data.get("hp", hp))
	max_hp = int(max(data.get("maxHp", max(hp, 1)), 1))
	var is_dead := bool(data.get("dead", false))
	# Present (a {successes, failures, stable} dict) means actively making
	# death saves OR stabilized-but-still-down -- both look the same
	# (kneeling), matching RAW: a stable creature is still unconscious, just
	# no longer rolling. Absent means either never went down, or came back up
	# (healed) -- not distinguished here, both just mean "not dying".
	var is_dying: bool = data.get("dying") != null

	if player_facing:
		_label.text = ""
	else:
		var conditions: Array = data.get("conditions", [])
		# String.join() wants a PackedStringArray, not a generic Array -- explicit
		# conversion rather than relying on implicit coercion to avoid guessing.
		var conditions_line := ("\n" + ", ".join(PackedStringArray(conditions))) if conditions.size() > 0 else ""
		_label.text = "%s\n%d/%d HP%s" % [token_name, hp, max_hp, conditions_line]
	_update_hp_bar()

	if not _initialized or new_type != token_type:
		token_type = new_type
		_rebuild_model()
	_update_fallback_color() # a real model's own texture is left alone; only the fallback capsule reacts to HP

	# Death/dying/hit-reaction animation -- only after the first real data (so
	# a freshly-spawned token at full HP doesn't play a "hit" reaction against
	# the -1 sentinel), and only via the real `dead`/`dying` flags (NOT a bare
	# hp<=0 check -- a token can sit at 0 HP mid-death-saves without being
	# `dead` yet, and RAW says nothing about kneeling just for losing HP while
	# still conscious). Priority order matters: dead beats everything (frozen,
	# permanent for this encounter -- UNLESS healed, see below), dying beats
	# hit-reaction (a creature already down doesn't play a standing
	# hit-flinch), and the transitions into/out of dying/dead are
	# edge-triggered off _was_dying/_was_dead so the loop isn't re-started
	# every single poll while nothing has changed.
	#
	# `applyHealing` (engine-server/engine/encounter.js) treats healing a dead
	# token above 0 HP as a deliberate revival (Revivify, Raise Dead, a DM
	# ruling -- there's no separate "revive" action, the same generic Heal
	# button does it) and clears `dead` server-side when that happens -- so a
	# dead token CAN come back to `is_dead == false` directly, without ever
	# passing back through `dying`. Only handling the was_dying->idle
	# transition below and not this one left a revived token permanently
	# frozen on Death01's last frame even though the server had already
	# correctly revived it -- a real animation bug, not a rules question.
	if _initialized and _anim_source_player:
		if is_dead and not _was_dead:
			_play_source_animation(_death_animation_key)
		elif is_dead:
			pass # stay frozen on Death01's last frame
		elif is_dying and not _was_dying:
			_play_source_animation(_dying_animation_key)
		elif not is_dying and (_was_dying or _was_dead):
			_play_source_animation(_idle_animation_key) # healed/revived/stood back up
		elif not is_dying and _last_hp >= 0 and hp < _last_hp and not _hit_animation_keys.is_empty():
			_play_source_animation(_hit_animation_keys.pick_random())
	_last_hp = hp
	_was_dead = is_dead
	_was_dying = is_dying

	# Grid cell -> world space directly, no extra vertical offset -- Body's own
	# children (the collision capsule, the fallback mesh) each carry whatever
	# local Y offset THEY need; adding one here too was a Phase 0/1 bug that
	# left every token floating 0.8m above the floor (harmless-looking with a
	# capsule, would have been obviously wrong once real ground-touching models
	# were added, so fixed now rather than papering over it with a matching
	# offset on the new models).
	var target: Vector3 = grid.cell_to_world(int(data.get("x", grid_x)), int(data.get("y", grid_y)))
	var moved := _initialized and (int(data.get("x", grid_x)) != grid_x or int(data.get("y", grid_y)) != grid_y)
	grid_x = int(data.get("x", grid_x))
	grid_y = int(data.get("y", grid_y))

	if moved:
		_animate_to(target)
	else:
		position = target
	_initialized = true

func _rebuild_model() -> void:
	for child in _model_root.get_children():
		child.queue_free()
	_fallback_mesh = null
	_character_skeleton = null
	_anim_source_skeleton = null
	_anim_source_player = null
	_bone_map.clear()
	_idle_animation_key = ""
	_walk_animation_key = ""
	_death_animation_key = ""
	_dying_animation_key = ""
	_hit_animation_keys = []

	# A token's real per-name entry (e.g. "monster:skeleton", "hero:barbarian")
	# wins over its type's generic fallback if one exists -- see MODEL_CONFIG's
	# own doc comment for why this two-tier lookup exists at all. Originally
	# monster-only (every hero rendered as the same superhero_male regardless
	# of name); extended to heroes the same way once a real per-name hero
	# model existed to look up, rather than building the hero half of this
	# ahead of ever needing it.
	var config_key := token_type
	if token_type == "monster" or token_type == "hero":
		var specific_key := token_type + ":" + _stat_block_key(token_name)
		if MODEL_CONFIG.has(specific_key):
			config_key = specific_key
	var config: Dictionary = MODEL_CONFIG.get(config_key, {})
	var model_path: String = config.get("path", "")
	var label_height: float = float(config.get("label_height", FALLBACK_LABEL_HEIGHT))

	if model_path != "" and ResourceLoader.exists(model_path):
		var scene := load(model_path) as PackedScene
		var instance := scene.instantiate() as Node3D
		_model_root.add_child(instance)
		_ground_model(instance)
		_setup_animation(instance, config)
		_label.position.y = label_height
	else:
		_add_fallback_capsule()
		_label.position.y = FALLBACK_LABEL_HEIGHT
		label_height = FALLBACK_LABEL_HEIGHT
	# Above the label, not below/overlapping it -- reported as "HP is there
	# but hard to see" when it sat at label_height - 0.2, likely lost against
	# the label's own multi-line text block right next to it. Clearly
	# separated (and bigger -- see the .tscn's QuadMesh sizes) should read
	# better; a further tuning pass may still be needed once actually seen.
	_hp_bar_root.position.y = label_height + 0.35

## Monster tokens are named "<Stat Block Name> <N>" by the engine's own
## spawnMonster() (e.g. "Skeleton 2") -- stripping the trailing number and
## lowercasing recovers the actual stat-block identity a specific
## MODEL_CONFIG entry should key off, the same name-matching convention
## dm-bridge/watch.js's own MONSTER_LIST already uses for narration-driven
## spawning. A name with no trailing number (a hand-placed token, either
## "addToken" instead of "spawn", or any hero -- heroes are always
## hand-placed, never spawned) just lowercases as-is -- no match in
## MODEL_CONFIG simply falls through to the type's generic entry, same as
## always. Shared between monster and hero lookups (see _rebuild_model())
## since the underlying rule -- "strip a trailing spawn-count number if
## present, lowercase the rest" -- doesn't actually depend on which type of
## token it's being applied to.
func _stat_block_key(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("^(.*?)\\s+\\d+$")
	var result := regex.search(name)
	var base_name := result.get_string(1) if result else name
	return base_name.strip_edges().to_lower()

## Drives `instance`'s skeleton from a SEPARATE, hidden instance of the
## family's own shared animation-source model (config["animation_source"]),
## copying bone poses across every frame by matching bone NAMES between the
## two skeletons -- deliberately not attempting to graft the source's
## Animation resources directly onto this model's own (nonexistent)
## AnimationPlayer via NodePath surgery, which would depend on Godot's glTF
## importer producing byte-for-byte identical scene structure across every
## different file, an assumption this project has already been burned by
## more than once this phase (see _ground_model's and GridManager.gd's own
## comments on trusting file structure over measuring the real thing).
## Copying bone-by-bone through each Skeleton3D's own pose API works
## regardless of how either scene happens to be structured around its
## skeleton.
func _setup_animation(instance: Node3D, config: Dictionary) -> void:
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_character_skeleton = skeletons[0] as Skeleton3D

	var animation_source_path: String = config.get("animation_source", "")
	if animation_source_path == "" or not ResourceLoader.exists(animation_source_path):
		return
	var source_scene := load(animation_source_path) as PackedScene
	var source_instance := source_scene.instantiate() as Node3D
	source_instance.visible = false # only its skeleton/player matter -- never rendered itself
	_model_root.add_child(source_instance)

	var source_skeletons := source_instance.find_children("*", "Skeleton3D", true, false)
	var source_players := source_instance.find_children("*", "AnimationPlayer", true, false)
	if source_skeletons.is_empty() or source_players.is_empty():
		return
	_anim_source_skeleton = source_skeletons[0] as Skeleton3D
	_anim_source_player = source_players[0] as AnimationPlayer

	# bone_name_map (see MODEL_CONFIG's own doc comment) translates the
	# character's bone name before searching the animation source, for a pair
	# whose skeletons don't share bone names at all (Meshy's rig vs. a free
	# pack's own animation library). Every existing family below has no
	# bone_name_map entry, so .get() falls through to bone_name unchanged --
	# this is a pure addition, exact-match behavior is byte-for-byte the same
	# as before for every family that doesn't opt in.
	var bone_name_map: Dictionary = config.get("bone_name_map", {})
	for char_idx in range(_character_skeleton.get_bone_count()):
		var bone_name := _character_skeleton.get_bone_name(char_idx)
		var source_bone_name: String = bone_name_map.get(bone_name, bone_name)
		var source_idx := _anim_source_skeleton.find_bone(source_bone_name)
		if source_idx != -1:
			_bone_map[char_idx] = source_idx

	# Resolved once here rather than assumed from config's bare clip name
	# directly -- a glTF import can namespace its animations under a named
	# AnimationLibrary (yielding a key like "somelib/Idle") rather than the
	# default unnamed one, and has_animation()/play() need the exact key
	# either way. Each of these may instead be a {clip, source} Dictionary
	# naming a DIFFERENT file entirely -- see _resolve_or_import() and
	# MODEL_CONFIG's own doc comment for why the Orc family needs that for
	# every field.
	_idle_animation_key = _resolve_or_import(config.get("idle", ""))
	_walk_animation_key = _resolve_or_import(config.get("walk", ""))
	_death_animation_key = _resolve_or_import(config.get("death", ""))
	_dying_animation_key = _resolve_or_import(config.get("dying", ""))

	_hit_animation_keys = []
	for hit_entry in config.get("hits", []):
		var resolved: String = _resolve_or_import(hit_entry)
		if resolved != "":
			_hit_animation_keys.append(resolved)

	# "_Loop"-suffixed clips in some packs aren't necessarily flagged to loop
	# by default on import -- force it so Idle/Walk/Dying actually repeat
	# instead of freezing on their last frame. Death/hit clips are
	# deliberately NOT forced to loop -- a death pose should freeze on its
	# last frame, and a hit reaction should play once and hand back to idle
	# (see _on_source_animation_finished).
	for key in [_idle_animation_key, _walk_animation_key, _dying_animation_key]:
		if key != "":
			_anim_source_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR

	if not _anim_source_player.animation_finished.is_connected(_on_source_animation_finished):
		_anim_source_player.animation_finished.connect(_on_source_animation_finished)

	print("Token %s: animation bone map covers %d/%d bones (%s); idle=%s walk=%s dying=%s%s" % [
		token_name, _bone_map.size(), _character_skeleton.get_bone_count(),
		"looks complete" if _bone_map.size() == _character_skeleton.get_bone_count() else "some bones unmatched -- check names",
		_idle_animation_key if _idle_animation_key != "" else "NOT FOUND",
		_walk_animation_key if _walk_animation_key != "" else "NOT FOUND",
		_dying_animation_key if _dying_animation_key != "" else "NOT FOUND",
		"; available: %s" % [_anim_source_player.get_animation_list()] if _idle_animation_key == "" or _walk_animation_key == "" or _dying_animation_key == "" else ""
	])

	_play_source_animation(_idle_animation_key)

## Resolves one config animation VALUE (idle/walk/death/dying, or one hits
## entry) against `_anim_source_player` -- either a plain clip name (String,
## resolved directly, the common case every Quaternius/KayKit field uses) or
## a `{"clip": <name>, "source": <path>}` Dictionary meaning that clip
## actually lives in a different file and needs importing first (see
## MODEL_CONFIG's own doc comment for why the Orc family needs this for
## every field). Returns "" if the clip can't be found/imported at all --
## every caller already treats an empty key as "this family has no
## animation for this state," the same graceful-degradation convention
## _play_source_animation()'s own no-op-on-empty-key already relies on.
func _resolve_or_import(value) -> String:
	if value is String:
		return _resolve_animation_name(_anim_source_player, value)
	if value is Dictionary:
		var clip_name: String = value.get("clip", "")
		var source_path: String = value.get("source", "")
		if clip_name == "" or source_path == "" or not ResourceLoader.exists(source_path):
			return ""
		var source_scene := load(source_path) as PackedScene
		var source_instance := source_scene.instantiate() as Node3D
		var source_players := source_instance.find_children("*", "AnimationPlayer", true, false)
		var imported := ""
		if not source_players.is_empty():
			imported = _import_animation_clip(_anim_source_player, source_players[0] as AnimationPlayer, clip_name)
		source_instance.queue_free() # never added to the tree -- just a temporary clip source
		return imported
	return ""

## Copies one named clip's Animation resource from `source_player` (a
## temporary, never-added-to-the-tree instance -- see its caller above) into
## `target_player`'s own default animation library, so a single
## AnimationPlayer can play a clip that actually lives in a completely
## different imported file. Returns the clip's own bare name (now playable
## directly on `target_player`) once imported, or "" if `clip_name` isn't
## found in `source_player` at all. Reuses (mutates in place), not replaces,
## `target_player`'s existing default library if it already has one -- a
## fresh glTF-imported AnimationPlayer already owns its own default library
## full of its native clips, and replacing it outright would lose all of them.
func _import_animation_clip(target_player: AnimationPlayer, source_player: AnimationPlayer, clip_name: String) -> String:
	var resolved_source_key := _resolve_animation_name(source_player, clip_name)
	if resolved_source_key == "":
		return ""
	var animation: Animation = source_player.get_animation(resolved_source_key)
	var library: AnimationLibrary
	if target_player.has_animation_library(""):
		library = target_player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		target_player.add_animation_library("", library)
	if library.has_animation(clip_name):
		library.remove_animation(clip_name)
	library.add_animation(clip_name, animation)
	return clip_name

## A one-shot reaction clip (hit or death) finishing playback hands control
## back to idle -- EXCEPT death, which should stay frozen on its final pose,
## not snap back to standing, and EXCEPT dying, which is forced to loop (see
## _setup_animation) so this only fires for it once per lap the same way it
## does for idle/walk -- re-playing the same key it's already on is already a
## no-op in _play_source_animation(), so excluding it here isn't strictly
## required for correctness, but keeps this function's intent (idle is the
## only "resting" state it hands control to) honest.
func _on_source_animation_finished(anim_name: String) -> void:
	if anim_name == _death_animation_key:
		return
	if anim_name != _idle_animation_key and anim_name != _walk_animation_key and anim_name != _dying_animation_key:
		_play_source_animation(_idle_animation_key)

## `anim_name` is the bare clip name (e.g. "Idle_Loop"); returns the exact key
## `AnimationPlayer.play()`/`has_animation()` need, which may be namespaced
## under a library ("somelib/Idle_Loop") -- or "" if no match exists at all.
func _resolve_animation_name(player: AnimationPlayer, anim_name: String) -> String:
	for candidate in player.get_animation_list():
		if candidate == anim_name or candidate.ends_with("/" + anim_name):
			return candidate
	return ""

func _play_source_animation(anim_key: String) -> void:
	if anim_key != "" and _anim_source_player and _anim_source_player.current_animation != anim_key:
		_anim_source_player.play(anim_key)

func _process(_delta: float) -> void:
	if not (_character_skeleton and _anim_source_skeleton):
		return
	for char_idx in _bone_map:
		var source_idx: int = _bone_map[char_idx]
		var is_root := _character_skeleton.get_bone_parent(char_idx) == -1
		# Position is only copied for a ROOT bone (no parent) -- that's what carries
		# the animation's own overall body movement/bob. Every OTHER bone's local
		# position is really just its own fixed rest-pose bone length/offset from
		# its parent; copying the SOURCE skeleton's position onto a DIFFERENTLY-
		# PROPORTIONED target bone displaces it to the wrong relative location.
		# Harmless (near-identical proportions) for a same-family pair (hero/
		# monster's own model <-> Quaternius, skeleton <-> KayKit's own animation
		# library) -- confirmed live to actually break the first genuinely
		# cross-rig pair this project has tried (a Meshy-rigged model driven by
		# Quaternius's UAL1, via bone_name_map): the Barbarian collapsed into a
		# crumpled heap the first time this copied position for every bone.
		if is_root:
			_character_skeleton.set_bone_pose_position(char_idx, _anim_source_skeleton.get_bone_pose_position(source_idx))
		# Rotation is copied for every bone EXCEPT the root. _ground_model()'s own
		# doc comment already documents that this project's rigs carry a baked
		# root-bone rotation that varies per model (a Z-up/Y-up export-tool
		# artifact) -- copying the SOURCE root's rotation onto a target root with a
		# DIFFERENT baked convention doesn't animate the body, it tips the entire
		# rigid hierarchy over as one unit (confirmed live: the crumpled-heap fix
		# above produced an anatomically correct but fully prone body next, exactly
		# what a wrong root rotation looks like -- everything below the root stays
		# internally consistent since child rotations are parent-relative, only the
		# whole thing's absolute orientation is wrong). Leaving the root's own
		# rotation alone (whatever this specific model's rest pose already has,
		# upright) while still copying every child bone's relative rotation is what
		# actually conveys the animation's limb movement without also inheriting a
		# foreign skeleton's own root convention.
		if not is_root:
			_character_skeleton.set_bone_pose_rotation(char_idx, _anim_source_skeleton.get_bone_pose_rotation(source_idx))

## Shifts `instance` up/down so the lowest point of its actual rendered
## geometry sits exactly at this token's own ground level (y=0 in ModelRoot's
## local space, which has no offset of its own -- see the class comment).
##
## Deliberately NOT relying on the model file's own raw mesh vertex bounds --
## a first attempt at this trusted glTF accessor min/max values read directly
## from the file (feet at ~y=0 in mesh-local space) and still rendered
## floating in Godot. The actual cause: both character rigs used here have a
## skeleton root bone with a baked-in -90 degree rotation (a Z-up/Y-up
## conversion artifact from whatever tool exported them), which changes a
## skinned mesh's final bind-pose position in a way raw accessor data alone
## doesn't capture -- reproducing that math by hand for every differently
## authored rig would be fragile. Measuring the actual instantiated node's
## real AABB after Godot has already resolved the skin is robust regardless of
## why a given model doesn't start at its own local origin.
func _ground_model(instance: Node3D) -> void:
	var lowest_y := INF
	for visual in instance.find_children("*", "VisualInstance3D", true, false):
		var mesh_instance := visual as VisualInstance3D
		var aabb: AABB = mesh_instance.get_aabb()
		for i in range(8):
			var world_corner: Vector3 = mesh_instance.global_transform * aabb.get_endpoint(i)
			lowest_y = min(lowest_y, world_corner.y)
	if is_finite(lowest_y):
		instance.position.y -= lowest_y

## Plain colored capsule -- Phase 0's original placeholder, now only used when
## the real model for this token type isn't available (see the class comment).
func _add_fallback_capsule() -> void:
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = FALLBACK_CAPSULE_RADIUS
	capsule.height = FALLBACK_CAPSULE_HEIGHT
	mesh_instance.mesh = capsule
	mesh_instance.position = Vector3(0, FALLBACK_CAPSULE_HEIGHT / 2.0, 0)
	mesh_instance.material_override = StandardMaterial3D.new()
	_model_root.add_child(mesh_instance)
	_fallback_mesh = mesh_instance

## Unlike a real model (which keeps its own textures untouched -- a real
## model's "dead" look is a later phase), the fallback capsule tints grey at 0
## HP. Runs every apply_data() call (cheap -- just a material color write), not
## only when the model is first built, so HP dropping to 0 later in play still
## updates it without needing a full model rebuild.
func _update_fallback_color() -> void:
	if not _fallback_mesh:
		return
	var color := Color(0.30, 0.52, 0.92) if token_type == "hero" else Color(0.82, 0.24, 0.22)
	if hp <= 0:
		color = Color(0.28, 0.28, 0.28)
	(_fallback_mesh.material_override as StandardMaterial3D).albedo_color = color

## Scales HPBarFillWrapper (not the mesh directly) so the bar drains from the
## right while its LEFT edge stays fixed -- the wrapper sits at the bar's own
## left edge with the fill mesh offset by half its width inside it, so
## scaling the wrapper's X moves the mesh's rendered right edge only. Color
## bands (green/yellow/red) are the same rough thresholds a lot of games use;
## nothing SRD-specific about the exact cutoffs.
func _update_hp_bar() -> void:
	var ratio: float = clamp(float(hp) / float(max(max_hp, 1)), 0.0, 1.0)
	_hp_bar_fill_wrapper.scale.x = ratio
	var color: Color
	if ratio > 0.5:
		color = Color(0.2, 0.8, 0.2)
	elif ratio > 0.25:
		color = Color(0.9, 0.75, 0.15)
	else:
		color = Color(0.85, 0.2, 0.2)
	(_hp_bar_fill.material_override as StandardMaterial3D).albedo_color = color

func set_selected(is_selected: bool) -> void:
	_selection_ring.visible = is_selected

func _animate_to(target: Vector3) -> void:
	if _move_tween:
		_move_tween.kill()
	_play_source_animation(_walk_animation_key)
	_face_direction(target - position)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, 0.35).set_trans(Tween.TRANS_SINE)
	_move_tween.finished.connect(_resume_idle_or_dying)

## A moved token's walk cycle (started in _animate_to) hands back to idle when
## the move finishes -- except a token that's down making death saves (or
## stabilized) should settle back into its kneeling pose instead of popping
## back onto its feet. An edge case in practice (a dying creature isn't
## usually the one being repositioned), but a DM could still drag one, and
## standing it up mid-tween-finish would look wrong for however long it stays
## dying.
func _resume_idle_or_dying() -> void:
	if _was_dying:
		_play_source_animation(_dying_animation_key)
	else:
		_play_source_animation(_idle_animation_key)

## Turns the whole token (an instant snap-turn, then the position tween moves
## it -- not a smooth turn-while-walking, a deliberately simpler first cut) to
## face the direction it's about to move. Uses Node3D's own look_at() rather
## than hand-derived trig specifically to remove one whole class of mistake
## this project has already hit more than once this phase (getting an axis/
## sign wrong by reasoning about it instead of using a well-tested built-in).
##
## The `+ PI` matters and is not arbitrary: look_at() points the node's local
## -Z at the target, but this specific model's authored "forward" turned out
## to be +Z instead -- confirmed by testing (without it, tokens correctly
## turned to face their destination but then visibly walked backward toward
## it, exactly what facing 180 degrees off looks like with a walk cycle
## playing). If a future model swap ever walks backward again, this is the
## line to revisit.
func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	look_at(global_position + direction, Vector3.UP)
	rotation.y += PI
