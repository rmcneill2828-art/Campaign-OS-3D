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

- [x] **Real glTF models for tokens and floor tiles.** Built 2026-09-11, needs
  live verification (see checklist below). `Token.gd` loads a real model per
  token type (`res://assets/creatures/hero/superhero_male.gltf` for heroes,
  `.../monster/imp.glb` for every monster, regardless of which SRD stat block
  it actually is -- a real per-name mapping is future work, see
  `godot/assets/README.md`) via `load()` + `ResourceLoader.exists()`, falling
  back to Phase 0's plain colored capsule if the asset isn't present (see
  Licensing below for why that fallback matters here specifically, not just as
  generic defensiveness). `GridManager.gd` now instances Kenney's real
  `floor.glb` (with `floor-detail.glb` mixed in on a fixed, deterministic
  subset of cells for visual variety) instead of a procedural checkerboard,
  uniformly scaled to `cell_size` -- confirmed by reading each model's own
  glTF accessor bounds directly (not assumed) that floor pieces are an exact
  1x1x1 unit cube and the character models already have their feet at local
  y=0, which is what made both scale/placement formulas exact rather than
  guessed. **Found and fixed a real Phase 0/1 bug along the way**: tokens were
  positioned 0.8m above the actual ground plane (`Token.gd`'s target position
  added a +0.8 offset on top of an *already* +0.8-offset child mesh) --
  harmless-looking with an abstract capsule, would have been obviously wrong
  once real ground-touching feet were added, so fixed at the root cause.
- [ ] **Animation is NOT done** -- both free-tier Quaternius packs used here
  ship with zero baked animation clips (confirmed by reading each file's own
  glTF/glb JSON directly, not assumed from their "Rigged"/"Retargetable"
  marketing tags), so models currently render in their raw bind pose (a
  T-pose, arms spread, for the hero) rather than idling/walking. Needs a
  separate download -- Quaternius's free "Universal Animation Library" is
  built specifically to retarget onto these "Retargetable" rigs -- before this
  item can actually be finished; tracked here rather than in Phase 3 since
  it's the direct continuation of this same asset-pipeline work.
- [ ] Walls (Kenney's `wall.glb`/`wall-half.glb`) around the board perimeter --
  deliberately deferred out of this pass rather than attempted alongside the
  floor/character changes above: wall segments are a 2x2x2.1 unit footprint
  (twice a floor tile's width), so getting the alignment right needs its own
  focused verification pass, not stacked on top of several other unverified
  geometry changes at once.

### Needs live verification (same reasoning as Phases 0-1)

- [ ] Heroes render as the real (T-posed) humanoid model, monsters as the real
  Imp model -- not capsules -- and neither model is missing/pink/broken-texture
  (the two-file "_png" URI mismatch in Quaternius's own hero export was fixed
  in this project's copy, see `godot/assets/README.md`)
- [ ] Models stand ON the floor (feet at the tile surface), not floating or
  sunk into it -- the specific thing the double-offset bug fix above should
  have corrected
- [ ] The floor renders as real dungeon tiles (stone texture, some tiles
  showing the "detail" variant) instead of the flat gray/tan checkerboard,
  tiling edge-to-edge with no visible gaps or overlaps between cells
- [ ] A token dropping to 0 HP still shows *some* visible state change even
  without the old grey-capsule tint (currently just the HP label text --
  confirm this reads clearly enough, or flag it as a gap to fix)
- [ ] Godot's console is clean of new errors/warnings after reloading the
  project (the `.gdignore` files added this session should have silenced the
  large warning count from Godot trying to import the raw, unused pack dumps
  -- confirm the specific 3 errors reported are gone too, or report back what
  they actually said if they're still there)
- [ ] Fix whatever the above turns up

## Phase 3+ -- Everything else (not scoped yet)

Deliberately not broken down further until Phases 0-2 are actually played with:
line-of-sight/fog of war in 3D, spellcasting VFX, a real dungeon-building/import
workflow, audio, a player-facing view, and -- much later, only once the pipeline
and interaction loop are both proven -- an actual investment in bespoke/licensed
"professional" art to replace the CC0 placeholders. Revisit this file once Phase 2
lands rather than guessing at the shape of Phase 3 now.
