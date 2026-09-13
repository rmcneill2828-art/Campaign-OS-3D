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

Phase 2 complete for models/floor/animation above. One item from this phase
remains explicitly open (not silently dropped):

- [x] **Animation.** Done 2026-09-11, verified live (user-confirmed) after
  two follow-up fixes. Downloaded Quaternius's free "Universal Animation
  Library" (v1 and v2; only v1's non-root-motion `UAL1_Standard.glb` is used,
  see `godot/assets/README.md`). Verified by direct comparison (not assumed)
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
  tween's duration and back to Idle after, and the token now turns to face
  its actual direction of travel (`_face_direction()`, via `look_at()`)
  before the move tween starts.
  **Two follow-up fixes from live testing, found via a one-time diagnostic
  `print()` that reports bone-map coverage and resolved animation names per
  token -- both real lessons, not guesses**:
  1. First run showed a perfect bone map (65/65, 55/55) but a frozen T-pose
     and `idle=NOT FOUND walk=NOT FOUND` -- the print()'s dump of the
     player's actual available animation names showed why directly: Godot's
     glTF importer strips a trailing `_Loop` from a clip's name and encodes
     that as the clip's own `loop_mode` property instead, so the real names
     are `"Idle"`/`"Walk"`, not `"Idle_Loop"`/`"Walk_Loop"`. One-line fix once
     the diagnostic showed the actual names -- no further guessing needed.
  2. Facing then worked (tokens turned toward their destination) but walked
     **backward** the whole way there, confirmed in every direction tested --
     the exact signature of `look_at()` pointing the node's -Z at the target
     while this specific model's authored "forward" is actually +Z. Fixed
     with `rotation.y += PI` after `look_at()`, documented as deliberate (this
     model's own quirk, confirmed by the symptom) rather than an arbitrary
     fudge factor.

- [x] **Walls -- superseded, not built as originally scoped.** The
  2026-09-11 planning pass below decided future maps are hand-authored Godot
  scenes, not a procedurally-generated board -- so a generic "wall.glb ring
  around the perimeter" script is the wrong shape of solution. Walls become
  part of building a map scene by hand (Phase 4) instead. Marked done-as-
  superseded rather than left as a dangling TODO nobody intends to pick up in
  its original form.

Phase 2 fully complete (including this item's resolution).

---

# Roadmap: Phases 3+ (planned 2026-09-11, after Phase 2)

A full-scope planning pass, now that Phases 0-2 have proven the core pipeline
(server-authoritative rules, real models/floor, animation) actually works.
Four decisions from that discussion shape everything below:

1. **Future maps are hand-authored Godot scenes** (real level design, built by
   hand from the Kenney kit pieces already in the project) -- not generated
   from the 2D app's own map data, and not a new in-app 3D map-builder tool.
   Most creative control; the cost is real per-map authoring effort and no
   automatic carry-over from an existing 2D campaign map.
2. **Mechanics before more visuals.** The engine already supports spells,
   conditions, class resources, rests, death saves, exhaustion, legendary/lair
   actions, and more -- none of it has 3D client UI yet (only move/attack/
   next-turn do). Wiring that up takes priority over further graphics work,
   since it's what actually makes this usable at a real table.
3. **Claude DM bridge integration is a real goal, but a later one.**
   `engine-server`'s HTTP action API already speaks the exact vocabulary the
   2D app's bridge uses, so this should be a natural fit when its turn comes
   -- just not before the manually-driven UI (Phases 3-6) exists.
4. **Art investment gets its own later, explicit phase** rather than being
   opportunistic or urgent -- revisit once the feature set from the phases
   below feels worth dressing up, not before.

## Phase 3 -- Core mechanics UI (next up)

Ordered roughly by how often each comes up at a real table, so the most
valuable gaps close first:

- [x] **Ability checks / saving throws.** Done 2026-09-12, verified live
  (user-confirmed). A "Token Actions" panel (top-right of the HUD) with two
  rows: a 6-item ability dropdown + "Roll Save" (sends `saving_throw`), and a
  24-item dropdown (6 abilities + the 18 named skills, matching
  `rollAbilityCheck`'s own "either works" contract) + "Roll Check" (sends
  `ability_check`), plus a shared DC spin box (default 10). Both act on
  whichever token is currently left-click-selected -- same selection model
  move/attack already use. `ABILITY_KEYS`/`SKILL_LIST` are duplicated into
  `Main.gd` from `engine/encounter.js`'s own copies -- same no-shared-module
  convention already covering this exact list across `encounter.js`/
  `campaign.js`/`dm-bridge/watch.js`.
  **Two real, unrelated gaps found live-testing this, both fixed the same
  session**:
  1. There was no way to deselect a token once picked at all -- found while
     the user tried to test the "nothing selected" hint. Added three ways to
     deselect (click past the board, click the already-selected token again,
     Escape), plus mentioning Esc in the selection status line.
  2. The hint message itself then turned out to disappear almost instantly --
     it shared `_status_label` with the ongoing map/round/log text, which the
     1-second poll cycle overwrites unconditionally, giving a hint well under
     a second of real visibility. Split it into a separate `HintLabel` +
     3-second one-shot `HintTimer` (`_show_hint()`), used by every other
     one-off "you just tried something" message too (failed attack-target
     selection, action-send failure, action-failed response) -- not just the
     one that surfaced it.
- [x] **Conditions.** Done 2026-09-12, verified live (user-confirmed). The Token
  Actions panel gained a 3-column grid of 11 toggle buttons (one per
  `conditionList` entry), reflecting and toggling the currently selected
  token's real `conditions` array via `toggle_condition` -- built dynamically
  in `Main.gd`'s `_ready()` (not hand-authored per-button in the .tscn, given
  there are 11 of them) and kept in sync from server state every poll via
  `set_pressed_no_signal()` (the plain `button_pressed` property would
  re-emit `toggled` and loop back into sending a spurious action on every
  tick). The visual indicator lives on the token itself, not a separate
  overlay: `Token.gd`'s existing name/HP label now appends a comma-joined
  conditions line when any are active (e.g. "Darkhawk\n91/91 HP\nProne,
  Poisoned") -- a text tag rather than icons, the simpler of the two options
  the roadmap named, revisit for icons later if a text tag doesn't read well
  at the table.
- [x] **Spellcasting.** Done 2026-09-12, verified live (user-confirmed). The
  largest single UI addition so far -- surprisingly needed only one real
  follow-up fix, and it wasn't in this feature's own UI code (see below).
  Also prompted a scroll-view refactor of the whole Token Actions panel
  refactor of the whole Token Actions panel (`TokenActionsScroll`, a
  `ScrollContainer`) since Phase 3's remaining items (resources, rests,
  death saves, exhaustion/legendary/lair) would keep growing it past the
  screen otherwise -- every existing child node path in `Main.gd` shifted
  down one level accordingly.
  - **Cast (single target)**: spell name (text), level (0 = cantrip, spin
    box), an optional target dropdown (rebuilt from the real token roster,
    but only when that roster's names actually change -- rebuilding every
    poll would reset whatever the user was mid-way through picking, since
    OptionButton selection doesn't survive `clear()`), optional damage dice
    + damage type, and concentration -- sends `cast_spell`. A target left on
    "(no target)" is omitted entirely, matching a save-based spell like Hold
    Person that spends a slot without an attack roll.
  - **Cast (area, checked targets)**: shares the name/level/damage/damage-
    type/concentration fields above, adds a checkbox per token (same
    rebuilt-only-on-roster-change treatment), a save ability dropdown, save
    DC, and a "Half on save" checkbox (defaults on, matching `castAreaSpell`'s
    own `halfOnSave` default) -- sends `cast_area_spell`. Refuses to send
    with no damage dice or no checked targets (hinted, not silent), since
    both are meaningless for this action.
  - `DAMAGE_TYPE_LIST` duplicated from `encounter.js` (13 SRD types) with one
    client-side-only addition, `"(none)"`, since damage type is optional on
    both cast actions and the dropdown needs a way to mean "don't set one."
  **The one real gap found live-testing this wasn't in Main.gd at all**: saves,
  checks, and spell attacks for the prototype's seeded heroes (Darkhawk, Wren)
  all silently computed a flat +0, while a spawned goblin correctly showed its
  real -1 STR -- because `engine-server/server.js`'s `seedState()` had carried
  zero ability scores for either hero since Phase 0 (fine when all that
  existed was move/attack, invisible once Phase 3 put real rolls in front of
  a user). Not a bug in the engine (`savingThrowBonus()`/`abilityCheckBonus()`
  correctly fall back to +0 on sparse data, exactly as documented) or in
  today's UI -- fixed at the actual source: gave both prototype heroes real
  (invented, not the real campaign's actual sheets) ability scores, and gave
  Wren spellcasting stats + slots so `cast_spell`'s attack-roll path had a
  real bonus to exercise instead of always hitting "no stated spell attack
  bonus, skipped." Verified directly against a clean server instance
  (`Wren rolls a INT save: 15 +4 = 19`, `Wren's magic missile attacks Goblin 1:
  5 + 7 = 12`) before telling the user to trust it.
- [x] **Class resources, rests, death saves, exhaustion/legendary/recharge/
  lair, and the HP bar -- all built 2026-09-12 in one batch** (the user
  explicitly asked to get the rest of Phase 3's foundation in before another
  verification round, rather than one-item-at-a-time like the earlier Phase 3
  items) **-- needs live verification, budget for a real fixing pass**: this
  went in with no incremental checkpoint, unlike every earlier Phase 3 item.
  - **Class resources**: name field + "Use" only (sends `use_resource`) --
    deliberately no "Restore" control. Checked directly in `dmBridge.js`
    rather than assumed: `restoreResource()` has no bridge action at all,
    matching the 2D app's own asymmetry (its Restore button calls the engine
    function straight from UI code, bypassing the bridge entirely, since
    restoring mid-scene is a DM correction rather than something narration
    would ever request).
  - **Rests**: Long Rest / Short Rest buttons, sending `long_rest`/`short_rest`.
  - **Death saves**: a "Roll Death Save" button, sending `roll_death_save` --
    left ungated on the token's own dying status since the engine already
    treats calling it on a non-dying token as a safe no-op, not an error.
  - **Exhaustion**: +1/-1 buttons sharing one handler (`add_exhaustion` with a
    signed `amount`).
  - **Legendary actions**: a "Use Legendary Action" button (cost omitted,
    server defaults it to 1).
  - **Recharge abilities**: free-text name field + "Use" (`use_recharge_ability`)
    -- no fixed list exists (these are named per-monster), same free-text
    pattern as the spell name field.
  - **Lair action**: free-text description + "Trigger" (`trigger_lair_action`)
    -- the one control on this whole panel that is deliberately NOT gated on
    a token selection, since a lair action fires against the whole encounter
    (RAW initiative count 20), not any one creature's turn.
  - **Death/hit-reaction animation**: `Token.gd` now plays `Death01` once when
    a token's real `dead` flag (not a bare hp<=0 check -- a token can sit at
    0 HP mid-death-saves without being `dead` yet) flips true, and a random
    `Hit_Chest`/`Hit_Head` clip whenever HP decreases while still alive --
    both clips were already sitting unused in the Phase 2 animation pack.
    Death freezes on its final pose; a hit reaction hands back to Idle once
    it finishes playing (`AnimationPlayer.animation_finished`).
  - **HP bar**: a real 2-quad billboarded bar above each token (green/yellow/
    red by ratio), added alongside the existing text label rather than
    replacing it. Uses a wrapper-node scaling trick so it drains from the
    right with a fixed left edge, not shrinking from both sides. Each
    instance gets its own fresh material at `_ready()`, not the `.tscn`'s
    shared sub-resource -- the same shared-resource gotcha this project
    already hit once with animations would otherwise recolor every token's
    bar together.
- [x] **Panel redesign, HP bar visibility, and dying/kneeling pose --
  2026-09-12, live-tested and verified (user-confirmed) with one follow-up
  feature request from that same test pass.**
  - **Collapsible sections.** The single flat Token Actions list (getting
    "really large" per live feedback, with its left edge cut off on the
    user's actual window size) was split into 5 collapsible sections --
    Checks, Conditions, Spells, Resources, Other (death save/exhaustion/
    legendary/recharge/lair) -- each a header `Button` (`toggle_mode = true`,
    `▸`/`▾` prefix) over a body container whose `visible` mirrors the
    header's pressed state, wired through one `_wire_collapsible_section()`
    helper rather than five near-duplicate blocks. `StatusLabel`/`HintLabel`
    switched from a fixed `offset_right = 900` (silently assuming a
    1600px-wide window) to a responsive `anchor_right = 1.0, offset_right =
    -380`, fixing the reported cut-off left edge.
  - **HP bar visibility.** Reported "hard to see" -- repositioned clearly
    above the name label (was overlapping it) and enlarged (background
    0.8x0.1 -> 1.1x0.22, fill 0.8x0.08 -> 1.0x0.16) with a darker background
    for contrast.
  - **Death animation "not working" turned out not to be a bug.** The
    reported case was a token dropping to 0 HP and starting death saves --
    "dying," not "dead" under real 5e rules, which this engine already
    applies correctly (`Token.gd` already gated `Death01` on the real `dead`
    flag, not a bare `hp<=0` check, since the batch item above). Verified by
    asking the user to actually carry a token to a real death before
    concluding anything was broken; confirmed working once they did.
  - **New feature from that same test pass**: "make the model kneel down
    when it is making death saving throws." Added a persistent
    `Crouch_Idle` pose (not `Fixing_Kneeling`, also in the same Quaternius
    pack -- `Crouch_Idle`'s own `_Loop`-suffixed source name is what marks it
    as authored to be held indefinitely, the same signal already relied on
    for Idle/Walk) driven by the engine's own `dying` field (present -- a
    `{successes, failures, stable}` dict -- whenever a token is actively
    rolling death saves or already stabilized-but-still-down; both look the
    same kneeling, matching RAW: stabilized just means no longer rolling, not
    back up). `Token.gd`'s animation-priority logic now reads dead > dying >
    hit-reaction > idle/walk, edge-triggered off `_was_dying` so the pose
    isn't re-triggered every poll while nothing changed, and a token healed
    back up out of dying stands back into Idle. Also covers the edge case of
    a dying token being moved (a DM dragging an unconscious creature) via a
    new `_resume_idle_or_dying()` helper, so the move-tween's finish doesn't
    pop it back onto its feet mid-death-saves.
- [x] **Healing -- 2026-09-12, a real gap found only after everything above
  ("i just realised there is no way to heal anyone").** Phase 3's original
  batch built every other HP-affecting control (damage arrives for free via
  attack/spells, death saves, exhaustion, rests) but never actually wired up
  `apply_healing`, even though the engine/bridge already fully support it
  (checked directly in `dmBridge.js`, not assumed -- confirmed present
  alongside `apply_damage`, both already copied into `engine-server` since
  Phase 0). Added a Heal row to the Resources & Rests section: an amount
  spin box + Heal button (`apply_healing` with that amount), and a Full Heal
  button that sends a deliberately oversized amount (`9999`) rather than the
  client needing to know the target's real max HP -- `applyHealing` already
  clamps to `maxHp` server-side. Healing back above 0 HP also clears
  `dying`/`dead` server-side (a deliberate revival, per the engine's own
  comment -- Revivify, Raise Dead, a DM ruling, no different from a manual
  HP edit), so this doubles as the un-kneel/revive control for the pose
  added just above, not just a top-up for an already-conscious target.
  Verified directly against a live server instance before wiring the UI
  (lethal damage -> `dying` set -> partial heal clears `dying` and restores
  HP -> full heal clamps exactly to `maxHp`), same discipline as the
  ability-scores fix earlier in this phase.
  **One follow-up bug found live-testing this, reported as "a kneel token
  stands up [when healed], a downed one doesn't":** confirmed by testing
  directly against a live server instance that this was a client-side
  animation bug, not correct behavior -- `applyHealing` already revives a
  fully dead token server-side (clears `dead`, restores HP) when healed
  above 0, by design (there's no separate "revive" action; the same generic
  Heal button represents Revivify/Raise Dead/a DM ruling too). `Token.gd`'s
  animation logic only handled the dying->idle stand-up transition, not a
  dead->idle one, so a token revived directly from `dead` (without passing
  back through `dying` first) stayed visually frozen on `Death01`'s last
  frame even though the server had already correctly brought it back. Fixed
  by also standing a token up out of a frozen death pose whenever `is_dead`
  goes false while `_was_dead` was true.

## Phase 4 -- Hand-authored maps

Directly resolves Phase 2's deferred "Walls" item (see above) -- once maps
are hand-built scenes, walls are just part of building the scene, not
something a generic script generates.

- [x] **Map-scene contract -- 2026-09-12, built.** `GridManager.build()` now
  takes an optional `map_scene_path`: given one, it instantiates that scene
  as the board's visual (floor/walls/props) and skips its own procedural
  floor generation entirely -- but ALWAYS still builds the invisible
  collision plane and the grid-line overlay itself, exactly as planned, so a
  hand-built map only needs to be geometry and never has to reimplement
  click-to-move raycasting or grid readability. An empty/unregistered path
  falls back to the original fully-procedural floor unchanged, so any future
  map with no hand-built scene yet still renders something. `Main.gd` owns
  the name -> scene-path lookup (`MAP_SCENES`, a plain dict -- literally the
  "simple name -> scene-path mapping" this item called for), resolved fresh
  every `_apply_state()` off the server's real `mapName` -- this doubles as
  the map-switching wiring too (see below), since a mapName change just
  naturally resolves to a different path or "" on the very next poll with no
  separate `switch_map`-specific code needed.
- [x] **One real example map, replacing "Prototype Chamber" -- 2026-09-12,
  built and verified live in Godot (user-confirmed, "looks good").**
  `godot/scenes/maps/prototype_chamber.tscn`:
  a real 12x8 room (matching the server's seeded size exactly) built from
  Kenney dungeon-kit pieces -- full Kenney floor/floor-detail tiling inside,
  a solid `wall.glb` ring one cell outside the playable area (so it can
  never overlap a cell a token could stand on), `column.glb` at the 4
  corners, a `wall-opening.glb` gap centered on the south wall as the room's
  entrance, and `chest.glb`/`barrel.glb` props tucked into the 4 inner
  corners (deliberately not the center, which a battle map needs clear for
  actual token movement/combat). Generated by a script
  (`godot/tools/build_prototype_chamber.gd`), not the editor GUI (not
  drivable interactively in this session) -- but still a genuinely
  hand-authored map in the sense the planning pass meant: every wall/door/
  prop position below is an explicit layout decision this script bakes in
  cell-by-cell, not a generic "wall ring around whatever size a map happens
  to be" algorithm GridManager itself runs. See `godot/tools/README.md` for
  how to build a second map the same way.
  **Verified two ways before calling this done, given the Godot editor GUI
  itself isn't drivable from this session**:
  1. Every piece's placement math was checked directly against the saved
     scene file's own raw transform values (`grep`), confirmed to exactly
     match `cell_to_world()`'s own `(x-0.5)*cell_size` formula for every
     wall/corner/door/prop position -- not assumed to generalize from one
     spot-checked example.
  2. Every piece's real footprint/height was measured first via a new
     headless tool (`godot/tools/measure_pieces.gd`, run against the user's
     actual Godot 4.7.2 install headlessly), the same "measure the real
     thing, don't trust assumptions about it" discipline `GridManager`/
     `Token.gd` already apply at runtime -- confirming e.g. `wall.glb` is a
     1x1-footprint, 1.1-unit-tall block with its origin already at its own
     base (no grounding correction needed, unlike `chest.glb`, which sits
     0.05 units below its own origin and got an explicit correction).
  **Known gap, deliberately not chased further this session**: a
  headless-script sanity check that tried to sum up the whole room's
  rendered bounding box hit an unexplained Godot quirk where nested scene
  instances' `global_transform` came back as identity even after
  `force_update_transform()`, in this bare-`SceneTree` context specifically
  -- worked around by checking local transforms directly instead (which
  did confirm the room's overall footprint is exactly right: `x=[-2,26]
  z=[-2,18]`, matching the 12x8 interior plus its wall ring). This doesn't
  affect the actual generated scene file (already independently confirmed
  correct by direct text inspection), only a throwaway diagnostic script,
  which was deleted rather than debugged further.
  **Confirmed live in Godot from a real screenshot**: the full wall ring
  renders solid and correctly proportioned relative to the tokens standing
  inside it (roughly 2-3x token height, reads as a real room, not an
  oversized or cramped one); the door opening (`wall-opening.glb`) renders
  as a visually distinct arch, clearly different from the plain wall blocks
  around it, in the correct position; all 4 corner columns and all 4 corner
  props (2 chests, 2 barrels) are visible in their intended spots with no
  floating/sinking; floor tiling (plain + detail variant) fills the room
  edge-to-edge with the grid-line overlay still reading clearly on top; and
  the existing tokens (Darkhawk, Wren, 2 goblins) render correctly inside
  the new room with their HP bars/labels intact, unaffected by the switch
  from a procedural to a hand-built floor. No follow-up fixes needed.
- [x] **Second hand-built map: "Entrance Hall" (entrance -> corridor -> room)
  -- 2026-09-13, built; pending live visual verification.** User request:
  "lets build a simple dungeon from scratch - entrance , corridor and room."
  Built from 8 Higgsfield "3D Jutsu" catalog pieces (see `godot/assets/
  README.md`'s Higgsfield section) instead of Kenney, reusing the exact same
  "measure the real thing, generate the scene via script, verify against the
  saved `.tscn`'s raw transforms" discipline as Prototype Chamber above:
  - `godot/tools/measure_higgsfield_dungeon.gd` measured all 8 pieces' real
    AABBs first, confirming Higgsfield's modules are natively 4m x 4m --
    exactly 2x2 of this project's own 2m grid cells at 5 ft/square.
  - `godot/tools/build_entrance_hall.gd` composes them into
    `res://scenes/maps/entrance_hall.tscn` (21 nodes): a self-contained arch
    doorway (entrance, module row 1), a self-contained straight corridor
    (module row 2), a 2x2-module room (4 floor tiles) south of it, its walls
    built from separate wall/corner/doorway pieces (the room's south wall
    has a doorway aligned with the corridor -- its one real connection --
    and a solid segment on the other half), plus 2 torches and 1 treasure
    chest as props.
  - `MapScenes.gd`'s `SCENES` dict now has an "Entrance Hall" entry; a
    Godot headless smoke test (`godot/tools/smoke_test_entrance_hall.gd`)
    confirms `MapScenes.resolve("Entrance Hall")` resolves to a real,
    loadable scene with exactly the expected 21 children.
  - `engine-server/server.js`'s `seedState()` registers "Entrance Hall" as a
    **second** map (4 columns x 8 rows) alongside Prototype Chamber, with 6
    real wall segments matching the built geometry exactly (both sides of
    the entrance/corridor tunnel, the room's 3 solid walls, and the room's
    south wall's solid half) -- deliberately does NOT call `setActiveMap` on
    it, so Prototype Chamber stays the default and Entrance Hall is only
    reached via `switch_map` (through the DM Assistant or a manual action).
    3 new tests in `engine-server/tests/entranceHall.test.js` confirm the
    map is registered without becoming active, that `switch_map` actually
    moves between the two maps and back, and -- most importantly -- that
    real line-of-sight is blocked through the solid wall sections and open
    through the one doorway that connects the corridor to the room. All 19
    engine-server tests pass (was 16).
  **The "floor level" saga -- 2026-09-13, several real but incomplete fixes
  before finding the actual root cause.** User feedback after switching to
  the map live: "looks good - only issue is floor level." What followed
  was three rounds of genuine, verified-at-the-time fixes that each turned
  out not to be the real cause, followed by the actual answer:
  1. **Room floor sat ~0.2m too high.** `dun_room_floor` is a genuinely
     free-standing floor tile; re-measuring (with the still-buggy
     measurement approach at the time, see step 4) suggested its walkable
     top sat 0.198m above the grid plane. Fixed by offsetting it down --
     a real, still-correct fix, but not the cause of the reported visual.
  2. **The camera never re-centered on a map switch.** `_camera_centered`
     in `Main.gd`/`PlayerView.gd` was a one-shot flag: it centered the
     camera once, on whichever map first loaded after connecting, and
     never again. With only one map that was invisible; the moment a
     second, differently-sized map (Entrance Hall) existed, the camera
     stayed locked on Prototype Chamber's old center. A real bug, fixed by
     tracking the last map name centered on and re-centering on every
     change -- but still not the cause of the reported visual.
  3. **A live marker test that gave a misleading "matches" result.** After
     both fixes above still didn't resolve it, a throwaway debug map
     floated opaque markers a fixed 0.5m above y=0 over the tunnel and the
     room separately, and the user judged both to hover the same height
     above their own floor. In hindsight this comparison was unreliable --
     judging relative height between two markers at different distances
     and against walls of different heights is exactly the kind of depth
     perception a human eye gets wrong, the same category of illusion this
     whole investigation kept (wrongly, in the end) reaching for as an
     explanation.
  4. **The actual root cause: every measurement tool in this pipeline was
     silently wrong.** What actually broke the case open was real tokens
     (goblins spawned by the DM assistant) landing at server-verifiable
     grid coordinates right at the corridor/room threshold, rendering at
     roughly WALL-TOP height over a visibly deep, dark, genuinely-textured
     recess -- not a perspective illusion, not a void gap, a real recessed
     floor. Investigating the doorway piece's own geometry directly (see
     `godot/tools/README.md`'s fourth gotcha for the full technical story)
     found it: `measure_higgsfield_dungeon.gd` had been using
     `MeshInstance3D.global_transform` in a bare `--script` `SceneTree`
     tool, which silently returns a WRONG (not identity, not an error --
     just plausible-looking wrong) transform for any node with real
     translation in its own nested wrapper hierarchy, because a bare
     `--script` tool never gets the real process frame Godot needs to
     propagate a freshly `add_child()`-ed node's transform down through
     its children. Every one of the 8 Entrance Hall pieces has that kind
     of nesting. The tool had been reporting every piece as flush-bottom
     at y=0 the entire time; the corridor/arch modules are actually
     vertically CENTERED on their own origin, so their real floor sat
     1.27m underground from the very first build -- and so did every
     wall/corner/torch/chest's true ground offset, all wrong in the same
     way, all "confirmed correct" by the same broken measurement.
  **The real fix**: rewrote `measure_higgsfield_dungeon.gd` to manually
  compose each mesh's real world transform by walking `get_parent()` up
  to the root (plain already-resolved `Transform3D` multiplication, no
  lazy propagation involved, correct with zero process frames) instead of
  trusting the cache, re-measured all 8 pieces, and corrected every entry
  in `build_entrance_hall.gd`'s `PROP_GROUND_OFFSET` dict -- not just the
  ones that had looked wrong. Verified with a second, equally
  transform-bug-free diagnostic that every piece now sits genuinely flush:
  tunnel modules' floors at y=0, walls' bases at y=0, room floor's
  walkable top at y=0. Regenerated `entrance_hall.tscn`, re-ran the
  headless smoke test (still 21/21 children, loads clean). All debug
  scaffolding from steps 3-4 (the debug map, its supporting headless
  tools, temporary `MapScenes.gd`/server map entries) removed once
  resolved. The room-floor fix from step 1 and the camera fix from step 2
  both remain in place -- genuinely correct, independently useful fixes,
  just not the ones that mattered here.
  **Lesson for next time, now documented as this project's most severe
  headless-tooling gotcha** (`godot/tools/README.md`): never trust
  `global_transform` in a bare `--script` tool for anything with
  meaningful scene nesting, especially anything that went through
  `fix_higgsfield_vertex_colors.gd`'s wrapper-adding process -- manually
  compose local transforms instead, from the start, not after guessing
  wrong for a whole map.
  **Known unverified guesses, flagged for a live look rather than assumed
  correct** (same "build first, verify from a real screenshot, fix from
  there" pattern Prototype Chamber and every KayKit/Meshy/Higgsfield model
  used): the 4 room corner pieces' rotations (0/90/180/270, the most
  defensible guess without being able to see which way the piece is
  actually authored to face); the 2 torches' wall-mounting rotations; and a
  known, deliberately-accepted **gap**, not a bug -- the tunnel (entrance +
  corridor) is only 1 module (2 cells) wide while the room is 2 modules (4
  cells) wide, so cells x=3-4 for rows y=1-4 fall inside the engine's
  rectangular columns x rows grid bounds but have no rendered floor/walls at
  all (an "L-shaped void"). Left alone rather than engineered around -- a
  token would only end up there via deliberate DM action, matching this
  project's existing pattern of accepting known low-priority limitations
  rather than preemptively solving problems nobody has hit yet.
- [ ] Per-map lighting/mood (a hand-built room may want its own atmosphere --
  torches, color grading -- rather than the single fixed sky+sun every map
  currently shares) -- not started; both existing maps still use the one
  shared sky+sun every map has had since Phase 0.

## Phase 5 -- Line of sight / fog of war in 3D

The "raycast against 3D wall meshes vs. an abstract wall-segment list"
question this phase used to be waiting on turned out to already be settled:
`engine/encounter.js` (copied verbatim into `engine-server` since Phase 0)
already has a complete, tested line-of-sight/fog-of-war system --
`addWall`/`removeWall`/`clearWalls`, `hasLineOfSight`, `cellVisibleToHero`,
`isVisibleToParty`, `visibleCellsForParty`, `revealVisibleTiles`, `resetFog`
-- all working against abstract 2D wall segments in grid VERTEX space, the
exact same model the 2D app's own DM canvas and Player Window already use.
No new LOS math needed writing at all; this phase is entirely about wiring
real data through it.

**Scope decision (2026-09-12):** checked the 2D app's own precedent before
building anything -- its DM canvas (`ui/app.js`) never dims/hides anything
for itself; fog rendering only exists in the separate Player Window
(`ui/playerView.js`), which is this project's own Phase 6, not this one.
Given that, this phase deliberately stops at making the DATA real and
correct -- it does NOT change what the current (DM) 3D client renders,
matching the 2D app's actual DM/Player split rather than guessing a fog
rendering scope the precedent doesn't support. Fog/LOS-driven rendering is
Phase 6's job, once a real player-facing view exists to put it in.

- [x] **Real wall segments for "Prototype Chamber" -- 2026-09-12, built and
  tested.** `engine-server/server.js`'s `seedState()` now calls `addWall()`
  five times, tracing the exact same room shape
  `godot/tools/build_prototype_chamber.gd` built in 3D: a solid perimeter
  around the full 12x8 playable area with a gap in the south wall at the
  same vertex range the 3D scene's own door opening sits (vertex x 6..7,
  matching `DOOR_COLUMN=7`). No shared source between the two definitions --
  same duplicated-by-hand convention this codebase already accepts for
  `ABILITY_KEYS`/`SKILL_LIST`/etc. across `encounter.js`/`Main.gd`; a
  comment on each cross-references the other file directly. Without this,
  `hasLineOfSight` would have nothing to test against and stay vacuously
  true everywhere (`encounter.js`'s own documented "no walls drawn" fast
  path) -- the door/room shape existing in 3D didn't mean the ENGINE knew
  about it at all until this.
- [x] **Visibility wired into the API -- 2026-09-12, built and tested.**
  Every `GET /state`/`POST /action`/`POST /reset` response now carries a
  `visibility: { mapName, currentlyVisible, revealed }` field alongside
  `state` -- `currentlyVisible` freshly computed each call from
  `visibleCellsForParty` (the party's real-time line of sight), `revealed`
  read back from `state.maps[mapName].revealedTiles` (the persisted
  "explored" memory). `POST /action`/`POST /reset` also now call
  `revealVisibleTiles()` before saving, the same choke-point pattern the 2D
  app's own `saveEncounter()` uses -- every mutation folds newly-visible
  cells into permanent memory, so nothing about switching to hand-built maps
  changed how exploration bookkeeping works.
  **Verified with 4 new tests (`engine-server/tests/visibility.test.js`),
  all behavioral, not just "returned 200"**: the seeded wall list matches
  the 3D room's shape segment-for-segment (not just a count); a straight
  line through the solid north/south wall sections is correctly blocked
  (`hasLineOfSight` called directly, the same way `cellVisibleToHero` does)
  while the exact same test through the door's vertex gap is correctly open;
  `revealed` starts empty and accumulates real cells after a `move_token`
  action, then survives a fresh `GET /state` reload. 10/10 tests passing
  (6 pre-existing + 4 new).
- [ ] Not built this phase, deliberately (see the scope decision above): any
  change to what the current 3D client actually renders. The DM's board
  still shows every token/tile unconditionally, matching the 2D app's own
  DM-canvas precedent. Revisit once Phase 6 gives a player-facing view
  something to actually consume this data for.

## Phase 6 -- Player-facing view

A 3D equivalent of the 2D app's Player Window (same-machine, read-only,
second monitor/TV) -- this is what Phase 5's visibility data was actually
for. Checked `ui/playerView.js` directly before building anything, rather
than guessing what "player-facing" should mean: read-only (no editing, no DM
panels, no Claude bridge), two independent filters before anything renders
(`hiddenFromPlayers` always wins; `isVisibleToParty` line-of-sight otherwise),
a rough color-banded HP bar instead of exact numbers, no on-map name text
(only a hover tooltip there -- full names only ever show in the initiative
list), full unredacted combat log (a documented, accepted 2D-app gap, not
something to silently "fix" here and risk getting subtly wrong), and a
three-state fog overlay (never explored / explored-but-not-currently-visible
/ currently visible) gated on the map actually having walls drawn at all.

- [x] **Server: `visibleTokenIds` -- 2026-09-12, built and tested.**
  `engine-server/server.js`'s `computeVisibility()` (Phase 5) now also
  returns `visibleTokenIds`: every token on the current map passing the
  EXACT same two-filter rule `ui/playerView.js`'s own `renderMapGrid()`
  applies (`!hiddenFromPlayers` then `isVisibleToParty`) -- read directly off
  the real engine functions, not reimplemented, so this can't drift from
  what the 2D app actually does. 3 new tests: everyone visible by default in
  the open room; `hiddenFromPlayers` hides and un-hides live; a token behind
  a real interior wall (added via the exact `add_wall` dmBridge action a
  DM's Walls tool uses) drops out and reappears once the wall is removed via
  `remove_wall_near`. 13/13 tests passing total.
- [x] **A real second, read-only 3D client -- 2026-09-12, built.**
  `godot/scenes/PlayerView.tscn` + `godot/scripts/PlayerView.gd`: its own
  independent poller against `GET /state` (never pushed to by the DM
  window -- same "a second independent poller beats one window pushing into
  another" reasoning `dm-bridge/watch.js`'s own poll loop already
  established for this project), reusing the same `GridManager`/map-scene
  contract (factored the small `MAP_SCENES` dict out of `Main.gd` into its
  own `res://scripts/MapScenes.gd` so both clients resolve a map name to the
  same hand-built scene, rather than accepting drift risk between two copies
  in the same language/project -- unlike the ABILITY_KEYS-style duplication
  this codebase accepts BETWEEN `encounter.js` and GDScript, where no shared
  import mechanism exists at all) and the same `Token.tscn`/`Token.gd`
  (a new `player_facing` flag, set only by `PlayerView.gd`, blanks the
  floating name/HP-number/conditions label -- the HP BAR mesh itself needed
  no change at all, it was already just a numberless colored quad, exactly
  the "rough bar, no exact numbers" middle ground `ui/playerView.js` already
  settled on). Only tokens in the server's `visibleTokenIds` are even
  instantiated -- not hidden-but-present, genuinely never created. A new
  `FogRoot` builds the three-state fog overlay fresh each poll as flat
  semi-transparent quads (never-explored solid-black, explored-dimmed,
  currently-visible clear), the same "cheap enough to fully rebuild every
  poll" precedent `GridManager`'s own grid-line overlay already established
  -- entirely separate from `GridManager` itself, which stays exactly as
  Phase 5 left it (shared, unfogged, still what the DM's own window uses).
  A read-only side panel shows initiative (sorted the same
  `b.initiative - a.initiative || a.name.localeCompare(b.name)` way
  `sortByInitiative` does, with DEAD/DYING/STABLE badges) and the full
  combat log. No `POST /action` call exists anywhere in `PlayerView.gd` --
  not gated off, structurally absent -- so nothing clickable in this window
  can mutate the encounter no matter what.
- [x] **Launch mechanism -- 2026-09-12, built.** `Main.tscn` gained an "Open
  Player Window" button (top-level HUD, not inside the Token Actions panel)
  that instantiates `PlayerView.tscn` inside a real Godot `Window` node --
  the project's subwindows are already not embedded (Godot's own default),
  so this opens as a genuine, separately-draggable second OS window, the
  same "second monitor/TV" the 2D app's own button opens a second browser
  tab for. A second click re-focuses the existing window instead of
  spawning a duplicate; closing it clears the tracked reference.
  **Real, non-obvious gotcha hit and documented** (see
  `godot/tools/README.md`): a brand new `class_name` (`MapScenes`, added
  this same phase) isn't visible to anything -- including this project's own
  headless smoke-test tools -- until the project's global class cache has
  been rebuilt, which normally happens automatically on a real editor
  session but not from a bare `--headless --script` run. Worked around with
  one headless editor pass (`--headless --editor --path godot --quit`) to
  force the rescan before re-verifying.
  **Verified live in Godot, 2026-09-12 (user-confirmed, "everything looks
  good")**: on top of both scenes instantiating headlessly with no
  script/parse errors (`godot/tools/smoke_test_main.gd`,
  `smoke_test_player_view.gd`), the DM confirmed the real, human-only checks
  a headless run can't cover -- the second window opens as genuine, separate,
  draggable screen real estate; the board/tokens/fog/redacted labels/
  initiative panel all render correctly together; and the player window
  updates independently of the DM's own window as the encounter changes.

Phase 6 complete.

## Phase 7 -- Claude DM bridge integration

Read `dm-bridge/watch.js` and `ui/app.js`'s own bridge code directly before
building anything, rather than re-deriving the protocol from the action
vocabulary alone -- `POST /action` accepting the same actions was necessary
but not sufficient; the actual bridge is a file-based IPC loop (write
`request.json`, poll `response.json`) with a very specific request shape
`watch.js`'s `buildPrompt()` expects, and a SYSTEM_PROMPT/action-validation
pipeline already fully implementing 5e's move/attack/spell/rest/death-save/
exhaustion/legendary-action rules text. None of that needed reimplementing.

- [x] **`dm-bridge/watch.js` copied verbatim -- 2026-09-13, built.**
  Byte-for-byte identical to Campaign-OS's own copy (same "copied verbatim,
  never hand-edited" convention as `engine/encounter.js`/`engine/dmBridge.js`)
  -- it has no idea whether a browser or this project's own server wrote its
  `request.json`, or whether an HTML page or a Godot window reads its
  `response.json`. `DND_REPO_PATH`-gated features (End Session, Create/
  Update Character -- writing to the actual DND campaign repo) degrade
  gracefully if unset and needed zero changes either; **not wired up from
  Godot this phase** (no free-text session-transcript concept exists in this
  client yet) -- a real, explicitly scoped-out gap, not silently dropped.
- [x] **`engine-server`: `POST /dm-command` -- 2026-09-13, built and tested.**
  One round trip does everything `ui/app.js`'s `sendDMBridgeCommand()`/
  `checkDMBridgeResponse()` pair does across two separate browser-side
  polling loops: write `dm-bridge/request.json` in the EXACT shape
  `buildPrompt()` expects (a new `buildBridgeStateSnapshot()`, ported
  field-for-field from `ui/app.js`'s own function of the same name -- grid,
  wallCount, round, activeToken, lairActionUsedThisRound, availableMaps, and
  a full per-token line covering abilityScores/spellSlots/resources/
  hitDice/resistances/concentration/dying/exhaustion/legendaryActions/
  visionRange/hiddenFromPlayers), poll `response.json` for a matching `id`
  (same ~1s cadence, 120s timeout matching `ui/app.js`'s own 2-minute give
  up), then apply the returned actions through the exact same
  `DMBridge.applyActions` the plain `/action` endpoint already uses, fold in
  `revealVisibleTiles` the same way, and hand back updated `state` +
  `visibility` in one response. Doesn't block the server's event loop while
  waiting -- `GET /state` and ordinary `/action` calls keep working normally
  during the up-to-2-minute wait.
  **Tested without needing a real `claude` CLI call** (not something to
  depend on for a fast, deterministic, free test suite): 3 new tests isolate
  the actual integration surface this server owns -- `request.json` matches
  `buildPrompt()`'s expected shape field-for-field, a simulated
  `response.json` (the exact shape the real, unmodified `watch.js` would
  produce) gets correctly picked up and applied through the real engine, and
  an empty command is rejected before ever writing a request. 16/16 tests
  passing total.
- [x] **Godot: a DM Assistant panel -- 2026-09-13, built.** A new
  collapsible "DM Assistant (Claude)" section on `Main.tscn` (same pattern
  every other Phase 3 section uses) -- a free-text line, a Send button, and
  a response label. Deliberately not gated on a selected token (narration is
  scene-wide, same as `trigger_lair_action`), and uses its OWN in-flight
  flag separate from ordinary actions' -- a Claude round trip can take up to
  ~2 minutes, and there's no reason Attack/Cast Spell/Next Turn should be
  blocked from working the whole time just because a narration command is
  also pending. On a successful response, refreshes the board immediately
  from the returned `state` rather than waiting for the next poll tick.
  **Verified live end to end, 2026-09-13 (user-confirmed).** One real
  snag on the way, worth recording: the first live attempt hit `HTTP 404`
  on `/dm-command` -- not a bug in the new code, but the user's already-
  running `node server.js` process predating this phase's changes (Node
  doesn't hot-reload). Restarting it picked up the new route immediately.
  Once running, the full 3-process stack (`node server.js` +
  `node dm-bridge/watch.js` + Godot) worked exactly as designed: typing
  "Three goblins emerge from the trees" in the DM Assistant panel produced
  a real Claude response ("Three goblins emerge from the trees, joining the
  fray!") and three real goblin tokens spawned on the 3D board via the
  actual engine (each with its own real 7/7 HP bar, matching the SRD
  goblin stat block), with the board refreshing immediately, no extra poll
  tick needed.

Phase 7 complete.

## Phase 8 -- Art investment

Free Quaternius/Kenney/KayKit assets proved the pipeline in Phase 2 and
filled real gaps (see the Creatures/ catalog in `godot/assets/README.md`).
This is where to evaluate paid asset packs or bespoke/commissioned art, and
where to close out remaining free-asset gaps -- a research pass on
2026-09-11 already surveyed the real paid/AI options, recorded below so it
doesn't need re-doing.

- [x] **KayKit Skeletons wired into `Token.gd` -- 2026-09-13, built and
  tested.** The obvious, free, zero-risk starting move once this phase
  actually began: every monster had rendered as the generic Imp regardless
  of its real SRD stat block since Phase 2, a known, explicitly documented
  gap, and the KayKit Skeletons pack (already downloaded, genuinely CC0) was
  sitting there specifically to fix it. `Token.gd`'s `MODEL_CONFIG` gained a
  two-tier lookup: a monster's real stat-block name (parsed from its token
  name, e.g. "Skeleton 2" -> "skeleton" -- the same name-matching convention
  `dm-bridge/watch.js`'s own `MONSTER_LIST` already uses) checked against a
  per-name entry first, falling back to the original generic "monster" (Imp)
  entry for anything without one -- so this is purely additive, not a
  reshuffle of existing behavior. Confirmed by testing BOTH paths
  functionally, not just the new one: a "Skeleton 1" token resolves its new
  per-name entry; a "Goblin 1" token (no specific entry) still resolves
  the original generic Imp family exactly as before, 55/55 bones, unchanged.
  Rig compatibility was verified directly first (`godot/tools/inspect_kaykit_skeleton.gd`:
  23/23 bones match across every KayKit animation file checked), exactly the
  check `godot/assets/README.md`'s own KayKit section had flagged as still
  outstanding since it was written -- not assumed from a shared "Rig_Medium"
  folder name. The pack's SKELETON-SPECIFIC clips (`Skeletons_Idle`,
  `Skeletons_Walking`, `Skeletons_Death`, `Skeletons_Inactive_Floor_Pose` for
  the dying/kneeling pose) drive idle/walk/death/dying -- a noticeably
  better thematic fit than a generic humanoid idle, found by listing the
  file's real clips rather than guessing one existed. Hit-reaction clips
  (`Hit_A`/`Hit_B`) don't exist in that same file, so `_setup_animation()`
  gained the ability to import a named clip's `Animation` resource from a
  SECOND animation file into the primary one's own animation library at
  runtime -- letting one `AnimationPlayer` play clips that actually live in
  two different imported files, without changing the bone-copying loop at
  all. Hit two real headless-tooling gotchas along the way, both now
  documented in `godot/tools/README.md` for next time: a brand new asset
  under a normally-scanned folder needs one headless editor pass
  (`--headless --editor --quit`) to actually get imported before
  `ResourceLoader` can see it (same fix as Phase 6's `class_name` gotcha,
  different trigger); and a bare `--script` `SceneTree` tool's `_init()`
  runs before any manually-added node's `@onready`/`_ready()` has actually
  fired, which crashed the first functional Token test until it became a
  real scene + `Node` script instead. **Verified**: 2 new functional test
  scenes (`test_skeleton_token.tscn`, `test_imp_token.tscn`) plus
  `smoke_test_main.gd` still passing; `engine-server`'s own 16/16 tests
  unaffected (this was a Godot-only change).
  **Verified live in Godot, 2026-09-13 (user-confirmed).** Model/texture
  render correctly, stands and animates properly. Death and revival both
  confirmed working too -- killing it produced a real collapsed-heap pose
  and healing it afterward correctly stood it back up, the exact
  dead-to-idle transition Phase 3 had to specifically fix generalizing
  cleanly to a whole new model family with no further changes needed.
  One real observation, checked rather than dismissed: the user didn't
  notice the kneeling/dying pose play before death. Confirmed via the
  engine code that this project has no "massive damage = instant death"
  rule -- a token always passes through `dying` first, even from a single
  overkill hit -- so the animation almost certainly did play; the likely
  explanation is that this pack's own dying pose
  (`Skeletons_Inactive_Floor_Pose`) and its death pose (`Skeletons_Death`)
  both read as "a skeleton collapsed on the floor," unlike the hero/Imp
  models where kneeling (upright) and death (a distinctly different
  collapsed pose) are easy to tell apart at a glance -- a real cosmetic
  quirk of this specific pack's pose choices, not a wiring bug (the dying
  key's resolution was already independently confirmed via the functional
  test above). Left as-is; revisit the specific pose choice later only if
  it actually causes confusion at the table.
  Adventurers (a real per-hero-name option, same pack family) and the
  KayKit Dungeon Remastered environment kit remain downloaded and cataloged
  only -- not wired up this pass.
- [x] **Custom-generated Orc via the Meshy API -- 2026-09-13, built.** The
  user's own Meshy trial, driven via the already-connected Composio
  integration (no separate API key setup needed -- `MESHY_*` tools were
  already available and active, 1100 credits at the start). First real test
  of "custom created models" as its own option alongside free packs, for a
  monster (Orc) neither Quaternius nor KayKit's free tiers cover.
  **Full pipeline, ~65 credits total, three real problems hit and fixed
  along the way rather than assumed away**:
  1. `MESHY_CREATE_TEXT_TO_3D_TASK`'s `generation_path: "fused"` (one-call
     geometry+texture) failed outright (`"Mode is a required field"`) --
     switched to the more basic `"preview"` path (geometry only) instead,
     which worked; not investigated further since the 2-step preview+refine
     flow works fine anyway.
  2. The preview came back in a fighting stance (fists clenched) despite
     `pose_mode: "t-pose"` being requested -- flagged to the user directly
     rather than assumed fine, with the actual live tradeoff (regenerate
     now vs. risk a bad rig later); the user chose to just try rigging it,
     which happened to work.
  3. **The real one**: rigging outright rejected the first attempt (over
     the 320,000-face rigging limit -- the raw preview was ~1,031,956
     faces), fixed with `MESHY_CREATE_REMESH_TASK` down to 30,000 -- but
     texturing had already been kicked off against the ORIGINAL high-poly
     preview in parallel, meaning the rig (low-poly) and the texture
     (high-poly) ended up on two different, incompatible topologies. Fixed
     by re-rigging the REMESHED geometry a second time, this time passing
     the already-generated texture image directly via
     `MESHY_CREATE_RIGGING_TASK`'s own `texture_image_url` field (which
     Meshy supports specifically for this) rather than trying to re-refine
     the remeshed geometry (confirmed by testing that refine only accepts
     an actual preview task, not a remesh one -- would have needed a third
     texture pass otherwise). One rigging task now correctly produces a
     rigged, skinned, AND textured result in one output.
  Six separate `MESHY_CREATE_ANIMATION_TASK` calls (one clip per file --
  Meshy's animation API returns one full skinned model per requested clip,
  not a shared multi-clip library file) supplied idle/walk/death/2
  hit-reactions/a kneel stand-in, picked from Meshy's own preset animation
  catalog after actually searching it rather than guessing what existed:
  confirmed no dedicated "death" or "held wounded/kneeling" pose category
  exists by name, but found real, usable picks anyway --
  `Fall_Dead_from_Abdominal_Injury` (sub-category "Dying") for death, and
  `Slow_Orc_Walk_inplace` for walk (the library visibly anticipates orc
  characters specifically). No good held kneel/dying pose exists in the
  library at all (checked directly) -- `Kneel_on_One_Knee_and_Stand` (a
  kneel-then-stand transition clip, not a true held pose) is used as an
  imperfect stand-in, looped the same way the other families' real held
  poses are.
  **`Token.gd`'s `MODEL_CONFIG` generalized to support this**: every
  animation field (idle/walk/death/dying, each `hits` entry) can now be
  either a plain clip name (the existing simple case) or a
  `{"clip": ..., "source": ...}` Dictionary naming a completely different
  file to import that one clip from -- the Orc needed this for literally
  every field, since each Meshy animation task produces its own separate
  file. This replaces (and generalizes) the skeleton family's earlier
  single-purpose `hit_source` field with the same mechanism, now reusable
  for any field, not just hits. Also confirmed and worked around a real
  Meshy-specific naming quirk: its clips come back pipe-delimited
  (`"Armature|Idle|baselayer"`), not the bare names every other pack here
  uses -- handled by using the full literal string as the config value, no
  code change needed once actually checked (`godot/tools/inspect_meshy_orc.gd`).
  **Verified**: bone-name compatibility checked directly (24/24 match
  across all 6 animation files -- expected, since Meshy retargets onto the
  exact rig it generated, but checked rather than assumed anyway), and a
  new functional test (`test_orc_token.tscn`) confirms every field
  (idle/walk/death/both hits/dying) resolves correctly end to end, all
  while the pre-existing skeleton and generic-monster (Imp) tests still
  pass unaffected by the generalization. `engine-server`'s own 16/16 tests
  unaffected (Godot-only change); "orc" already exists as a real SRD stat
  block server-side, so it's spawnable today.
  **Verified live in Godot, 2026-09-13 (user-confirmed): animations all
  correct** -- kneels and stands back up on saving throws (the dying
  stand-in reads fine in motion despite being a transition clip, not a
  true held pose), staggers on a hit, and collapses to the floor on
  death. **Texture was genuinely wrong, not a false alarm** -- a real
  camouflage-looking scramble, not the clean green-skin/leather result
  from the earlier preview thumbnail. Root cause confirmed rather than
  guessed: the rig had been built from the REMESHED (low-poly) geometry
  while the texture came from a `MESHY_REFINE_TEXT_TO_3D_TASK` run
  against the ORIGINAL high-poly preview in parallel -- remeshing
  regenerates UV coordinates for the new topology, so a texture image
  baked for the old UVs doesn't line up on the new ones, even though
  passing it via rigging's own `texture_image_url` field "worked" (no
  error, just visibly wrong). Fixed with the right tool for the job:
  `MESHY_CREATE_RETEXTURE_TASK` against the REMESHED task specifically
  (10 more credits) -- unlike refine, retexture generates a fresh
  texture matching whatever UVs the input model actually has right now,
  confirmed correct in a new preview thumbnail before spending anything
  further -- then one more rigging pass (5 credits) on that correctly
  textured result, reusing the same skeleton/animation files unchanged
  (they only ever contributed skeleton + one clip each to Token.gd,
  never their own visible mesh, so nothing about them needed
  redoing). Re-verified after the swap: bone map and all animation
  keys still resolve identically (24/24 bones, same clip keys) since
  only the visible mesh/texture changed, not the skeleton. Total cost
  for the full Orc including this fix: 78 credits (1100 -> 1022).
  **Final confirmation, 2026-09-13 (user-confirmed): "looks good."** One
  known, minor cosmetic artifact -- a slightly odd-looking arm in close-up
  -- noted but deliberately not chased further; the user's own call, since
  this whole Orc was explicitly a first test of the Meshy pipeline itself,
  not a production asset needing to be pixel-perfect. Worth revisiting only
  if it actually bothers someone at the table.

