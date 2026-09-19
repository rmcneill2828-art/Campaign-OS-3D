# Tools

Headless Godot scripts, run via `--headless --path godot --script res://tools/<name>.gd`
against a real Godot 4.7.2 executable -- not part of the running game, and not
referenced by anything in `scenes/`/`scripts/`. Useful whenever a change needs
checking without a live `node server.js` or opening the editor GUI.

- **`measure_pieces.gd`** -- instantiates a list of asset pieces and prints
  each one's real, Godot-resolved AABB (size + how far its origin sits from
  its own lowest/highest point). Same "measure the real thing, don't trust
  the file's claimed bounds" discipline `GridManager.gd`/`Token.gd` already
  rely on at runtime -- this is that same technique, run once at
  map-authoring time instead of every frame, so a new piece's real placement
  offset is known before it goes into a map scene rather than guessed and
  fixed after a screenshot. Edit its `PIECES` list to measure something new.
- **`build_prototype_chamber.gd`** -- generated `scenes/maps/prototype_chamber.tscn`
  (see that scene's own history in `ROADMAP.md`'s Phase 4 entry) by placing
  real Kenney dungeon-kit pieces cell-by-cell and saving the result with
  `PackedScene.pack()` + `ResourceSaver.save()`. Still a genuinely
  hand-authored map in the sense the Phase 3+ planning pass meant -- every
  wall/door/prop position is an explicit, human-made layout decision baked
  into this one script -- just placed via a script instead of the editor's
  mouse-and-gizmo workflow (not drivable interactively in this session). A
  second hand-built map is a copy of this pattern: a new script with its own
  explicit layout, run once to produce a new committed `.tscn`.
- **`smoke_test_main.gd`** / **`smoke_test_player_view.gd`** -- instantiate
  `Main.tscn`/`PlayerView.tscn` headlessly and confirm they load/`_ready()`
  with no script error (no live `engine-server` needed -- HTTPRequest calls
  just fail to connect, which is fine). A cheap regression check after
  editing any of the scripts either scene uses, before ever opening the
  real editor.
- **Animation-era tools archived, not deleted** (2026-09-17 project
  decision -- see `ROADMAP.md`'s own entry and the PROJECT DECISION comment
  atop `Token.gd`: every token is now a static model, no skeletal
  animation). `inspect_kaykit_skeleton.gd`, `inspect_meshy_orc.gd`,
  `inspect_bone_name_map.gd`, and the `test_skeleton_token.gd`/`.tscn`,
  `test_imp_token.gd`/`.tscn`, `test_orc_token.gd`/`.tscn` functional checks
  all verified pieces of the bone-retargeting/animation-resolution system
  `Token.gd` no longer has -- each now references `Token` fields (e.g.
  `_death_animation_key`, `_bone_map`) that don't exist on the live,
  simplified script, so running any of them as-is would error. Moved to
  `_archive/animation-system-2026-09-17/tools/` (one directory above
  `godot/`, outside Godot's own project scan, each renamed with a trailing
  `.txt`) alongside the full pre-refactor `Token.gd` they were built to
  verify -- see that archive folder's own `README.md` for what each did and
  how to restore them if animation comes back in a future version.

- **`inspect_higgsfield_test.gd`** / **`fix_higgsfield_vertex_colors.gd`**
  (Phase 8) -- a matched pair for Higgsfield's "3D Jutsu" catalog imports.
  The inspector measures real size (same AABB discipline as
  `measure_pieces.gd`) and checks for a texture; the fix tool exists because
  that check turned up a real, confirmed bug (not assumed from the flat
  look alone -- a separate throwaway script dumped the mesh's own
  `ARRAY_COLOR` data directly and found real, varied colors underneath):
  every 3D Jutsu GLB export carries genuine per-vertex color data, but
  Godot's glTF importer leaves the resulting `StandardMaterial3D`'s
  `vertex_color_use_as_albedo` false, so that color is silently never
  rendered -- everything comes in looking flat white regardless of its
  real intended color. The fix tool assigns each mesh surface a fresh
  `material_override` (never mutating the imported resource's own shared
  material) with that flag corrected, then re-saves the result as a
  `.tscn` -- **not** a `.glb`: `ResourceSaver.save()` only writes
  Godot-native formats, re-exporting an actual `.glb` needs the separate
  `GLTFDocument` API instead, which this fix didn't need. A `.tscn`
  referencing the original glTF's meshes plus the corrected material loads
  from `Token.gd`/`GridManager.gd` exactly like a plain `.glb` would.
  Re-run both for any future Higgsfield catalog import -- this is very
  likely a pipeline-wide issue, not specific to the 3 pieces tested so far.

