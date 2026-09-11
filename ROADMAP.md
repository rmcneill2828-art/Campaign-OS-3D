# Campaign OS 3D -- Roadmap

Working plan, in the same spirit as Campaign-OS's own `ROADMAP.md`: a checklist of
what's actually done vs. what's next, organized by dependency rather than strict
priority. This project is much earlier than that one -- expect this file to change
shape a lot as the first few phases land and teach us what the next ones should be.

## Phase 0 -- Prove the pipeline (in progress)

The goal of this phase is narrow on purpose: confirm that server-authoritative
rules + a Godot 3D client + placeholder art can actually work together end to end,
before investing in anything real-art-shaped or feature-complete.

- [x] **engine-server.** Done 2026-09-11. Zero-dependency Node HTTP server loading
  a verbatim copy of `engine/encounter.js` + `engine/dmBridge.js`, exposing
  `GET /state` / `POST /action` / `POST /reset`. Seeds a small default encounter
  (2 heroes, 2 goblins) on first run, persists to `state/encounter.json`. 5 unit
  tests (`npm test`) covering state seeding, move_token, attack, malformed-action
  rejection, and reset -- verified live over real HTTP (not just in-process calls)
  with curl before committing.
- [x] **Godot scaffold.** Done 2026-09-11. `godot/` project with an orbit/pan/zoom
  camera rig, a checkerboard grid built from the server's real column/row count,
  capsule-primitive "miniatures" colored by token type (blue hero / red monster /
  grey at 0 HP) with a floating name+HP label, click-to-select and click-to-move
  wired to `POST /action`, and a status readout showing the connection state and
  latest combat-log line. Hand-written `.tscn`/`.gd` files, opened cleanly in a
  real Godot 4.7.2 editor with only the expected one-time "upgrade from 4.3"
  project-settings prompt -- no script/parse errors.
- [x] **Verified live in Godot 4.7.2, 2026-09-11 (user-confirmed).** Board
  renders as a checkerboard grid at the right size; two blue hero capsules and
  two red goblin capsules appear, each labeled; right-drag/middle-drag/wheel
  orbit/pan/zoom the camera smoothly with no flipping or floor-clipping;
  left-clicking a token then a floor tile moves it (a real `move_token` call
  through the actual engine, not a local fake); the status HUD updates with the
  combat-log line after a move. Camera feel and tile/label sizing were good
  enough to not need immediate tuning. Not separately re-tested: killing/
  restarting `node server.js` mid-session (the client's reconnect-status-text
  path) -- low-risk, revisit only if it actually misbehaves at the table.

Phase 0 complete. The core bet -- server-authoritative rules engine + a Godot 3D
client + placeholder art, wired end to end -- is proven out.

## Phase 1 -- Make the prototype actually playable (small, after Phase 0 is verified)

- [x] **Attack action from the client.** Built 2026-09-11, needs live
  verification (see checklist below). Left-click selects a token (as before);
  a quick right-click (not a right-drag, which still orbits the camera --
  `Main.gd` distinguishes the two by whether the mouse moved more than
  `RIGHT_CLICK_DRAG_THRESHOLD_PX` between press and release) on a *different*
  token fires a real `attack` action with the selected token as attacker.
  Hit/miss/damage message shows in the status HUD (it's already the server's
  own log line, no separate rendering needed) and HP-driven capsule
  color/label updates live -- both existing `Token.gd` behavior from Phase 0,
  unchanged, since the server response already carries the post-attack state.
- [x] **Turn tracker UI.** Built 2026-09-11, needs live verification. A "Next
  Turn" button in the HUD sends `next_turn`; the status label now shows
  "Turn order not started" (round 0) or "Round N -- `<name>`'s turn."
  (resolved from the server's own `turn.tokenId` against the current map's
  tokens) -- this is what actually unlocks real speed-limited movement
  (`moveToken` only enforces movement budget on the active turn's own token,
  same as the 2D app).