Custom-generated models via Meshy: real, working, and now proven end to
end for one full monster -- a real pipeline (including its rough edges: a
failed API mode, a pose that didn't match the prompt, a topology mismatch
between two parallel steps) documented here for the next one, not just a
success story. Phase 8's KayKit and Meshy items are both complete and
live-verified.

- [x] **Higgsfield "3D Jutsu" catalog explored -- 2026-09-13, 3 test pieces
  imported and a real pipeline bug found and fixed.** Composio surfaced this
  as a candidate 3D asset toolkit; connected and explored directly rather
  than assumed useful from its name alone. Its catalog turned out to be
  environment/prop-focused, not creature models (searching "orc" returned
  irrelevant results; "dungeon" returned 85 real hits) -- a genuinely rich,
  cohesive modular dungeon set: full corridor pieces (straight/corner/
  T-junction/4-way/ramp/dead-end), walls, stairs, doors, and dense
  atmospheric set-dressing (torture rack, iron maiden, gibbet cage, bone
  throne, cursed crystal, magic portal, stone altar/well, treasure chest),
  noticeably richer than the Kenney kit currently used for Phase 4 maps.
  **Two real open questions resolved with actual research before using
  anything, not assumed either way**:
  1. **Cost**: Higgsfield's own credit system is priced per agent-chat
     message (by which LLM you pick inside their own chat UI, "Auto" free
     by default), not per catalog import -- confirmed via their own pricing
     writeups, and consistent with the API responses themselves never
     reporting any credit consumption the way Meshy's `consumed_credits`
     field always did. Calling the search/import tools directly (not
     through their chat agent) appears to cost nothing.
  2. **Licensing**: genuinely unresolved, and said so plainly rather than
     assumed permissive. Higgsfield's actual Terms of Use (read directly,
     not inferred from a blog post) has no section addressing the pre-made
     catalog specifically -- only user-uploaded/generated content is
     covered. Their blog post mentions the catalog mixes Higgsfield's own
     curated assets with actual Mixamo characters, so it isn't even one
     uniform source. Discussed directly with the user: for a private,
     non-commercial, never-distributed project, the practical risk is
     accepted as near zero (nearly all such restrictions target
     distribution/resale, not personal use) -- but this is a real, lower
     level of certainty than the CC0/QAL licenses this project actually
     read and quoted for Kenney/Quaternius/KayKit, and the moment this
     project is ever published/distributed even for free, that answer
     needs to come from Higgsfield directly, not be assumed to still hold.
  **A real, confirmed pipeline bug found and fixed while testing 3
  pieces** (wall torch, treasure chest, corridor-straight): every
  Higgsfield GLB export carries genuine per-vertex color data (confirmed
  directly -- the treasure chest alone has 349 distinct wood-brown tones,
  not flat white), but Godot's glTF importer leaves the resulting
  material's `vertex_color_use_as_albedo` false, so every piece renders
  flat white regardless of its real color, until fixed. Fixed with a
  reusable tool (`godot/tools/fix_higgsfield_vertex_colors.gd`) that
  assigns each mesh a corrected `material_override` and re-saves the
  result -- likely a pipeline-wide issue for any future Higgsfield import,
  not specific to these 3 pieces, so this tool is meant to be re-run for
  the next one too. Also confirmed the corridor piece is a clean 4x4m
  footprint -- exactly 2x2 of this project's own 2m grid cells -- a good
  sign the kit was built on a real, consistent module size, not arbitrary
  dimensions. **Not yet verified live** -- the fix is confirmed correct at
  the data level (`vertex_color_use_as_albedo` reads back `true` after the
  fix), but nobody has actually looked at the corrected pieces rendered in
  the real editor yet. Not wired into any map or `MODEL_CONFIG` entry --
  this was scoped as a "does this pipeline work at all" test, not yet a
  decision to actually build Phase 4 content from this kit.

