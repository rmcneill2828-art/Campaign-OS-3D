# Campaign OS 3D

A separate, from-scratch **3D real-time battle map** client for Campaign OS's D&D
5e rules engine -- a Godot project, talking over local HTTP to the exact same 5e
rules logic (`engine/encounter.js`, `engine/dmBridge.js`) the 2D Campaign-OS app
uses. This is a new project, not a branch of the 2D app -- the 2D app
([`../Campaign-OS`](../Campaign-OS)) is left completely untouched and remains the
one actually usable at the table today.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the two halves fit together, and
[ROADMAP.md](ROADMAP.md) for what's built so far and what's next.

## Why a separate project

Campaign-OS's own battle map is DOM/CSS -- flat map images with percent-positioned
`<div>` tokens, zero 3D rendering of any kind. Getting to a real-time 3D board with
professional-grade visuals isn't an incremental feature on that app; it's a new
rendering/asset pipeline end to end. Keeping it a separate repo means the working
2D app never has to sit mid-refactor while this is figured out, and this project is
free to make very different technology choices (a real game engine, a build step,
3D asset pipelines) without dragging the 2D app's "open index.html, no build step"
design along for the ride.

## What's here today (prototype, Phase 0 -- see ROADMAP.md)

- **`engine-server/`** -- a small, zero-dependency Node HTTP server that loads a
  verbatim copy of Campaign-OS's `engine/encounter.js` + `engine/dmBridge.js` (the
  same way Campaign-OS's own tests do -- see `lib/loadEngine.js`) and exposes it as
  `GET /state` / `POST /action` / `POST /reset`. This is the ONLY place 5e rules are
  decided -- the Godot client never computes a rule itself, it just renders
  whatever the server reports and asks it to do things.
- **`godot/`** -- a Godot 4 project: an orbit camera over a checkerboard 3D grid,
  placeholder capsule "miniatures" for each token, click-to-select / click-to-move
  wired to the server above, and a status readout of the combat log. Geometry is
  all built-in Godot primitives for now -- no art assets yet, see
  [`godot/assets/README.md`](godot/assets/README.md).

## Running it

**1. Start the rules engine server** (from `engine-server/`):

```text
npm test        # optional -- confirms the copied engine still behaves as expected
node server.js  # listens on http://127.0.0.1:8787
```

Leave it running. It seeds a small default encounter (two heroes, two goblins) the
first time it runs, and persists any changes to `state/encounter.json` so restarting
it doesn't lose progress. `POST /reset` restores the default encounter at any time.

**2. Open the Godot project.** Requires **Godot 4.3+** (not installed in the
environment this was scaffolded in -- get it from https://godotengine.org/download).
Open `godot/project.godot` in the Godot editor and press Play (F5), or run
headlessly:

```text
godot --path godot
```

**3. Play.** Right-drag to orbit the camera, middle-drag to pan, scroll to zoom.
Left-click a miniature to select it, then either left-click a floor tile to move
it there, or right-click (a quick click, not a drag -- a right-drag still just
orbits the camera) a *different* token to attack it with the selected one --
both go through the real engine (`moveToken()`'s speed limits/RAW diagonal cost,
`attack()`'s real hit/damage roll). **Next Turn** in the HUD advances the turn
tracker, which is what actually turns on movement's speed limit (unconstrained
before turn order starts, same as the 2D app).

## What this does NOT do yet

This is still an early slice proving the pipeline works end to end against the
real rules engine, not yet a usable VTT: no spellcasting/conditions/resources UI,
no real 3D models (placeholder primitives only), no imported maps, no player
window, no DM bridge/Claude narration. See [ROADMAP.md](ROADMAP.md) for the
planned order of what comes next -- and note Phase 1's newest pieces (attack,
turn tracker, feet-per-square scaling) haven't been visually verified yet either,
see ROADMAP's own checklist.
