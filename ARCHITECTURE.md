# Architecture

## The three decisions this project starts from

Settled 2026-09-11, after a review of the 2D Campaign-OS app concluded that "3D
with professional game graphics" is not an incremental feature but a separate
project of comparable-or-greater size, dominated by art/engineering work the 2D
app never needed:

1. **Real-time 3D battle map** (orbit camera over a 3D board with 3D miniatures) --
   not an isometric/2.5D board, and not a full first/third-person walk-around
   world. The closest cousin to what the 2D app already is.
2. **Godot** (4.3+, GDScript, Forward+ renderer) -- not staying in-browser
   (Three.js/Babylon.js), and not Unity/Unreal. Free, open-source, a real 3D
   rendering ceiling, and its own editor/tooling rather than hand-authoring
   everything.
3. **Free/CC0 placeholder assets first** (built-in Godot primitives right now;
   Kenney/Quaternius-style packs next) to prove the camera/grid/animation/lighting
   pipeline works before spending money or bespoke-art time on "professional"
   models.

## Why the rules engine is a local HTTP server, not a GDScript port

Campaign-OS's `engine/*.js` (encounter state, combat math, saving throws,
spellcasting, conditions, death saves, rest automation, line of sight, encounter
difficulty -- see Campaign-OS's own `CLAUDE.md`/`ROADMAP.md` for the full list) is
hundreds of hours of tested, RAW-accurate 5e rules logic. Porting that to GDScript
would mean **two** implementations of D&D 5e rules to keep in sync forever, with
every future rules fix (a new monster, a corrected damage-type edge case) needing
to land twice. That's a strictly worse position than today's actual constraint,
which this project instead works around the same way `dm-bridge/watch.js` already
does for the Claude integration: **a small local Node process the game client
talks to over HTTP**, keeping exactly one real implementation of the rules.

`engine-server/` loads `engine/encounter.js` and `engine/dmBridge.js` **completely
unmodified**, using the identical technique Campaign-OS's own
`tests/load-script.js` uses to unit-test them under Node (`new Function("window",
"console", code)` -- these files are plain browser scripts that attach to
`window`, not CommonJS modules, so this avoids forking a second, Node-flavored
copy just to get `require()` to work). See `engine-server/lib/loadEngine.js`.

**This means engine-server/engine/*.js is a COPY, not a symlink or a build
artifact** -- `engine-server/scripts/sync-engine.sh` re-pulls it from a sibling
Campaign-OS checkout on demand. There is exactly one real source of truth (the 2D
repo), synced by hand and reviewed before committing, the same convention
Campaign-OS's own `CLAUDE.md` already documents for its several intentionally
duplicated lookup lists (`MONSTER_LIST`/`CONDITION_LIST`/`DAMAGE_TYPE_LIST`/
`SKILL_LIST` between the browser engine and `dm-bridge/watch.js`). Re-run it
whenever a rules fix lands upstream in Campaign-OS and this project needs it.

## The HTTP contract

`engine-server/server.js` is a plain `node:http` server (no Express, no
dependencies -- matching Campaign-OS's own zero-dependency ethos) exposing:

- `GET /state` -- the full current encounter state (same shape as
  `dm-bridge/live-state.json` in the 2D app).
- `POST /action` -- one action object, e.g. `{"type": "move_token", "target":
  "Darkhawk", "x": 5, "y": 5}`. Dispatched through `engine/dmBridge.js`'s
  `applyActions()` -- **the exact same action vocabulary** the 2D app's Claude DM
  bridge and live-actions channel already use (`attack`, `cast_spell`,
  `spawn_monster`, `next_turn`, `use_resource`, ... -- see Campaign-OS's own
  `dm-bridge/watch.js` `SYSTEM_PROMPT` constant for the authoritative shape list).
  Returns the new state plus any log message(s).
- `POST /reset` -- reseeds the small default prototype encounter.

State persists to `engine-server/state/encounter.json` between runs (gitignored --
runtime data, not source, the same way the 2D app's browser-side autosave isn't
committed anywhere either).

## The Godot side

`godot/` is a normal Godot 4 project (`project.godot`, `scenes/`, `scripts/`) --
nothing unusual there. The one thing worth knowing: **the Godot client makes no
rules decisions of its own.** `Main.gd` polls `GET /state` on a timer, renders
whatever comes back (grid size, token positions/HP/type), and turns a click into a
`POST /action` call -- it never computes movement legality, hit/miss, damage, or
anything else rules-shaped locally. That boundary is deliberate and should hold
for every future feature: if it's a rule, it lives in `engine/*.js` and gets
called through `engine-server`; if it's presentation (camera feel, model
selection, VFX, animation timing), it lives in Godot.

See `godot/scripts/*.gd` for the current pieces (`GridManager` -- grid-cell <->
world-space math and board geometry; `Token` -- one miniature's rendering/motion;
`CameraRig` -- orbit/pan/zoom; `Main` -- polling, state-to-scene sync, click
handling) and `ROADMAP.md` for what's not built yet.

## What's deliberately NOT decided yet

- **Real-time multiplayer / a player-facing view.** The 2D app's "Player window"
  is same-machine, polling-based, and out of scope here until this prototype's
  single-DM-view loop is solid.
- **How map geometry (walls, terrain, non-flat spaces) gets authored.** The 2D
  app's line-of-sight system works against 2D wall segments on a flat map; a real
  3D equivalent (3D wall meshes? a heightmap? hand-built scenes per encounter?) is
  an open question, not yet started.
- **Asset pipeline specifics** (which glTF/format conventions, LOD strategy,
  animation rig standard) -- deferred until real (non-placeholder) assets are
  actually being brought in.