- [x] **Tie the grid's visual scale to the map's real feetPerSquare** instead
  of the fixed `CELL_SIZE` constant Phase 0 shipped with. Built 2026-09-11,
  needs live verification. `GridManager.gd` now derives `cell_size` from
  `feet_per_square * METERS_PER_FOOT` (0.4 m/ft, chosen so the D&D-default 5
  ft square still renders at exactly the same 2.0m tile Phase 0 had -- the
  default case is visually unchanged) and rebuilds the board if a map's own
  `feetPerSquare` differs, e.g. a 10 ft/square map renders visibly bigger
  tiles.

- [x] **Verified live in Godot, 2026-09-11 (user-confirmed).** Attack (select
  then right-click a target) fires correctly and a right-drag-only orbit does
  NOT also attack; Next Turn advances round/active token correctly in the
  status label; default 5 ft/square map renders unchanged. Bonus, unprompted
  confirmation the server-authoritative architecture is paying off already:
  dropping a goblin to 0 HP surfaced a real "starts making death saves"
  message with **zero client-side code written for death saves at all** --
  it's a rules consequence the engine already handles (see Campaign-OS's own
  `CLAUDE.md` "Death saves" section), and it just showed up for free because
  the Godot client renders whatever the server's log says, nothing more
  specific than that.

Phase 1 complete.

## Phase 2 -- Real assets (medium, after Phase 1 proves the interaction loop)

- [x] **Real glTF models for tokens and floor tiles.** Done 2026-09-11,
  verified live in Godot (user-confirmed) after three follow-up fixes. `Token.gd`
  loads a real model per token type (`res://assets/creatures/hero/superhero_male.gltf`
  for heroes, `.../monster/imp.glb` for every monster, regardless of which SRD
  stat block it actually is -- a real per-name mapping is future work, see
  `godot/assets/README.md`) via `load()` + `ResourceLoader.exists()`, falling
  back to Phase 0's plain colored capsule if the asset isn't present (see
  Licensing below for why that fallback matters here specifically, not just as
  generic defensiveness). `GridManager.gd` instances Kenney's real `floor.glb`
  (with `floor-detail.glb` mixed in on a fixed, deterministic subset of cells
  for visual variety) instead of a procedural checkerboard, uniformly scaled
  to `cell_size`, plus a thin white grid-line overlay so the DM can still read
  cell boundaries on a real (non-checkerboard) stone texture.
  **Three real placement bugs found and fixed from actual screenshots, not
  file inspection alone** -- worth recording since they share one root lesson:
  a model file's own authored/raw bounds do NOT reliably predict where Godot
  actually renders it (a rig's skeleton root rotation, a modular kit piece's
  decorative props sitting above its base plate, etc. -- each is a different
  concrete cause, no single rule would have caught all three in advance):
  1. A genuine Phase 0/1 bug, unrelated to the new assets but only obviously
     wrong once real feet existed: `Token.gd` added a +0.8 vertical offset on
     top of an *already* +0.8-offset child mesh, floating every token 0.8m
     above the ground.
  2. Fixing #1 alone still left characters floating -- their raw glTF vertex
     bounds suggested feet at local y=0, but both rigs have a skeleton root
     bone with a baked-in -90 degree rotation (a Z-up/Y-up export artifact)
     that changes a skinned mesh's real bind-pose position in a way those raw
     bounds don't capture. Fixed by measuring the actual instantiated model's
     AABB at runtime (`_ground_model()`) instead of trusting the file.
  3. The floor tiles then rendered visibly below the grid lines -- same
     lesson again: `floor.glb`'s raw bounds suggested a plain 1x1x1 box, but
     the real rendered result didn't match. Fixed the same way
     (`_measure_top_offset()`), which then revealed a FOURTH, more specific
     issue: `floor-detail.glb` (measured independently) came out sitting
     visibly sunken relative to plain floor tiles, because that scene's own
     highest point is the top of a decorative rubble prop, not the shared
     base-plate surface `floor.glb` and `floor-detail.glb` are actually meant
     to share. Fixed by measuring the offset once from the plain tile only
     and reusing it for both variants, rather than measuring each
     independently.