- **`measure_higgsfield_dungeon.gd`** / **`build_entrance_hall.gd`** (Phase
  4/8) -- the same measure-then-build pattern as `measure_pieces.gd` +
  `build_prototype_chamber.gd`, applied to the second hand-built map,
  "Entrance Hall" (`scenes/maps/entrance_hall.tscn`), using 8 Higgsfield "3D
  Jutsu" pieces (the vertex-color-fixed `.tscn` versions -- see
  `fix_higgsfield_vertex_colors.gd` above) instead of Kenney's kit. The
  measure tool confirmed Higgsfield's modules are natively 4m x 4m, exactly
  2x2 of this project's own 2m grid cells, before any placement math was
  written. The build tool composes a self-contained arch-doorway entrance
  and straight-corridor tunnel (each already walled on its own, no separate
  wall pieces needed) leading into a 2x2-module room built from separate
  floor/wall/corner pieces, with a doorway left open in the one wall
  segment that actually faces the corridor. See `ROADMAP.md`'s Phase 4
  entry for the full layout, the known corner-rotation/torch-mounting
  guesses still awaiting a live look, and the accepted "L-shaped void" gap
  where the narrower tunnel meets the wider room.
  **`measure_higgsfield_dungeon.gd` is on its 2nd version** -- its first
  version trusted `global_transform` directly and got every single one of
  the 8 pieces' Y-offsets wrong (see the fourth gotcha below); it now
  manually composes each mesh's real world transform instead of trusting
  the cache, which is the only version of this tool that should ever be
  copied as a template again.
- **`smoke_test_entrance_hall.gd`** -- confirms `MapScenes.resolve("Entrance
  Hall")` resolves to a real path and that `entrance_hall.tscn` loads with
  exactly the 21 nodes `build_entrance_hall.gd` is expected to produce, the
  same regression-check role `smoke_test_main.gd`/`smoke_test_player_view.gd`
  play for their own scenes.

**Second gotcha: a bare `--script` `SceneTree` tool's `_init()` runs before
any manually `add_child()`-ed node has had a real `_ready()`/`NOTIFICATION_ENTER_TREE`
pass.** A `Node3D`'s `global_transform` silently reads back as identity
(not an error -- just wrong) when queried this early, and a `Token`'s own
`@onready var _label` etc. are still null, which crashes the very first
`apply_data()` call that touches them. Neither of `measure_pieces.gd`'s or
`build_prototype_chamber.gd`'s own top-level instances actually needed a
non-identity ancestor transform or `@onready` access at the moment they
were queried, which is why this didn't surface until `test_skeleton_token.gd`
needed a real, fully-initialized `Token`. Fix: don't use a bare `--script`
tool for anything that needs a genuinely "ready" node tree -- write a small
real scene + `Node` script instead (see `test_skeleton_token.tscn`'s own
pattern: an `await get_tree().process_frame` before touching anything just
instantiated), and run it as a normal scene path instead of via `--script`.

**Update, 2026-09-19: a lighter-weight fix exists for the "smoke test" case
specifically, found the hard way.** `smoke_test_main.gd`/
`smoke_test_player_view.gd` had exactly this bug from the day they were
written -- `quit()` ran synchronously at the end of `_init()`, before
`Main.tscn`/`PlayerView.tscn`'s own `_ready()` (and every `@onready`
assignment) ever actually executed -- so despite their own doc comments
claiming to catch "a `_ready()`-time runtime error," they were only ever
catching a scene-file/parse error, for as long as they existed, without
anyone noticing (nothing they checked required `_ready()` to have run).
Confirmed directly: probing a known `_ready()`-built value came back null
right after `add_child()`, but populated by the first `_process()` tick.
Fix, without switching to a whole separate scene + `Node` file: override
`_process(delta) -> bool` on the SAME bare `--script` `SceneTree` tool, do
the real work (and call `quit()`) there instead of in `_init()`, and
`return true`. One real iteration is all `_ready()` needs, and a bare
`--script` tool gets exactly one before this fix, zero without it. This
doesn't replace the real-scene-+-`Node` approach above for anything that
needs MULTIPLE frames or genuine physics/animation settling over real
time (`test_dice_roll.gd`'s own settle-timing check instead calls
`_process(delta)` manually with a large `delta` to fast-forward past that,
rather than actually waiting) -- it only buys the first frame, but that's
enough for `_ready()`/`@onready` itself, which is all four of this
project's current `test_*.gd` scripts (`test_aoe_template.gd`,
`test_character_creator.gd`, `test_character_viewer.gd`,
`test_dice_roll.gd`) actually need.

