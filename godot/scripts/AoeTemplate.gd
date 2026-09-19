extends RefCounted
class_name AoeTemplate
## Ports engine-server/engine/encounter.js's own pointInCircle/pointInCone/pointInLine AoE
## shape math to GDScript, plus the 2D app's own templateCoveredTokenNames() wrapper
## (ui/app.js) -- the two live in different languages with no shared-module mechanism
## between them, same "duplicated by hand" convention this project already uses for
## ABILITY_KEYS/SKILL_LIST/etc. (see Main.gd's own class doc comment on those). See
## ROADMAP.md's "Seven requested features" 2026-09-19 entry, item 7: the shape
## PRIMITIVES were already shared-engine-side (encounter.js, already copied verbatim
## into engine-server/), but the higher-level "which tokens does this shape actually
## cover" wrapper turned out to be 2D-UI-side only (ui/app.js), so it needed porting
## here, not just wiring up.
##
## Coordinate convention matches encounter.js's own vertex-space exactly: a cell's
## center sits at (index - 0.5, index - 0.5) in "cell units" (NOT world meters, NOT
## the 1-indexed integer cell coordinates token.x/token.y use directly) -- callers
## convert to/from world space (GridManager.cell_size) and to/from feet
## (GridManager.feet_per_square) at their own boundary, same layering the JS side
## documents for itself. Conveniently, GridManager.cell_to_world(x, y) is exactly
## `Vector3((x - 0.5) * cell_size, 0, (y - 0.5) * cell_size)` -- so a world position
## divided by cell_size IS a cell-unit coordinate already, no separate offset needed
## (see Main.gd's own use of this).

## Angle convention: 0 = +x, increasing the same direction Godot's own atan2(dz, dx)
## on two cell-unit points already produces -- self-consistent with how Main.gd
## derives a live drag angle, so unlike the 2D app (which has to lean on "screen pixels
## and real angles agree because the grid is square") this doesn't need that assumption
## at all: it's real angles from real world-space raycasts throughout.
static func point_in_circle(px: float, py: float, center_x: float, center_y: float, radius_cells: float) -> bool:
	return Vector2(px - center_x, py - center_y).length() <= radius_cells

## RAW cone geometry (SRD): "the cone's width at a given point along its length is
## equal to that point's distance from the point of origin" -- a true triangle (apex +
## two straight edges), not a circular sector. `angle_rad` is the cone's own centerline
## direction. Rotates the point into the cone's own reference frame (origin at the
## apex, axis along +x) rather than testing against two separately-angled edges --
## same technique point_in_line uses below.
static func point_in_cone(px: float, py: float, apex_x: float, apex_y: float, angle_rad: float, length_cells: float) -> bool:
	var dx := px - apex_x
	var dy := py - apex_y
	var c := cos(-angle_rad)
	var s := sin(-angle_rad)
	var local_x := dx * c - dy * s
	var local_y := dx * s + dy * c
	if local_x < 0.0 or local_x > length_cells:
		return false
	return abs(local_y) <= local_x / 2.0

## A line "originates from a point ... and extends [length] in a certain direction,
## with a total length you choose" (RAW) at a caller-supplied width (5 ft for most
## line spells, but not hardcoded here -- it's a per-spell UI input, not a rules
## constant the way the cone's implicit angle is).
static func point_in_line(px: float, py: float, origin_x: float, origin_y: float, angle_rad: float, length_cells: float, width_cells: float) -> bool:
	var dx := px - origin_x
	var dy := py - origin_y
	var c := cos(-angle_rad)
	var s := sin(-angle_rad)
	var local_x := dx * c - dy * s
	var local_y := dx * s + dy * c
	return local_x >= 0.0 and local_x <= length_cells and abs(local_y) <= width_cells / 2.0

## Mirrors ui/app.js's own templateShapeCells() -- builds the actual placed shape (a
## circle, or a cone/line polygon) from the current placement state. `origin` and the
## returned points are all in cell units (see class doc comment above).
##
## Returns a Dictionary: {"kind": "circle", "center": Vector2, "radius_cells": float}
## or {"kind": "polygon", "points": Array[Vector2]} (3 points for a cone's triangle, 4
## for a line's rectangle).
static func shape_cells(shape_name: String, origin: Vector2, angle_rad: float, length_cells: float, width_cells: float) -> Dictionary:
	if shape_name == "circle":
		return {"kind": "circle", "center": origin, "radius_cells": length_cells}

	var dir := Vector2(cos(angle_rad), sin(angle_rad))
	var perp := Vector2(-sin(angle_rad), cos(angle_rad))
	var far := origin + dir * length_cells

	if shape_name == "cone":
		# RAW: half-width at the far end equals half the cone's own length (see
		# point_in_cone's own doc comment -- width = distance along the length).
		var half_width := length_cells / 2.0
		return {"kind": "polygon", "points": [origin, far + perp * half_width, far - perp * half_width]}

	# line
	var half_w := width_cells / 2.0
	return {
		"kind": "polygon",
		"points": [
			origin + perp * half_w,
			far + perp * half_w,
			far - perp * half_w,
			origin - perp * half_w
		]
	}

## Mirrors ui/app.js's own templateCoveredTokenNames() -- every token (as a
## {"name": String, "x": int, "y": int} dict, 1-indexed grid cells, matching
## token.x/token.y's own convention) whose cell center falls inside the current
## template shape. `shape_name`/`origin`/`angle_rad`/`length_cells`/`width_cells` are
## the same placement fields shape_cells() takes, passed straight through rather than
## re-deriving them from `shape` itself -- point_in_cone/point_in_line need the raw
## apex/origin + angle directly, not just the already-built polygon's own vertices
## (matching ui/app.js's own reasoning for why it recomputes originCell separately
## rather than reading it back off shape.points).
static func covered_token_names(tokens: Array, shape_name: String, origin: Vector2, angle_rad: float, length_cells: float, width_cells: float) -> Array[String]:
	var names: Array[String] = []
	for token in tokens:
		var px: float = float(token.get("x", 1)) - 0.5
		var py: float = float(token.get("y", 1)) - 0.5
		var covered := false
		if shape_name == "circle":
			covered = point_in_circle(px, py, origin.x, origin.y, length_cells)
		elif shape_name == "cone":
			covered = point_in_cone(px, py, origin.x, origin.y, angle_rad, length_cells)
		else:
			covered = point_in_line(px, py, origin.x, origin.y, angle_rad, length_cells, width_cells)
		if covered:
			names.append(str(token.get("name", "")))
	return names