Below is the untouched research from 2026-09-11 for the bigger, still-open
questions this phase hasn't tackled yet (a unified retargeting pipeline,
paid packs, AI generation):

**Mixamo (Adobe, free) -- worth investigating before anything else, possibly
even before this phase formally starts.** Free rigged characters, a huge
animation library, and critically an **auto-rigger that accepts an uploaded
custom humanoid mesh** and fits it to Mixamo's own standard skeleton, after
which any of its animations retarget onto it automatically. This is
potentially bigger than "another asset source" -- it could **unify** the
bone-mapping problem this project has been solving by hand per pack family
(Quaternius's skeleton vs. KayKit's separate one): route any new humanoid
model through Mixamo's rigger once, and it's on one standard skeleton with a
massive animation library, instead of hand-verifying bone-name matches and
maintaining a second per-family animation source each time a new pack shows
up. License: free, no royalties, commercial and non-commercial use both
fine, no attribution required -- same "don't resell/redistribute the raw
files standalone" restriction every other pack here already follows. Worth a
real evaluation pass on its own before assuming the current per-family
bone-copy approach is the long-term answer.

**Synty Studios "POLYGON" series -- the actual paid/professional path**, and
the most direct answer to this whole project's original "professional game
graphics" question. A large, consistent, widely-recognized stylized
low-poly art ecosystem (many shipped indie games use it) with dedicated
fantasy/dungeon packs (Dungeon Pack, Dungeon Realms, Fantasy Kingdom, Fantasy
Rivals). Pricing: ~$20-250 per individual pack, or a $30/month subscription
for their entire 150+ pack library. Godot support exists, but native glTF
source files were still "coming soon" from Synty as of this research --
confirm current format support directly before buying anything, the same
"verify before relying on it" discipline every asset decision here has used.

