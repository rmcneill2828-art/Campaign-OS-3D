extends Node3D
class_name DiceRollVisual
## Item 2 of ROADMAP.md's "Seven requested features" (2026-09-19) -- a single
## tumbling physical die that settles and reveals a REAL, already-decided result.
## The actual outcome always comes from the server (Main.gd extracts it straight out
## of encounter.js's own roll message via _extract_d20_rolls() -- see that function's
## own doc comment for why parsing text is the right call here rather than changing
## the shared engine), never from this object's own physics. The physics tumble is
## purely a visual flourish matching how a real d20 lands on a table, not a second,
## competing source of truth for what the roll actually was -- letting physics itself
## decide the outcome would risk a client-side result that disagrees with what the
## server already rolled and applied.
##
## Not modeled as a literal numbered d20 mesh -- a real per-face-labeled polyhedron is
## an asset-creation task, not a code one, and this project's own static-models-only
## decision (see Token.gd's class doc comment) already deliberately keeps this kind of
## bespoke-asset work out of scope for now. A plain cube tumbles/bounces physically
## for the "something is rolling" feel, and the actual number reveals via a big
## floating Label3D once it settles -- the same "tumble, then reveal the true number"
## technique most digital tabletop tools use, for exactly this reason.

const SETTLE_SECONDS := 1.1
const LINGER_SECONDS := 2.0
const CUBE_SIZE := 0.35

var _body: RigidBody3D
var _label: Label3D
var _result: int
var _elapsed := 0.0
var _settled := false

## `origin` -- where to spawn/toss the die from (world space, typically just above
## the rolling token). `color` distinguishes multiple dice shown together (e.g. an
## advantage/disadvantage pair) -- see Main.gd's own _spawn_dice().
func start(result: int, origin: Vector3, color: Color = Color.WHITE) -> void:
	_result = result
	position = origin

	_body = RigidBody3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CUBE_SIZE
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	_body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * CUBE_SIZE
	collision.shape = shape
	_body.add_child(collision)
	add_child(_body)

	# A real random toss, not a scripted flight path -- purely cosmetic (see class doc
	# comment), so an actual physics impulse/spin reads as more natural than a canned
	# animation, with zero risk of disagreeing with the real result since the result is
	# never read FROM this physics at all. Lands on the same invisible floor collision
	# GridManager already builds for click-to-move raycasting -- no extra setup needed.
	_body.linear_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 3.0), randf_range(-1.0, 1.0))
	_body.angular_velocity = Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))

	_label = Label3D.new()
	_label.text = str(_result)
	_label.font_size = 48
	_label.modulate = Color(1, 1, 1, 0) # invisible until it settles
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 0.6, 0)
	_body.add_child(_label)

func _process(delta: float) -> void:
	if _settled:
		return
	_elapsed += delta
	if _elapsed >= SETTLE_SECONDS:
		_settle()

func _settle() -> void:
	_settled = true
	_body.freeze = true # the tumble is over -- the number is now fixed, no further physics should move it
	var tween := create_tween()
	tween.tween_property(_label, "modulate:a", 1.0, 0.15)
	# Disappear a couple seconds after settling so old rolls don't clutter the board.
	await get_tree().create_timer(LINGER_SECONDS).timeout
	queue_free()
