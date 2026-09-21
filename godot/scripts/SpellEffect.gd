extends Node3D
class_name SpellEffect
## Item 6 of ROADMAP.md's "Seven requested features" (2026-09-19) -- Spell effects.
## Before this, cast_spell/cast_area_spell were purely mechanical in this client: dice,
## an HP change, one log line, zero particle/shader feedback. A one-shot GPUParticles3D
## burst, colored by the cast's own damageType (or a neutral arcane color when none was
## given), at the caster's position always and the target's position on an actual hit --
## triggered off the same /action response Main.gd's own _try_show_dice_roll already
## reacts to, matching the "presentation reacts to already-decided server state" split
## ARCHITECTURE.md documents. Purely cosmetic -- like DiceRollVisual, this never decides
## or reports back any real outcome, only shows one that already happened.
##
## Cleanup is a manually-accumulated `_process(delta)` timer, the exact same pattern
## DiceRollVisual's own SETTLE_SECONDS/LINGER_SECONDS use -- deliberately NOT
## GPUParticles3D's own `finished` signal (only emitted once the node's real particle
## simulation completes, which needs an actual non-dummy rendering backend; a
## `--headless` smoke-test run, this project's own convention, may never fire it at all,
## leaking every effect spawned during such a run) and deliberately NOT
## `get_tree().create_timer(...)` either (real wall-clock-driven, so a headless test
## script can't deterministically fast-forward past it the way DiceRollVisual's own test
## does with a single large `_process(5.0)` call -- see test_spell_effect.gd's own
## `_test_visual`).

const LIFETIME_SECONDS := 0.6
const CLEANUP_BUFFER_SECONDS := 0.3
const PARTICLE_AMOUNT := 24
const BURST_SIZE := 0.12

var _particles: GPUParticles3D
var _color: Color
var _elapsed := 0.0
var _freed := false

## `origin` -- world position to burst at (caster or target, both offset upward by the
## caller so the effect reads at roughly chest height, not floor level). `rise` -- true
## for effects that read as "hot"/upward (fire, radiant): particles drift up instead of
## scattering outward on all axes. `big` -- true for a confirmed critical hit: a larger,
## denser burst, same "make the rare, exciting outcome visually bigger" precedent
## DiceRollVisual's own advantage/disadvantage color-coding follows for a different roll.
func start(color: Color, origin: Vector3, rise: bool = false, big: bool = false) -> void:
	_color = color
	position = origin

	_particles = GPUParticles3D.new()
	_particles.emitting = false # set true only after every property below is configured
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.amount = PARTICLE_AMOUNT * (2 if big else 1)
	_particles.lifetime = LIFETIME_SECONDS

	var mesh := SphereMesh.new()
	mesh.radius = BURST_SIZE * (1.4 if big else 1.0)
	mesh.height = mesh.radius * 2.0
	_particles.draw_pass_1 = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0, 1, 0) if rise else Vector3(0, 0, 0)
	process_material.spread = 15.0 if rise else 180.0
	process_material.initial_velocity_min = 1.0 * (1.5 if big else 1.0)
	process_material.initial_velocity_max = 2.5 * (1.5 if big else 1.0)
	process_material.gravity = Vector3(0, -1.0 if rise else 0.0, 0)
	process_material.scale_min = 0.4
	process_material.scale_max = 1.0
	process_material.color = color
	_particles.process_material = process_material

	add_child(_particles)
	_particles.emitting = true

func _process(delta: float) -> void:
	if _freed:
		return
	_elapsed += delta
	if _elapsed >= LIFETIME_SECONDS + CLEANUP_BUFFER_SECONDS:
		_freed = true
		queue_free()