**AI generation, beyond Meshy specifically** (see the earlier Meshy
discussion in this project's own conversation history for the base case):
Meshy and **Tripo AI** are the two leading hosted options for game-ready
generation with built-in auto-rigging; Tripo is faster (~8s/model) and
explicitly recommended for game-dev use in third-party comparisons, with a
free tier (~200-300 credits/month) -- but that free tier is **non-commercial
only**, a real difference from Meshy's free tier (CC BY 4.0, commercial use
allowed with attribution) worth checking before testing anything meant to
ship. Rodin AI produces the highest raw mesh detail of the three but has no
built-in auto-rigging (would still need Mixamo or manual rigging
afterward). No hands-on testing of any of these has happened yet -- this is
a survey of what's out there, not a recommendation to commit to one.

**More free monster variety exists beyond KayKit's Skeletons**, scattered
across itch.io and similar sites (individual creator packs, not one curated
source the way Kenney/Quaternius/KayKit are) -- lower confidence, would need
per-pack verification (license, rig, quality) the same way every pack
catalogued in `godot/assets/README.md` already was. Worth a targeted search
only once a specific missing monster (not covered by KayKit or a future
Mixamo/AI-generated model) actually blocks something real.

## Feature Parity Audit (2D Campaign-OS -> 3D), 2026-09-13

