extends Node3D
class_name Token
## One 3D miniature. Deliberately dumb -- it only renders whatever `apply_data()`
## is given each poll and reports its own click via the "Body" StaticBody3D's group
## membership; Main.gd owns all selection/movement decisions and talks to the
## server.
##
## Model loading is intentionally NOT preload() -- real creature models are
## licensed for use but NOT committed to this git repo (see godot/assets/
## README.md: their license permits using them in a game, but not
## redistributing the raw asset files themselves, which committing them to a
## repo would risk). A fresh clone without those files re-downloaded must
## still open and run -- just with the plain colored-capsule placeholder Phase 0
## shipped with -- rather than fail to load the scene at all. `load()` +
## `ResourceLoader.exists()` achieves that; `preload()` would not.

## PROJECT DECISION (2026-09-17, see ROADMAP.md's own entry for the full
## reasoning): every token is now a STATIC model -- no skeletal animation,
## no `animation_source`, no bone-name-map/retargeting machinery. Animation
## is deliberately deferred to a future version, after a stable/playable/
## presentable VTT exists on static models first -- a call made only after
## the Barbarian's own three-pipeline animation saga showed what animating
## even ONE humanoid actually costs, with a real campaign needing dozens of
## creatures and the full SRD bestiary running to hundreds.
##
## The FULL working animation system this project already built (rest-pose-
## relative bone retargeting, Meshy/Mixamo bone-name maps, per-clip import
## across separate animation-source files, death/dying/hit-reaction state
## machine) is preserved, not deleted -- see
## _archive/animation-system-2026-09-17/Token.gd.txt at the repo root (one
## directory above godot/, so Godot's own project scanner never sees it --
## a second `class_name Token` inside the scanned project would conflict
## with this file). Reintroducing animation for a future version means
## restoring that file's logic, not rebuilding it from scratch. The
## MODEL_CONFIG entries that used to reference it (hero, monster,
## monster:skeleton, monster:orc, hero:barbarian) were removed entirely per
## this decision, not just their animation fields -- every token falls back
## to the plain placeholder capsule until a static replacement model is
## sourced for each one.
##
## Lookup key -> a "model family" config: which model to instance, and
## where its name/HP label floats (label_height, meters above its own feet
## -- whatever vertical offset the model actually needs to stand on the
## floor is figured out at runtime regardless, see _ground_model()). A
## model with its own built-in display base (e.g. a 3D-printed-miniature-
## style asset) is fine -- _ground_model() grounds any mesh shape correctly
## regardless of whether the lowest point is a foot or a sculpted base.
##
## Keys are either a bare token type ("hero", "monster" -- the fallback used
## when no more specific entry matches) or "monster:<stat-block name>"
## (lowercased, e.g. "monster:skeleton") for a real per-monster-name model --
## see _stat_block_key() and _rebuild_model()'s own lookup order.
const MODEL_CONFIG := {}
const FALLBACK_LABEL_HEIGHT := 1.9
const FALLBACK_CAPSULE_RADIUS := 0.4
const FALLBACK_CAPSULE_HEIGHT := 1.6

## "Painted tabletop miniature" material finish (2026-09-18) -- applied to
## every loaded model in _apply_miniature_finish() and to the fallback
## capsule in _add_fallback_capsule(), so a static download's own PBR finish
## (often glossier/flatter than a real painted mini) reads consistently
## across every source pack (Meshy, KayKit, Quaternius, Sketchfab...)
## without hand-tuning each asset individually -- see that function's own
## doc comment for why this has to run per-instance in code rather than as a
## one-off Inspector edit. ROUGHNESS gives a soft matte-plastic finish
## instead of a glossy one; RIM/RIM_TINT catches edge lighting off the
## scene's own angled DirectionalLight3D ("Sun" in Main.tscn), mimicking how
## a real miniature's paint catches overhead room light.
const MINIATURE_ROUGHNESS := 0.4
const MINIATURE_RIM := 0.5
const MINIATURE_RIM_TINT := 0.3

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

var _initialized := false
var _move_tween: Tween
# Set only while the fallback capsule is the active visual (null once a real
# model is loaded) -- lets HP-driven color react every poll without rebuilding
# the whole model tree each time (see _update_fallback_color below).
var _fallback_mesh: MeshInstance3D

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
	_last_hp = hp

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

