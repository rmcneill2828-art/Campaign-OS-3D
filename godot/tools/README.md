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
- **`smoke_test_main.gd`** -- instantiates `Main.tscn` headlessly and
  confirms it loads/`_ready()`s with no script error (no live
  `engine-server` needed -- HTTPRequest calls just fail to connect, which is
  fine). A cheap regression check after editing `Main.gd`/`GridManager.gd`/
  `Token.gd`, before ever opening the real editor.

None of these are shipped or referenced by the actual game -- delete any of
them freely if they get in the way; regenerate `measure_pieces.gd`'s or
`build_prototype_chamber.gd`'s output by re-running them if needed.
