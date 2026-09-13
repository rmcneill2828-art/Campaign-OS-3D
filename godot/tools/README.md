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
- **`inspect_kaykit_skeleton.gd`** (Phase 8) -- lists every real animation
  clip name in a set of KayKit animation files and checks their skeleton's
  bone names against a target model's, the same "verify a rig actually
  matches, don't assume from a shared folder name" check that already
  covered Quaternius's UAL1. A template for verifying the NEXT new
  monster/hero model family before wiring it into `Token.gd`'s
  `MODEL_CONFIG` -- edit `SKELETON_MODEL`/`ANIM_FILES` for whatever's being
  checked next.
- **`test_skeleton_token.gd`/`.tscn`** and **`test_imp_token.gd`/`.tscn`** --
  actual `Node`-scene functional checks (NOT bare `--script` SceneTree tools
  -- those run before `@onready`/`_ready()` ever fire on manually-instanced
  children, which silently breaks a real `Token.apply_data()` call; see the
  gotcha these two were written to work around, below) that build a real
  `Token` for a specific server-shaped name ("Skeleton 1", "Goblin 1") and
  print whether `MODEL_CONFIG`'s lookup/bone-map/animation resolution
  actually succeeded. Run via
  `<Godot>.exe --headless --path godot res://tools/test_skeleton_token.tscn`
  (a real scene path, not `--script`). A template for confirming the NEXT
  new per-monster-name `MODEL_CONFIG` entry actually resolves before ever
  looking at it live in the editor.

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

**Gotcha: a brand new `class_name` isn't visible to these scripts until the
project's global class cache knows about it.** Adding a new `class_name`
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