## Item 3 of ROADMAP.md's "Seven requested features" (2026-09-19) -- lets
## CharacterViewer.gd swap in an already-instantiated model (e.g. a runtime-loaded
## external glTF file it just parsed, previewing a candidate before it's actually
## wired into MODEL_CONFIG) through the exact same grounding/miniature-finish
## treatment _rebuild_model() below gives a real MODEL_CONFIG entry, so a preview
## looks exactly like what wiring that file in for real would produce -- not a
## simplified re-derivation of that same logic. Bypasses MODEL_CONFIG/token_type
## entirely; a later real apply_data() call rebuilds over it the usual way.
func preview_external_model(instance: Node3D) -> void:
	for child in _model_root.get_children():
		child.queue_free()
	_fallback_mesh = null
	# queue_free() above only SCHEDULES removal (at the next idle frame) -- if
	# `instance` was itself already a child of _model_root (a repeat preview of the
	# same override after a poll tick rebuilt something else in between), it's still
	# nominally attached at this exact point, and add_child() below would reject it
	# ("already has a parent"). remove_child() is synchronous, so this makes calling
	# this function safe regardless of instance's current parenting state, not just
	# on a fresh never-parented node.
	if instance.get_parent():
		instance.get_parent().remove_child(instance)
	_model_root.add_child(instance)
	_ground_model(instance)
	_apply_miniature_finish(instance)

func _rebuild_model() -> void:
	for child in _model_root.get_children():
		child.queue_free()
	_fallback_mesh = null

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
		_apply_miniature_finish(instance)
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

## Shifts `instance` up/down so the lowest point of its actual rendered
## geometry sits exactly at this token's own ground level (y=0 in ModelRoot's
## local space, which has no offset of its own -- see the class comment).
##
## Deliberately NOT relying on the model file's own raw mesh vertex bounds --
## a first attempt at this trusted glTF accessor min/max values read directly
## from the file (feet at ~y=0 in mesh-local space) and still rendered
## floating in Godot. The actual cause: character rigs seen here can have a
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

## Gives `instance` a consistent "painted tabletop miniature" finish
## (MINIATURE_ROUGHNESS/RIM/RIM_TINT above) regardless of which pack/
## generator it came from -- runs on a DUPLICATE of each surface's own
## active material (get_active_material(), which resolves whatever the
## imported model is actually rendering with -- StandardMaterial3D or
## ORMMaterial3D, both BaseMaterial3D, both carrying roughness/rim), never
## the imported resource itself. Duplicating first matters for the same
## reason _ready() builds a fresh HP-bar material per instance rather than
## mutating a shared one: Godot's ResourceLoader caches/shares a model
## file's materials across every instance of it, so tweaking one in place
## would silently reskin every OTHER token using that same model too, not
## just this one. Only the roughness/rim are touched -- albedo, its texture,
## and every other property (normal maps, transparency, etc.) carry over
## from the original untouched, since duplicate() copies the whole material
## first.
func _apply_miniature_finish(instance: Node3D) -> void:
	for visual in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := visual as MeshInstance3D
		if not mesh_instance.mesh:
			continue
		for surface_idx in range(mesh_instance.mesh.get_surface_count()):
			var base_material := mesh_instance.get_active_material(surface_idx)
			if not (base_material is BaseMaterial3D):
				continue # e.g. a ShaderMaterial -- nothing safe to tweak generically
			var tweaked := (base_material as BaseMaterial3D).duplicate() as BaseMaterial3D
			tweaked.roughness = MINIATURE_ROUGHNESS
			tweaked.rim_enabled = true
			tweaked.rim = MINIATURE_RIM
			tweaked.rim_tint = MINIATURE_RIM_TINT
			mesh_instance.set_surface_override_material(surface_idx, tweaked)

## Plain colored capsule -- Phase 0's original placeholder, now only used when
## the real model for this token type isn't available (see the class comment).
## Carries the same MINIATURE_ROUGHNESS/RIM finish as a real model (see
## _apply_miniature_finish()) so a token without a sourced model yet still
## looks visually consistent with ones that have one, not glossier/flatter.
func _add_fallback_capsule() -> void:
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = FALLBACK_CAPSULE_RADIUS
	capsule.height = FALLBACK_CAPSULE_HEIGHT
	mesh_instance.mesh = capsule
	mesh_instance.position = Vector3(0, FALLBACK_CAPSULE_HEIGHT / 2.0, 0)
	var material := StandardMaterial3D.new()
	material.roughness = MINIATURE_ROUGHNESS
	material.rim_enabled = true
	material.rim = MINIATURE_RIM
	material.rim_tint = MINIATURE_RIM_TINT
	mesh_instance.material_override = material
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
	_face_direction(target - position)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, 0.35).set_trans(Tween.TRANS_SINE)

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
