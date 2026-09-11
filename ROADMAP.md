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

### Needs live verification (same reasoning as Phase 0 -- none of this has been
seen rendered; no Godot install in the environment that built it)

- [ ] Selecting a token, then right-clicking a different token, sends a real
  attack (confirm via the status HUD message and/or `curl .../state` showing
  HP changed) -- and a right-drag used purely to orbit the camera does NOT
  also fire an attack
- [ ] "Next Turn" advances the round/active token, shown correctly in the
  status label, and a moved-but-not-yet-its-turn token still moves freely
  (unconstrained) while the active token's movement is speed-limited
- [ ] Default map (5 ft/square) still renders at the same tile size as before
  this change -- a quick visual regression check, not a new feature to test
- [ ] Fix whatever the above turns up
  once movement/range start mattering to the player, not just to the server.

## Phase 2 -- Real assets (medium, after Phase 1 proves the interaction loop)

- [ ] Swap capsule primitives for free/CC0 glTF miniatures (Kenney, Quaternius, or
  similar) for at least hero/goblin-tier monster silhouettes -- first real test of
  a glTF import pipeline in this project.
  - Kenney: https://kenney.nl/assets (many CC0 3D asset packs, including
    mini-dungeon/creature-adjacent sets)
  - Quaternius: https://quaternius.com/ (CC0 low-poly characters/creatures)
- [ ] Basic idle/walk animation on at least one imported rig, driven by an
  AnimationPlayer/AnimationTree state -- first real test of the animation
  pipeline this whole effort depends on for "professional game graphics" later.
- [ ] A simple modular floor/wall tile kit (even a CC0 placeholder one) instead of
  the flat checkerboard, to start answering the "how is 3D map geometry authored"
  open question ARCHITECTURE.md flags.

## Phase 3+ -- Everything else (not scoped yet)

Deliberately not broken down further until Phases 0-2 are actually played with:
line-of-sight/fog of war in 3D, spellcasting VFX, a real dungeon-building/import
workflow, audio, a player-facing view, and -- much later, only once the pipeline
and interaction loop are both proven -- an actual investment in bespoke/licensed
"professional" art to replace the CC0 placeholders. Revisit this file once Phase 2
lands rather than guessing at the shape of Phase 3 now.