- [x] **Verified live in Godot, 2026-09-11 (user-confirmed), after the three
  follow-up fixes above.** Heroes render as the real (T-posed) humanoid
  model, monsters as the real Imp model, no missing/pink/broken textures;
  models stand correctly on the floor with feet at the tile surface (no
  floating, no sinking); the floor renders as real dungeon stone tiles
  (plain + detail variants) all sitting flush at the same level, tiling
  edge-to-edge with the grid-line overlay reading clearly on top; console
  clean of errors after the `.gdignore` additions (the earlier "3 errors and
  311 warnings" did not recur). Not separately flagged as a problem: a token
  at 0 HP currently shows only via its HP label text (no fallback-capsule-style
  grey tint on a real model) -- left as a known, minor gap rather than a
  blocker, revisit if it actually causes confusion at the table.

Phase 2 complete for the two items above. Two items from this phase remain
explicitly open (not silently dropped):

- [x] **Animation.** Built 2026-09-11, **not yet verified live** (this is the
  most structurally complex piece of Phase 2 -- budget for at least one
  round of live debugging, same as the model/floor placement bugs above).
  Downloaded Quaternius's free "Universal Animation Library" (v1 and v2;
  only v1's non-root-motion `UAL1_Standard.glb` is used, see
  `godot/assets/README.md`). Verified by direct comparison (not assumed)
  that its skeleton's bone names match the hero model's exactly and the
  monster's bones are a strict subset of the same set. `Token.gd`'s
  `_setup_animation()` instances a hidden copy of the animation file
  alongside the visible model and copies bone poses across by NAME every
  frame (`_process()`), rather than trying to graft the animation library's
  `AnimationPlayer` tracks directly onto the character's own scene via
  NodePath -- deliberately avoiding a second reliance on Godot's glTF
  importer producing identical scene structure across different files,
  exactly the assumption that caused the three placement bugs above. Idle
  plays by default; a real `move_token`-driven move switches to Walk for the
  tween's duration and back to Idle after. A one-time diagnostic
  `print()` reports the bone-map coverage (e.g. "62/62 bones") to the Godot
  console per token the first time its model builds -- check this first if
  animation doesn't visibly work, since it will immediately show whether
  bone-name matching actually succeeded.

### Needs live verification (animation specifically -- see print() diagnostic above)

- [ ] Godot console shows a "N/N bones" message per token with N close to the
  full bone count (a low number, or an error before that line, points at
  bone-name matching or file-loading failing)
- [ ] Stationary heroes/monsters play a subtle idle animation (breathing/sway),
  not a frozen T-pose
- [ ] Moving a token (click-to-move) visibly switches it to a walk animation
  for the duration of the move, then back to idle once it arrives
- [ ] No visual glitching/jitter in the pose (would suggest a bone mismatch or
  conflicting pose source)
- [ ] Fix whatever the above turns up

- [ ] **Walls** (Kenney's `wall.glb`/`wall-half.glb`) around the board
  perimeter -- deliberately deferred out of this pass rather than attempted
  alongside the floor/character changes above: wall segments are a 2x2x2.1
  unit footprint (twice a floor tile's width), so getting the alignment right
  needs its own focused verification pass, not stacked on top of several
  other unverified geometry changes at once. Given how many placement
  surprises the floor/character work above turned up, budget for the same
  "measure the real thing" approach rather than assuming Kenney's own stated
  dimensions will just work.

## Phase 3+ -- Everything else (not scoped yet)

Deliberately not broken down further until Phases 0-2 are actually played with:
line-of-sight/fog of war in 3D, spellcasting VFX, a real dungeon-building/import
workflow, audio, a player-facing view, and -- much later, only once the pipeline
and interaction loop are both proven -- an actual investment in bespoke/licensed
"professional" art to replace the CC0 placeholders. Revisit this file once Phase 2
lands rather than guessing at the shape of Phase 3 now.