**Third gotcha: `ResourceSaver.save()` cannot write an actual `.glb` file,
even though it happily accepts the path and only fails at the actual write.**
Passing a `.glb` destination to `ResourceSaver.save(packed_scene, path)`
fails with error 15, because `ResourceSaver` only knows Godot-native
formats (`.tscn`/`.res`/`.scn`) -- writing a real glTF/GLB binary needs the
separate `GLTFDocument` export API instead. If the goal is just "something
`load()`-able from a Godot script later" (not genuine interop with another
glTF-reading tool outside Godot), a `.tscn` destination does the job with
zero extra machinery -- see `fix_higgsfield_vertex_colors.gd`'s own use of
this.

**Fourth gotcha, and the most dangerous one found so far: in a bare
`--script` `SceneTree` tool, `MeshInstance3D.global_transform` can silently
return a WRONG (not identity, not an error -- just plausible-looking wrong)
transform for any node with real translation in its own nested wrapper
hierarchy.** This is a worse variant of the second gotcha above: that one
at least fails obviously (null `@onready` vars, identity transform on a
never-moved node). This one doesn't -- it returns SOME transform, composed
from part of the ancestor chain but not all of it, because a freshly
`add_child()`-ed node's transform doesn't get pushed down through its own
children without a real process frame, which a bare `--script` tool never
gets. Found live, the hard way: `measure_higgsfield_dungeon.gd`'s first
version measured every one of the 8 Entrance Hall pieces as flush-bottom
(`lowest.y` at or near 0) using plain `global_transform` -- every one of
those numbers looked completely plausible, `build_entrance_hall.gd` used
them to place all 8 pieces, and the generated scene loaded and smoke-tested
fine. It wasn't until tokens were spawned live in Godot (a real running
process, unaffected by this bug) and appeared to be standing at wall-TOP
height over a visibly deep, dark recess that anything looked wrong at all
-- the corridor/arch modules' real floor was actually 1.27m underground the
entire time, because those pieces are vertically CENTERED on their own
origin, not flush-bottom, and the buggy measurement couldn't see that.
Fix: never trust `global_transform` (or `get_aabb()` combined with it) in a
bare `--script` tool for any node with meaningful nesting -- manually
compose each node's own LOCAL `.transform` by walking `get_parent()` up to
the root instead (see `measure_higgsfield_dungeon.gd`'s own
`_real_global_transform()` for the pattern: plain already-resolved
`Transform3D` multiplication, no lazy/dirty propagation involved, correct
with zero process frames). `measure_pieces.gd`/`build_prototype_chamber.gd`
happened not to hit this (Kenney's GLBs don't have the same nested-wrapper
translation structure), and the `test_*_token.gd/.tscn` tools were already
immune for an unrelated reason (real scene + `await
get_tree().process_frame`, which gives Godot the process frame this bug is
actually missing) -- but any FUTURE bare `--script` tool measuring a
piece's real world position, especially anything that went through
`fix_higgsfield_vertex_colors.gd`'s wrapper-adding process, needs this
fix from the start, not discovered after guessing wrong for a whole map.

**Fifth gotcha: a brand new `class_name` isn't visible to these scripts until
the project's global class cache knows about it.** Adding a new `class_name`
(e.g. `MapScenes`, Phase 6) and immediately running a `--headless --script`
tool against code that references it fails with `Identifier "X" not
declared in the current scope"`, even though the exact same code opens fine
in a real editor session -- the editor scans and registers `class_name`
declarations into `.godot/global_script_class_cache.cfg` on project open,
and a bare `--script` run never triggers that scan on its own. Fix: run the
project through one headless editor pass first, which does the same scan
and quits without opening a GUI window:
```
<path-to-Godot>.exe --headless --editor --path godot --quit
```
Then the normal `--headless --script ...` tools can see the new class.

None of these are shipped or referenced by the actual game -- delete any of
them freely if they get in the way; regenerate `measure_pieces.gd`'s or
`build_prototype_chamber.gd`'s output by re-running them if needed.
