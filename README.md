# Campaign OS 3D

A separate, from-scratch **3D real-time battle map** client for Campaign OS's D&D
5e rules engine -- a Godot project, talking over local HTTP to the exact same 5e
rules logic (`engine/encounter.js`, `engine/dmBridge.js`) the 2D Campaign-OS app
uses. This is a new project, not a branch of the 2D app -- the 2D app
([`../Campaign-OS`](../Campaign-OS)) is left completely untouched and remains the
one actually usable at the table today.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the two halves fit together, and
[ROADMAP.md](ROADMAP.md) for what's built so far and what's next (Phases 0-8 are
complete; a feature-parity audit against the 2D app tracks what's still missing).

## Why a separate project

Campaign-OS's own battle map is DOM/CSS -- flat map images with percent-positioned
`<div>` tokens, zero 3D rendering of any kind. Getting to a real-time 3D board with
professional-grade visuals isn't an incremental feature on that app; it's a new
rendering/asset pipeline end to end. Keeping it a separate repo means the working
2D app never has to sit mid-refactor while this is figured out, and this project is
free to make very different technology choices (a real game engine, a build step,
3D asset pipelines) without dragging the 2D app's "open index.html, no build step"
design along for the ride.

## What's here today

- **`engine-server/`** -- a small, zero-dependency Node HTTP server that loads a
  verbatim copy of Campaign-OS's `engine/encounter.js` + `engine/dmBridge.js` (the
  same way Campaign-OS's own tests do -- see `lib/loadEngine.js`) and exposes it as
  `GET /state`, `POST /action`, `POST /dm-command`, and `POST /reset`. This is the
  ONLY place 5e rules are decided -- the Godot client never computes a rule itself,
  it just renders whatever the server reports and asks it to do things. State
  persists to `state/encounter.json` with atomic writes and a `.bak` recovery copy.
- **`dm-bridge/`** -- Campaign-OS's own Claude DM bridge (`watch.js`), copied
  verbatim and never hand-edited. Run separately (`node dm-bridge/watch.js`); it
  watches for a `request.json` the engine-server's `/dm-command` endpoint writes and
  answers with a `response.json`, the same file-based protocol the 2D app uses.
- **`godot/`** -- a Godot 4 project with two scenes:
  - **`Main.tscn`** -- the DM's working view: an orbit/pan/zoom camera over a real
    3D board (hand-built maps with real geometry, floor/wall glTF assets, and
    line-of-sight-blocking walls), animated humanoid miniatures (idle/walk/hit/
    death/dying-kneel), click-to-select / click-to-move / right-click-to-attack,
    a scrolling combat log, and a collapsible Token Actions panel covering the
    full core 5e loop -- saving throws, ability checks, all 11 conditions,
    single-target and area spellcasting, class resources, long/short rests, death
    saves, exhaustion, legendary actions, recharge abilities, lair actions,
    healing, initiative (roll or set), an advantage/disadvantage roll-mode
    toggle, and quick actions for damage/drop-concentration/spend-hit-die/remove-
    token. A "DM Assistant (Claude)" panel sends free-text narration through
    `POST /dm-command` and applies whatever actions Claude decides on.
  - **`PlayerView.tscn`** -- a read-only second window (opened via "Open Player
    Window" in the DM view, meant for a second monitor/TV) with no `POST /action`
    call anywhere in it, structurally incapable of mutating the encounter. Shows
    only tokens the server's `visibleTokenIds` allows (`hiddenFromPlayers` +
    line-of-sight, computed server-side so this can't drift from the DM view's
    own rule), a rough color-banded HP bar instead of exact numbers, a three-state
    fog overlay (unexplored / explored-but-not-visible / currently visible), and
    the initiative list + combat log.

  Two hand-built example maps ship today (Prototype Chamber, Entrance Hall); see
  [`godot/tools/README.md`](godot/tools/README.md) for how a new one is built, and
  [`godot/assets/README.md`](godot/assets/README.md) for asset licensing and the
  current (partial) per-monster model coverage.

## Running it

**1. Start the rules engine server** (from `engine-server/`):

```text
npm test        # optional -- confirms the copied engine still behaves as expected
node server.js  # listens on http://127.0.0.1:8787
```

Leave it running. It seeds a small default encounter (two heroes, two goblins) the
first time it runs, and persists any changes to `state/encounter.json` so restarting
it doesn't lose progress. `POST /reset` restores the default encounter at any time.

**2. (Optional) Start the Claude DM bridge** (from the project root), if you want
the in-game "DM Assistant" panel to work:

```text
node dm-bridge/watch.js
```

Requires the `claude` CLI already installed and authenticated on this machine --
see `dm-bridge/watch.js`'s own header comment for how it's invoked. Everything else
(move/attack/spells/etc. from the Token Actions panel) works without this running.

**3. Open the Godot project.** Requires **Godot 4.7+** (the project targets Godot's
"4.7" feature set; developed and verified live against 4.7.2 -- get it from
https://godotengine.org/download). Open `godot/project.godot` in the Godot editor
and press Play (F5), or run headlessly:

```text
godot --path godot
```

**4. Play.** Right-drag to orbit the camera, middle-drag to pan, scroll to zoom.
Left-click a miniature to select it (Esc, clicking it again, or clicking past the
board all deselect), then either left-click a floor tile to move it there, or
right-click (a quick click, not a drag -- a right-drag still just orbits the
camera) a *different* token to attack it with the selected one -- both go through
the real engine. **Next Turn** in the HUD advances the turn tracker, which is what
actually turns on movement's speed limit (unconstrained before turn order starts,
same as the 2D app). The collapsible sections on the right (Checks, Conditions,
Spells, Resources, Other, Initiative) act on whichever token is currently
selected; the "DM Assistant (Claude)" section and "Open Player Window" button are
scene-wide and need no selection.

## What this does NOT do yet

The core 5e rules loop, real assets, hand-built maps with line-of-sight/fog, a
player-facing second window, and Claude DM narration are all built and verified
live in Godot -- see [ROADMAP.md](ROADMAP.md)'s Phase 0-8 entries and its
"Feature Parity Audit" section for the full detail behind each of these. Real gaps
against the 2D app, still open:

- No AoE template tool (drag out a cone/circle/line on the map and auto-detect
  covered tokens) -- `cast_area_spell` still requires checking each target by hand.
- No ruler/measuring tool.
- No interactive wall editor -- walls come from hardcoded map-building tools or
  DM Assistant text commands, not click-drag drawing.
- No Encounter Difficulty calculator, no freeform dice roller (both are already
  pure functions in the shared engine, just not wired into this client's UI yet).
- No Token Library / Map Library / folder-based asset browsing -- every map and
  creature model is hand-built/hardcoded today.
- No Character Creator wizard, no End Session / session-transcript reporting
  (both already exist in `dm-bridge/watch.js` itself; this client's UI just never
  added a way to trigger them).
- No campaign-level save/load across multiple sessions -- one live
  `engine-server/state/encounter.json` only.
- No music/ambience system.
- Only a handful of monster types (hero, generic monster, skeleton, orc) have a
  real per-name 3D model; everything else falls back to a generic placeholder --
  see `godot/assets/README.md`.
- Godot-side CI only runs the existing headless smoke tests (do the scenes
  load and `_ready()` clean); no automated interaction coverage yet for
  things like token selection, movement, player-view fog, or HUD action
  wiring actually doing the right thing when clicked.
