extends Node3D
class_name CameraRig
## A simple orbit/pan/zoom rig over the board -- right-drag to orbit, middle-drag
## to pan, wheel to zoom. Deliberately conservative angle clamps (never looks
## straight down, never dips below the horizon) so the board stays readable, the
## same spirit as a real tabletop DM leaning over a table rather than a free
## first-person camera. Tune the @export values in the editor to taste.

@export var min_distance := 6.0
@export var max_distance := 40.0
@export var min_pitch_deg := 20.0
@export var max_pitch_deg := 85.0
@export var orbit_sensitivity := 0.25 ## degrees of rotation per pixel of mouse motion
@export var pan_sensitivity := 0.02 ## world units per pixel of mouse motion
@export var zoom_step := 1.5

@onready var camera: Camera3D = $Camera3D

var distance := 16.0
var yaw_deg := 45.0
var pitch_deg := 55.0

var _orbiting := false
var _panning := false

func _ready() -> void:
	_apply_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clamp(distance - zoom_step, min_distance, max_distance)
			_apply_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clamp(distance + zoom_step, min_distance, max_distance)
			_apply_transform()
	elif event is InputEventMouseMotion:
		if _orbiting:
			yaw_deg -= event.relative.x * orbit_sensitivity
			pitch_deg = clamp(pitch_deg - event.relative.y * orbit_sensitivity, min_pitch_deg, max_pitch_deg)
			_apply_transform()
		elif _panning:
			var yaw_rad := deg_to_rad(yaw_deg)
			var right := Vector3(cos(yaw_rad), 0, -sin(yaw_rad))
			var forward := Vector3(sin(yaw_rad), 0, cos(yaw_rad))
			position -= right * event.relative.x * pan_sensitivity
			position += forward * event.relative.y * pan_sensitivity
			_apply_transform()

func _apply_transform() -> void:
	var yaw_rad := deg_to_rad(yaw_deg)
	var pitch_rad := deg_to_rad(pitch_deg)
	var horizontal := cos(pitch_rad) * distance
	camera.position = Vector3(
		horizontal * sin(yaw_rad),
		sin(pitch_rad) * distance,
		horizontal * cos(yaw_rad)
	)
	camera.look_at(global_position, Vector3.UP)

## Re-centers the rig's pivot (and re-derives the camera transform around it) --
## called once by Main.gd as soon as the board's real size is known from the server.
func center_on(point: Vector3) -> void:
	position = point
	_apply_transform()
