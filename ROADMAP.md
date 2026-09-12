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
- [ ] Per-map lighting/mood (a hand-built room may want its own atmosphere --
  torches, color grading -- rather than the single fixed sky+sun every map
  currently shares) -- not started; the single existing map still uses the
  one shared sky+sun every map has had since Phase 0.

## Phase 5 -- Line of sight / fog of war in 3D

Unlocked by Phase 4, not before -- the 2D app's LOS math works against 2D
wall segments; real 3D wall geometry (from hand-authored maps) is what makes
a 3D equivalent meaningful. Not designed in detail yet: the two live options
(raycast against the hand-placed wall meshes directly, vs. maintaining an
abstract wall-segment list per map closer to the 2D model) each have real
tradeoffs worth a dedicated discussion once Phase 4 exists to build on.

## Phase 6 -- Player-facing view

A 3D equivalent of the 2D app's Player Window (same-machine, read-only,
second monitor/TV) -- matters once the client is actually good enough to run
at a table. Not scoped in detail yet.

## Phase 7 -- Claude DM bridge integration (later, per decision #3 above)

`engine-server`'s `POST /action` already accepts the exact same action
vocabulary (`attack`, `cast_spell`, `move_token`, ...) the 2D app's
`dm-bridge/watch.js` produces -- wiring narration/tool-calling into this
client later should mean reusing that contract, not redesigning it. Not
scoped further until Phases 3-6 exist for it to sit on top of.

## Phase 8 -- Art investment (later, per decision #4 above)

Free Quaternius/Kenney/KayKit assets proved the pipeline in Phase 2 and
filled real gaps (see the Creatures/ catalog in `godot/assets/README.md`).
Once the feature set from Phases 3-6 feels worth dressing up, this is where
to evaluate paid asset packs or bespoke/commissioned art to replace them.
Deliberately not scoped further until that point -- but a research pass on
2026-09-11 already surveyed the real options, recorded here so it doesn't
need re-doing when this phase actually starts:

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

## Also tracked, not yet phased

- **Audio/ambience** (matching the 2D app's Music Folder/Ambience feature) --
  a nice parity feature, no urgency.
- **Real multiplayer** (a server/sync service for players on their own
  devices, not just a second monitor) -- explicitly out of scope for now,
  the same "revisit only if actually needed" call the 2D app itself already
  made for this exact question.
- **Performance** (one hidden AnimationPlayer + Skeleton3D per token, full
  board rebuild on any map-size change) -- fine at current token/map counts;
  no need to optimize preemptively.
