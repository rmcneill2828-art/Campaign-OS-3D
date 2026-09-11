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
  latest combat-log line. **Not yet verified inside the Godot editor** -- no Godot
  install was available in the environment this was scaffolded in (see "Needs
  verification" below). Hand-written `.tscn`/`.gd` files following standard Godot
  4.3 conventions; the engine-server half (server logic, action dispatch, state
  persistence) IS independently verified via its own test suite above, since that
  part runs under plain Node either way.
- [ ] **Needs verification: open `godot/project.godot` in a real Godot 4.3+
  editor and confirm it actually loads and runs** -- install Godot
  (https://godotengine.org/download), open the project, press Play with
  `engine-server` running, and work through the checklist below. This is the
  single most important next step before building anything further on top of this
  scaffold, since none of it has been visually confirmed yet:
  - [ ] Board renders as a checkerboard grid at the right size (12x8 by default)
  - [ ] Two blue hero capsules and two red goblin capsules appear, each labeled
  - [ ] Right-drag orbits, middle-drag pans, wheel zooms, and the camera never
    flips upside down or clips through the floor
  - [ ] Left-clicking a token shows its selection ring; left-clicking a floor tile
    afterward moves it there (both instantly in the 3D view and confirmed via
    `curl http://127.0.0.1:8787/state` showing the new x/y)
  - [ ] Status label updates with the combat log line after a move
  - [ ] Stopping/restarting `node server.js` and reconnecting doesn't crash the
    client (it should just show the "could not reach engine-server" status text
    while it's down)
  - [ ] Fix whatever the above turns up -- some tuning (camera angle/speed, tile
    size, label legibility) should be expected on a scaffold that's never been
    seen rendered

## Phase 1 -- Make the prototype actually playable (small, after Phase 0 is verified)

- [ ] **Attack action from the client.** Right-click (or a small on-screen button)
  on a selected token's target to fire a real `attack` action, showing the
  hit/miss/damage message and updating HP-driven capsule color/label live.
- [ ] **Turn tracker UI.** A minimal HUD control for `next_turn`, showing whose
  turn it is -- unlocks real speed-limited movement (`moveToken` only enforces
  movement budget on the active turn's own token, same as the 2D app).
- [ ] **Tie CELL_SIZE to the map's real feetPerSquare** instead of a fixed visual
  constant (`GridManager.gd`'s documented follow-up) so distances read correctly
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