User request: "lets do a complete review of Campaign-OS and 3D to see if we
have missed any features and effects." Method: `engine/encounter.js`,
`engine/campaign.js`, and `engine/dmBridge.js` are confirmed byte-identical
between the two projects (same file sizes, empty `diff`), so every core 5e
mechanic is already available server-side -- this audit is specifically
about what the 3D client's UI (and its DM Assistant action vocabulary,
which routes through the exact same `DMBridge.applyActions` `POST /action`
calls from `Main.gd` do) actually exposes, cross-referenced function-by-
function against `ui/app.js` (~4000 lines) and its sibling modules.

**Real gaps found, roughly in the order worth tackling:**
- [x] **No way to set or roll initiative order at all -- 2026-09-13,
  fixed.** `dmBridge.js`'s shared action vocabulary had no
  `set_initiative`/`roll_initiative` case; the 2D app set it via a plain
  `<input name="initiative">` form field on the token sheet
  (`updateToken(state, id, { initiative })`, already engine-supported,
  clamped 0-99) that was never carried over as an action type when the 3D
  client's HTTP action API was built, and `nextTurn()` already sorts by
  initiative (confirmed by reading it) so this was a real, complete
  blocker on using rolled initiative order at all, not just a UI nicety.
  Added a new `rollInitiative(state, tokenId)` to `encounter.js` (1d20 +
  the token's real DEX modifier, RAW, no advantage/disadvantage support --
  not a RAW thing for initiative outside a specific feat this engine
  doesn't model) for the "roll it" case, and reused the existing
  `updateToken` for the "a player reports their own physical roll, or the
  DM corrects/tie-breaks a value" flat-assignment case -- two new
  `dmBridge.js` cases (`roll_initiative`, `set_initiative`) cover both.
  Applied to both Campaign-OS and Campaign-OS-3D (separate repos) to keep
  `engine/encounter.js`/`engine/dmBridge.js` byte-identical, confirmed
  with `diff`; `dm-bridge/watch.js`'s prompt updated in both too, so the
  Claude DM Assistant can roll initiative for every combatant at the
  start of a fight in one response. 4 new unit tests in Campaign-OS's own
  `tests/encounter.test.js` (370/370 passing there), 2 new integration
  tests in Campaign-OS-3D's `tests/server.test.js` confirming the actions
  reach the engine and persist onto the token through the real
  `POST /action` path (24/24 passing).
  On the 3D client: a new collapsible "Initiative" section (matching the
  existing Saving Throws/Checks/Conditions/etc. accordion pattern) with a
  "Roll Initiative (1d20 + DEX)" button and a manual "Set to <N>" row,
  placed first in the list since it's the thing a DM reaches for before
  anything else once a fight starts.
- [x] **No Advantage/Disadvantage toggle anywhere -- 2026-09-13, fixed.**
  Turned out bigger than expected: `attack()`/`castSpell()` already
  accepted `options.advantage`/`options.disadvantage` server-side, but
  `rollSavingThrow()`/`rollAbilityCheck()` didn't accept them AT ALL --
  only ever auto-applying disadvantage from specific conditions
  (exhaustion, Restrained, Poisoned). A DM declaring "advantage from
  Bless" on a save had no way to express that, in either the 3D UI or the
  Claude DM Assistant (its shared action vocabulary had no such field
  either). Fixed at the engine level first (`rollSavingThrow`/
  `rollAbilityCheck` now take an `options` param, combined with automatic
  condition-based disadvantage using `attack()`'s own established
  convention: explicit + automatic on the same side both just count as
  one, explicit advantage + disadvantage together cancel to a normal
  roll) -- applied to **both** Campaign-OS and Campaign-OS-3D (separate
  git repos) to keep `engine/encounter.js`/`engine/dmBridge.js` byte-
  identical, confirmed with `diff`. 4 new unit tests in Campaign-OS's own
  `tests/encounter.test.js` (366/366 passing there), 2 new integration
  tests in Campaign-OS-3D's `tests/server.test.js` confirming the field
  actually reaches the engine through the real `POST /action` path
  (22/22 passing). `dm-bridge/watch.js`'s system prompt updated in both
  repos so the Claude DM Assistant knows about the new fields too.
  On the 3D client itself: added one shared "Roll mode" dropdown
  (Normal/Advantage/Disadvantage) near the top of the selected-token
  panel in `Main.tscn`/`Main.gd`, applying to whichever roll comes next --
  attack (right-click), saving throw, ability check, or a spell's attack
  roll -- rather than duplicating the control in every section, matching
  how a real table treats it as one standing declaration rather than a
  per-button setting. Deliberately NOT wired into `cast_area_spell`,
  which resolves as one save per target -- no single "advantage" applies
  to "everyone in the blast," and the engine doesn't expose per-target
  advantage there anyway.
- **No dedicated UI for `apply_damage` (direct damage without a full attack
  roll), `drop_concentration`, `spend_hit_die`, or `remove_token`** -- all
  four are real cases in the shared `DMBridge.applyActions` vocabulary
  (so already reachable by typing a command into the DM Assistant panel),
  but none has a quick direct button the way `heal`/`long_rest`/
  `use_resource` etc. do -- every use costs a real Claude API round-trip
  instead of an instant click.
- **No AoE template tool** -- `cast_area_spell` exists and works, but
  requires manually checking each target's checkbox one at a time; the 2D
  app lets the DM drag out a cone/circle/line template directly on the map
  and auto-detects which tokens it covers (`templateCoveredTokenNames()`,
  built on real point-in-shape geometry already living in `encounter.js`
  and therefore already available to the 3D server too -- just never
  wired into a 3D-side drawing tool).
- **No ruler/measuring tool** (2D app: click-drag distance measurement
  overlay).
- **No interactive wall editor** -- walls only come from hardcoded
  `seedState()` calls (this project's own map-building tools) or DM
  Assistant `add_wall`/`remove_wall_near` text commands; no click-drag
  wall drawing/erasing the way the 2D app's `renderWallsOverlay` supports.
- **No Encounter Difficulty calculator** -- `evaluateEncounterDifficulty()`
  (XP budget vs. party level, easy/medium/hard/deadly thresholds) is
  already a shared, pure engine function; the 2D app has a whole panel for
  it (`renderEncounterDifficulty`), the 3D client calls it nowhere.
- **No freeform dice roller** (2D app: type "2d6+3", get a rolled result,
  via the shared `rollFreeform()` -- a real, commonly-needed DM utility
  for ad-hoc rolls not tied to any token/action).
- **No Token Library / Map Library / folder-based asset browsing** (2D:
  `tokenLibrary.js`, `mapLibrary.js`, `folderAssets.js`, plus
  `renderMapFolderResults`/`renderTokenFolderResults`/
  `renderMusicFolderResults`) -- every 3D map and creature is hand-built/
  hardcoded via this project's own headless tools rather than something a
  DM can browse a folder and drop into a live session.
- **No Character Creator wizard** and **no End Session / session
  transcript reporting** -- both are real `dm-bridge/watch.js` features
  (confirmed already, Phase 7's own notes: "requires `DND_REPO_PATH` env
  var only for End Session/Create Character features (not used yet in 3D
  client)") -- `watch.js` itself is copied byte-for-byte and already
  supports both; the 3D client's own UI just never added a way to trigger
  either.
- **No campaign-level save/load** -- the 2D app has a whole `renderCampaign`/
  `renderCampaignDetail` system for multiple saved campaigns/characters
  across sessions; the 3D client only ever has the one live
  `engine-server/state/encounter.json`.
- **No music/ambience system** -- Campaign-OS's Phase 10 feature
  (`renderMusicFolderResults`, `crossfadeAmbience`, `renderAmbienceControls`)
  has no 3D equivalent at all -- this was already tracked below before
  this audit; folding it in here rather than keeping a separate line.

**Checked and confirmed NOT a gap** (worth recording so this doesn't get
re-investigated later): the HP bar already has a real green/yellow/red
"bloodied" gradient (`Token.gd`'s `_update_hp_bar()`, thresholds at 50%/
25%) -- arguably a better indicator than the 2D app's plain "DEAD"/"DYING"/
"STABLE" text badges. And the 3D client's skeletal idle/walk/hit/death/
dying animation system (Phase 3/8) is actually MORE sophisticated than the
2D app's own combat feedback, which is just text plus one CSS dice-tumble
keyframe animation -- 3D isn't behind here, it's ahead.

**Architecturally unnecessary for 3D, not real gaps**: the 2D app's grid
handles / drag-to-align-grid-to-a-background-image system and its map
background image upload/resize pipeline both only make sense for photo-
background 2D maps -- hand-built 3D scenes (Prototype Chamber, Entrance
Hall) have no equivalent need.

## Also tracked, not yet phased

- **Real multiplayer** (a server/sync service for players on their own
  devices, not just a second monitor) -- explicitly out of scope for now,
  the same "revisit only if actually needed" call the 2D app itself already
  made for this exact question.
- **Performance** (one hidden AnimationPlayer + Skeleton3D per token, full
  board rebuild on any map-size change) -- fine at current token/map counts;
  no need to optimize preemptively.
