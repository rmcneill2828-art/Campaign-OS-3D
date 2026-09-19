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

**Update, 2026-09-16: evaluated, not the path taken.** Automating Mixamo
for a whole creature library turned out to be real account risk, not just
"another integration" -- Adobe's own terms explicitly prohibit bulk/
scripted automation. See "Meshy-rig-to-free-animation bone name mapping"
further down this file for what got built instead: rig via Meshy once per
model, then animate free forever via a bone-name translation table onto
Quaternius's existing free animation library, no Mixamo involved at all.

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
  **Follow-up, found live -- 2026-09-13, fixed.** User clicked Roll
  Initiative and saw no confirmation at all. Checked the live server
  directly (`GET /state`) rather than guessing: the roll HAD actually
  succeeded (the token's initiative was a real, plausible DEX+d20 result),
  but the message wasn't anywhere in the visible log -- it turned out
  `Main.gd`'s `_status_label` only ever shows `state.log[0]`, the single
  most recent entry, trivially pushed out by the very next action or even
  the next 1-second poll tick if anything else happened first. This
  wasn't initiative-specific at all -- every action's confirmation was
  this easy to miss, `PlayerView.gd` just never had the problem because
  it already has a real scrolling combat log. Added the same thing to
  `Main.gd`'s own view (`_update_combat_log()`, ported directly from
  `PlayerView.gd`'s own function) rather than patching initiative alone
  -- a new `CombatLogPanel` on the left side below the hint label,
  listing the full `state.log` (newest first, matching its own storage
  order), so a DM can actually see what just happened and scroll back
  through recent history instead of only ever seeing the latest line.
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
- [x] **No dedicated UI for `apply_damage`/`drop_concentration`/
  `spend_hit_die`/`remove_token` -- 2026-09-13, fixed.** Three of the four
  were already real cases in the shared `DMBridge.applyActions` vocabulary
  (reachable by typing a command into the DM Assistant, just not a quick
  button); `remove_token` turned out to not exist as a DM-bridge action at
  all -- the 2D app has its own "Remove Token" button, but it calls
  `removeToken()` directly in-browser rather than going through
  `dmBridge.js`, so that engine glue case genuinely didn't exist yet. Added
  it (mirroring the others' `findTokenByName` + not-found-message
  convention), applied to both Campaign-OS and Campaign-OS-3D to keep
  `engine/dmBridge.js` byte-identical (confirmed with `diff`), and updated
  `dm-bridge/watch.js`'s prompt in both repos with guidance on when to use
  it (a token that genuinely shouldn't exist anymore -- a summon expiring,
  cleaning up a mistaken spawn -- not as a stand-in for "it died," which a
  dead-but-still-present token already models better). 2 new unit tests in
  Campaign-OS's own `tests/dmBridge.test.js` (372/372 passing there), 1 new
  integration test in Campaign-OS-3D's `tests/server.test.js` confirming
  the real `POST /action` path actually deletes the token (25/25 passing).
  On the 3D client: four new controls added to the existing "Other Actions"
  section -- a Damage row (amount + type + Apply), a Drop Concentration
  button, a Hit Die row (free-text type, since a token's own pool varies by
  class/level -- same reasoning the existing Recharge Abilities row's
  free-text name field already uses), and a Remove Token button, all
  wired to the same `_require_selected_token()`/`_send_action()` pattern
  every other action here already uses. No confirmation dialog on Remove
  Token -- matches this client's existing no-confirmation convention for
  every other action (Full Heal, dropping to 0 HP, etc.).
- ~~**No AoE template tool**~~ -- **fixed 2026-09-19**, see item 7 of
  "Seven requested features" below for the full account.
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
- ~~**No Character Creator wizard**~~ -- **fixed 2026-09-19**, see item 1 of
  "Seven requested features" below for the full account. **No End Session /
  session transcript reporting** is still open -- also a real
  `dm-bridge/watch.js` feature (confirmed, Phase 7's own notes) the 3D
  client's UI just never added a way to trigger.
- **No campaign-level save/load** -- the 2D app has a whole `renderCampaign`/
  `renderCampaignDetail` system for multiple saved campaigns/characters
  across sessions; the 3D client only ever has the one live
  `engine-server/state/encounter.json`. The narrower "import an existing
  campaign's characters" half of this is tracked as item 4 of "Seven
  requested features" below.
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

## CI -- 2026-09-16, built, not yet verified against a real run

`.github/workflows/test.yml`: a `node-tests` job (`npm test` in
`engine-server/`, matching Campaign-OS's own `test.yml` convention) plus a
`godot-smoke-tests` job running against `barichello/godot-ci:4.7.2` (a
Docker image pinning the exact same headless `godot` binary version this
project is developed/verified against) -- primes the project's global
class cache first (`godot --headless --editor --path godot --quit`, the
same fix `godot/tools/README.md`'s own "fifth gotcha" documents, without
which `smoke_test_entrance_hall.gd`'s `MapScenes` reference would fail to
resolve), then runs the three existing `godot/tools/smoke_test_*.gd`
scripts unchanged.
**Not actually verified end to end**: this repo has no `git remote`
configured yet, so nothing has triggered a real GitHub Actions run against
this workflow -- it's built directly from the smoke tests' own documented
invocation convention and a Docker Hub tag check (`barichello/godot-ci`
publishes a matching `4.7.2` tag), not confirmed by watching it pass.
Verify on the first real push to a GitHub remote, and treat a first-run
failure as the workflow needing a fix, not the smoke tests themselves.
Real interaction coverage (token selection, movement, player-view fog,
HUD action wiring actually doing the right thing when triggered, not just
"the scene loads") is still open -- the existing smoke tests only catch a
load/parse/`_ready()` failure, not a wiring regression in already-loading
code.

## Meshy-rig-to-free-animation bone name mapping -- 2026-09-16, built, needs live verification

Resolves this file's own earlier "Mixamo (Adobe, free) -- worth
investigating" research note above (2026-09-11), but lands somewhere
different than that note assumed: the user wants to build a large library
of Monster Manual creatures from Meshy's free static-model downloads, and
at that scale Meshy's own per-model rig+animate cost adds up fast (the Orc
alone cost 78 credits, most of it the 6 individual animation clips, not
the 5-credit rig step) -- so the goal became "rig via Meshy once per
model, animate for free forever after" rather than routing every model
through Mixamo. Automating Mixamo itself for bulk use was ruled out
separately: Adobe's own Generative AI User Guidelines explicitly prohibit
"unauthorized automated or scripting processes (such as bulk or automated
uploading of content through a script)," which is exactly what building a
whole creature library through it would be -- real account risk, not
hypothetical.

Checked (not assumed) whether a Meshy-rigged model's skeleton could
directly drive Quaternius's or KayKit's existing free animation libraries
the same way `Token.gd`'s `_setup_animation()` already does between
same-family models -- extracted real bone-joint names straight out of the
already-generated `orc_warrior.glb` (Meshy's rig) and
`mannequin_animations.glb` (Quaternius UAL1) via a small standalone
Node.js glTF parser (no Blender/Godot needed to read a skin's joint
names). Result: **zero bone names in common** -- Meshy's rig uses
Mixamo-style names (`Hips`, `LeftUpLeg`, `LeftForeArm`), Quaternius uses
Unreal-style (`pelvis`, `thigh_l`, `lowerarm_l`), KayKit uses
Blender-style (`hips`, `upperleg.l`, `lowerarm.l`) -- so the existing
exact-name-match bone copy would silently animate nothing at all for a
Meshy-rigged model paired with either free pack.

But every one of Meshy's 24 rig bones has a clean, unambiguous Quaternius
UAL1 equivalent by function (confirmed programmatically against both
real bone lists, not eyeballed: 22/24 map correctly, no typo'd source
keys, no two Meshy bones mapping to the same Quaternius target) -- only
`head_end`/`headfront` (small Meshy-specific attachment bones, not part
of the walk/idle/attack silhouette) have no Quaternius equivalent and stay
unmapped. Added `Token.MESHY_TO_QUATERNIUS_UAL1_BONE_MAP` and a new
optional `bone_name_map` field on any `MODEL_CONFIG` entry:
`_setup_animation()`'s bone-matching loop now translates the character's
bone name through this map (when present) before searching the animation
source's skeleton, falling through to the bone name unchanged when a
family has no map at all -- every existing entry (hero/monster/skeleton/
orc) is untouched, byte-for-byte the same exact-match behavior as before.
No new `MODEL_CONFIG` entry was wired in yet -- this is the reusable
mechanism, ready for whichever Monster Manual creature the user rigs via
Meshy next (5-ish credits, one-time, per model) instead of paying for
Meshy's own animate step or touching Mixamo at all.

New tool: `godot/tools/inspect_bone_name_map.gd`, matching
`inspect_kaykit_skeleton.gd`/`inspect_meshy_orc.gd`'s existing "verify a
rig actually matches, don't assume" convention -- checks Token's own map
constants directly (not a copy), so it can't drift from what `Token.gd`
actually ships. **Needs a real Godot session to run** (this environment
has none) before trusting the map/mechanism live -- the underlying
bone-name DATA was verified directly against the real files (not
guessed), but the new GDScript logic itself (the `bone_name_map` lookup
added to `_setup_animation()`, and the tool that checks it) has not been
executed in a real Godot process.

**Update, 2026-09-16 (same day): a second, genuinely different Meshy rig
convention confirmed already** -- the very next model the user rigged
(a downloaded free static "Warrior" model, through Meshy's WEBSITE
Rigging tool rather than the API) came back with completely different
bone names: real `mixamorig:`-prefixed names (`mixamorig:Hips`,
`mixamorig:Spine1`/`Spine2`, capitalized `Neck`) matching genuine Adobe
Mixamo output exactly, not the API path's prefix-stripped
`Spine01`/`Spine02`/lowercase-`neck` variant. Root cause, from the actual
evidence available rather than guessed: the website's Rigging tool shows
an explicit **"Skeleton template: Mixamo"** dropdown that the
Composio-connected `MESHY_CREATE_RIGGING_TASK` API doesn't expose at all
-- not, as first suspected, a difference between a from-scratch-generated
model (the orc) and an already-existing uploaded one (the warrior); the
API's own schema simply has no template-choice parameter, so it always
falls back to one fixed internal convention regardless of what's being
rigged.

Renamed the original constant to `Token.MESHY_API_RIG_TO_QUATERNIUS_UAL1_BONE_MAP`
(no longer ambiguous now that a second convention exists) and added
`Token.MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP` alongside it --
built and verified the same programmatic way as the first (real bone
names extracted from the actual downloaded `.glb`, not guessed): 26 of
its 28 bones map cleanly to Quaternius UAL1, zero bad mappings, zero
duplicate targets, zero typo'd keys; only `mixamorig:HeadTop_End` and a
stray unprefixed `headfront` bone (present on both Meshy rigs, still
unexplained) are left unmapped. `inspect_bone_name_map.gd` now points at
`MESHY_API_RIG_TO_QUATERNIUS_UAL1_BONE_MAP` by default and documents both.

Since the website (not the API) is the path actually being used for every
future creature in this library, the Mixamo-template convention is
expected to be the common case going forward -- but per this same
update's own lesson, that expectation still needs re-checking against the
next model via `inspect_bone_name_map.gd`, not assumed to hold just
because it held twice. The warrior model itself hasn't been copied into
the Godot project or wired into a `MODEL_CONFIG` entry yet -- still
sitting at the user's own downloaded-models folder, pending a decision on
which hero/monster slot it should fill.

**Update, 2026-09-16 (same day): wired in as "Barbarian," the first
per-name HERO entry.** Copied the rigged model into
`godot/assets/creatures/hero/barbarian.glb` (same flattened-copy
convention every other model here follows) and added `"hero:barbarian"`
to `MODEL_CONFIG`, using `MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP`
and reusing the plain `"hero"` entry's own Quaternius UAL1
animation_source/clip names verbatim (same file, same Idle/Walk/Death01/
Crouch_Idle/Hit_Chest/Hit_Head clips -- only the model and its
bone_name_map differ). Re-confirmed the copied file's bone names still
match the map post-copy (26/28, same as the original download) before
wiring it in.

`_rebuild_model()`'s per-name lookup was monster-only until now (every
hero rendered as the same `superhero_male` regardless of name, a known
gap since Phase 2) -- extended the exact same `"<type>:<stat-block-key>"`
two-tier pattern to heroes too, now that a real per-name hero model
existed to justify it, rather than building the hero half speculatively
ahead of need. A hero token needs to actually be NAMED "Barbarian"
(case-insensitive, optional trailing spawn number, same
`_stat_block_key()` rule monsters already use) to pick this model up --
Darkhawk/Wren and any other hero name still fall through to the generic
`superhero_male` entry unaffected.

`label_height` reuses the generic `"hero"` entry's own `2.0` as a
starting default -- this specific model's real proportions haven't been
measured live, same "needs live tuning" caveat as everything else in this
update. **Still entirely unverified in a real Godot session** (this
environment has none) -- the bone-name data and the file copy are
confirmed correct; the actual visual result (grounding, scale, animation
playback, label position) has not been seen.

## `add_token` DM-bridge action -- 2026-09-16

Found trying to actually use the new Barbarian hero above: **there was no
way to create a hero token in this client at all.** Confirmed by checking
`dmBridge.js`'s full action list directly (28 cases, no `add_token`/
`add_hero`) rather than assumed -- `spawn_monster` only covers the fixed
SRD monster list, and no "Add Hero" button exists anywhere in `Main.gd`.
The only two heroes that have ever existed (Darkhawk, Wren) are hardcoded
into `engine-server/server.js`'s own `seedState()`.

This is a shared-engine gap, not 3D-specific, so the real fix lives in
`engine/dmBridge.js`/`dm-bridge/watch.js` -- see Campaign-OS's own
`ROADMAP.md` for the full `add_token` entry (generic `tokenType` "hero"
or "monster", `abilityScores` passed through so a new hero doesn't
silently show a flat +0 on every roll, matching the same fix Phase 3
already made once for the seeded heroes). Synced into this project the
usual way (`engine-server/scripts/sync-engine.sh` for `dmBridge.js`, a
plain copy for `watch.js` -- confirmed byte-identical via direct `diff`
against Campaign-OS afterward, same discipline as every other shared-file
change). One new integration test in `engine-server/tests/server.test.js`
confirms the real `POST /action` path actually creates a usable, real
token with real ability scores (49/49 tests passing).

**What this unlocks right now, with zero further Godot code**: typing a
command into the existing DM Assistant panel (e.g. "add a hero named
Barbarian") already works end-to-end through `POST /dm-command` -- Claude
resolves it to a real `add_token` action, same as any other DM Assistant
command. **Not yet built**: a dedicated "Add Hero" button/form in
`Main.gd`'s own UI, which wouldn't depend on Claude correctly
interpreting a free-text request each time. Worth adding if the DM
Assistant path proves unreliable or too slow for something this
frequent -- not done yet since the underlying capability (the actual
blocker) is what mattered most to fix first.

## First real live verification: Barbarian appeared, but frozen in bind pose -- 2026-09-16, found and fixed

The user actually created a Barbarian hero via the DM Assistant and saw
it live in Godot for the first time this phase -- correctly grounded,
correctly scaled, standing right next to Darkhawk, but frozen in a T-pose
instead of playing Idle. First real live confirmation that the model/
rig/token-creation pipeline built this session actually works end to
end, and the first real bug only a live Godot run could have caught.

Root cause, found with `godot/tools/inspect_bone_name_map.gd` (pointed at
`barbarian.glb` + `MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP`) run
against the user's real Godot 4.7.2 install, not guessed: **Godot's glTF
importer replaces ":" with "_" when it turns each joint into a Skeleton3D
bone.** The map's keys were written from the raw file's own real bone
names (`mixamorig:Hips`, confirmed by direct extraction earlier this
session) -- correct for the FILE, wrong for what Godot actually names the
bone at runtime (`mixamorig_Hips`). First run: 0/28 matched, every bone
stuck in bind pose. This is exactly the kind of thing this project's own
established discipline (`_ground_model()`'s AABB-measurement comment,
`GridManager.gd`'s piece-placement comments) already warns about --
trusting a source file's own claimed data over what Godot actually does
with it at runtime -- but this specific case (bone names, not mesh
bounds/transforms) hadn't come up before.

Fixed by correcting `MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP`'s
keys to the underscore form; re-ran the same tool and confirmed 26/28
matched, same coverage originally verified against the raw file, now
confirmed against Godot's real runtime bone names instead.
**Note this only affects the Mixamo-template map, not the orc's own API-
rig map** -- `MESHY_API_RIG_TO_QUATERNIUS_UAL1_BONE_MAP`'s bone names
never had colons in the first place (`Hips`, `LeftUpLeg`, etc.), so
nothing about the orc's own already-working animation was at risk.

**Update, same session: the bone-name fix alone wasn't enough.** Live
result after restarting the scene: correctly playing Idle now (bone
names DO match, 26/28, confirmed), but the whole model collapsed into a
crumpled heap on the floor instead of standing -- a different, deeper bug
the bone-name fix couldn't have caught. Root cause: `_process()` copied
every bone's position AND rotation AND scale from the source skeleton,
not just rotation. That's harmless between two skeletons with near-
identical proportions (every pairing before now: hero/monster's own
model <-> Quaternius, KayKit Skeleton <-> KayKit's own animation
library -- same rig family or closely matched proportions either way) --
but this is the FIRST genuinely cross-rig pairing this project has tried
(a Meshy-rigged model, different proportions entirely, driven by
Quaternius's UAL1 via `bone_name_map`), and copying the source's bone
*positions* onto a differently-proportioned target displaces every limb
to the wrong relative location. Fixed by only copying position/scale for
a bone with no parent (the root, carrying the animation's own overall
body movement/bob) -- every other bone now keeps its own rest-pose
position, driven only by rotation, the standard way skeletal retargeting
across different-proportioned rigs actually works.

**Update, same session: the position fix worked, but revealed a third,
narrower bug.** Live result: crumpled heap gone, body anatomically
correct -- but now lying fully prone on the floor, tipped over as one
rigid unit rather than standing. Root cause: still copying the ROOT
bone's rotation from source to target, and `_ground_model()`'s own doc
comment (right below `_process()` in this same file) already documented
the relevant fact -- this project's rigs carry a baked root-bone rotation
that varies per model (a Z-up/Y-up export-tool artifact), confirmed
independently once already for `_ground_model()`'s own bug, not
re-discovered here. Copying the source root's rotation onto a target
root with a different baked convention doesn't animate the body, it
tips the entire hierarchy over as one unit -- everything below the root
stayed internally consistent (child rotations are parent-relative, which
is exactly why the body wasn't ALSO crumpled this time), only the whole
thing's absolute orientation was wrong. Fixed by leaving the root bone's
own rotation alone entirely (whatever this specific model's own rest
pose already has, upright) while still copying every child bone's
relative rotation -- position copies only for the root, rotation copies
only for everyone else, a clean split rather than "copy everything for
the root."

**Update, same session: orientation fixed, but sunk into the floor up to
the waist.** Root cause: still copying the root bone's POSITION every
frame -- Quaternius's root sits at a different height within ITS OWN
skeleton than Meshy's root does in Meshy's differently-proportioned one,
so the ongoing per-frame copy kept dragging the body down below where
`_ground_model()`'s one-time bind-pose grounding had placed it (that
function has no way to know a later system will keep moving the root
after it runs once at setup). Fixed by leaving the root bone completely
untouched now -- neither position nor rotation copied for it at all,
only every other bone's rotation. Trades away whatever root-motion
bob/sway Quaternius's Idle clip might carry for actually standing in the
right place; a rest-pose-relative delta (source root's current pose
minus its own rest pose, applied onto the target's own rest pose rather
than its raw absolute transform) would be the more correct fix if root
motion is ever worth the complexity, not attempted now.

Fourth fix in the same live-debugging thread (bone names -> position ->
root rotation -> root position), each only found by actually seeing the
previous fix's real result in Godot, not by reasoning alone -- explicitly
noted in this fix's own code comment as close to the practical limit for
guessing at something this visual without direct Godot access.

**Update, same session: standing/grounded confirmed correct, but real
diagnosis this time instead of another screenshot-guess** -- the user
checked directly in the Godot editor, orbiting/zooming the live camera
per this project's own controls, rather than another round of "here's a
screenshot, guess again." Both feet visibly twisted, and the face too --
not one isolated bone, every joint.

This pointed at something more fundamental than any of the four fixes
above: `_process()` was still copying each non-root bone's rotation as a
raw ABSOLUTE value from source to target, which only produces a correct
pose if both skeletons share the exact same REST orientation per bone.
True within one rig family (why hero/monster<->Quaternius and
skeleton<->KayKit never had this problem) but never actually guaranteed
across genuinely different rigs -- and any per-bone rest-orientation
mismatch compounds down a joint chain, worst at its far end (toes,
the neck/face), exactly where this showed up, not at the torso.

Fixed with the real retargeting technique this needed all along: extract
how far the SOURCE bone has rotated away from ITS OWN rest pose
(`source_rest.inverse() * source_pose`), then apply that same delta on
top of the TARGET's own rest pose instead of the source's raw absolute
rotation. A mismatched baseline orientation between the two skeletons
now cancels out instead of compounding into a visible twist. Root bone
handling is untouched (still skipped entirely, per the fix above) --
this only changes how every OTHER bone's rotation is computed.

**Update, same session: rest-pose-relative retargeting fixed feet and
face -- confirmed live, with a real diagnosis, not another guess.** The
user checked directly in Godot again: legs/feet/spine/face all correct
now. One remaining, precisely-localized issue -- both shoulders pulling
the whole arm backward, in both Idle and Walk (so not animation-
specific). The arm chain itself (upper arm through hand) was explicitly
confirmed already correct on its own.

Fixed the same way the root bone issue was: removed
`mixamorig_LeftShoulder`/`mixamorig_RightShoulder` from
`MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP` entirely, so
`_process()`'s bone-map loop never touches them -- they stay at their own
natural rest angle permanently, while the arm chain below (already
confirmed working) continues to be driven normally. Best available
explanation for why the shoulder specifically needed this and the rest
of the arm didn't: Quaternius's `clavicle_l`/`clavicle_r` most likely
isn't the same *functional* joint as Meshy's `LeftShoulder`/
`RightShoulder` -- a clavicle bone in many rigs barely rotates at all
(a near-static shoulder-width spacer), while Meshy's own rig may expect
its shoulder bone to actually move, so even a mathematically correct
rest-relative delta computed from Quaternius's own near-static clavicle
motion doesn't mean much applied to a bone that's supposed to carry real
rotation. Bone count for this map: 24/28 now (down from 26 -- 2 removed
deliberately, not a new mismatch found).

**Update, same session: shoulder exclusion had ZERO effect -- diagnosis
was wrong, not just incomplete.** The user put the Barbarian directly
next to Darkhawk for a real side-by-side comparison against a known-
working reference: Darkhawk's arms sat in a natural raised guard stance;
the Barbarian's were still swept backward, identically to before the
shoulder fix, in both Idle and Walk. Real diminishing returns on this
approach after 5 live-tested rounds (bone names, position, root rotation,
root position, shoulder exclusion) -- rather than guess a 6th time,
switched strategy entirely instead of continuing to patch the retargeting
math.

**Switched to real Mixamo animations instead of retargeting onto
Quaternius.** Since Meshy's rig already uses genuine `mixamorig:`-
prefixed bone names (confirmed live earlier this same session, via the
colon-to-underscore Godot import finding above), real Mixamo animations
should share that exact convention and need NO retargeting math at all --
the same plain exact-name bone matching the `"hero"` entry's own
Quaternius pairing already relies on. User manually downloaded 5 clips
from mixamo.com "without skin" (Breathing Idle, Standard Walk, Standing
Death Forward 01, Reaction, Hit Reaction) -- a handful of files, not the
bulk/automated pull this file's own earlier Mixamo research note already
ruled out. Confirmed directly (not assumed) by scanning the raw FBX bytes
for readable strings: real bone names present and identical in style to
what Meshy's own rig already produced (`mixamorig:Hips`,
`mixamorig:LeftShoulder`, etc., the full 65-bone standard rig, a superset
of Meshy's 28), AND a real, concrete gotcha found the same way -- **every
one of the 5 files shares the exact same internal clip name,
`"mixamo.com"`**, a well-known Mixamo export quirk. Importing several
under that literal name into one shared library would have silently
overwritten each other.

Fixed by extending `Token.gd`'s clip-import helpers
(`_resolve_or_import()`/`_import_animation_clip()`) with a new optional
`"as"` field -- looks the clip up in its source file by one name
(`"clip"`) but stores it in the target library under a different one
(`"as"`), fully backward compatible (every existing `{clip, source}` entry
across the Orc/Skeleton families has no `"as"` field, so they fall back to
the old identical-name behavior unchanged). Rewired `"hero:barbarian"` to
use the 5 new files as its `animation_source`/clips, with `bone_name_map`
removed entirely. The Quaternius-retargeting map/mechanism itself is left
in place (not deleted) as real, tested infrastructure for a future
Meshy-rigged model where downloading matching Mixamo clips isn't
practical -- just no longer what the Barbarian uses.

No dedicated "dying" (kneeling/downed) clip existed among what was
downloaded -- left unset rather than forcing a short reaction clip to
loop awkwardly as an imperfect stand-in, same call the Orc's own entry
already made for its own missing kneel pose, just resolved as "nothing"
here instead of "an imperfect substitute."

**Update, same session: verified live -- bones matched (27/28), but the
Barbarian came back frozen in a T-pose again.** Extended
`inspect_bone_name_map.gd` to also print the animation source's real
`AnimationPlayer.get_animation_list()` rather than guess a second time,
and confirmed directly: the real, Godot-resolved clip name is
`"mixamo_com"`, not `"mixamo.com"`. The raw FBX bytes really do contain
the literal string `"mixamo.com"` (confirmed earlier this session by
scanning them directly) -- but that's metadata (a credit/description
field), not the actual AnimStack/Take name Godot's FBX importer surfaces
as a playable clip key. Godot's FBX importer sanitizes `"."` out of
animation names the same general way its glTF importer sanitizes `":"`
out of bone names -- a second instance of the exact same class of gotcha
found earlier this session for bone names, not a coincidence, and a
useful pattern to remember for the next FBX import this project does:
don't trust a raw file string as the Godot-resolved name for ANYTHING
(bones, clips, likely more) without checking live.

Fixed by correcting every `"mixamo.com"` reference in `"hero:barbarian"`
to `"mixamo_com"`.

**Update, same session: verified live -- the mechanism works completely.**
The Barbarian now stands correctly, animates cleanly, no twisting, no
crumpling, no backward-pulled arms -- confirmed by the user via a direct
side-by-side against Darkhawk. This closes out the whole retargeting saga
started by the earlier bone-name/position/rotation fixes: the actual,
final answer was abandoning cross-rig retargeting in favor of real
Mixamo animations, exactly as the strategy switch above intended.

One remaining issue was pure content choice, not technical: "Breathing
Idle" (the actual Mixamo clip originally downloaded for `idle`) turned
out to look like "a Zombie pose" once seen animating -- arms thrust
forward, clenched hands, not a relaxed standing stance. Swapped for a
different Mixamo clip (plain "Idle") -- a pure file replacement at the
same path (`mixamo_idle.fbx`), no code or config change needed at all,
confirming the underlying mechanism (clip-name resolution, bone
matching, animation playback) is robust to swapping which specific
Mixamo animation is used. `walk`/`death`/`hits` still use the original
4 downloaded clips (Standard Walk, Standing Death Forward 01, Reaction,
Hit Reaction) -- not yet individually confirmed live the way idle now
is, worth a look if any of them turn out to have the same
"technically-plays-but-looks-wrong" problem "Breathing Idle" did.

**Update, same session: the swap to plain "Idle" regressed -- "his whole
body is twisted," a real structural problem, not another pose-choice
issue.** Checked the new file's raw bytes directly (bone names, export
metadata) before guessing -- structurally identical to "Breathing Idle"
(same rig, same "MotionOnlyScene" motion-only export), so the difference
had to be in the actual animation curve data, not the file/rig itself.

Reconsidered the mechanism instead of the file: `_process()` had frozen
the root/hip bone ENTIRELY since the earlier Quaternius cross-rig work,
where that was the right call (the two rigs' rest conventions genuinely
conflicted). But the Barbarian isn't cross-rig anymore -- source and
target are both real Mixamo rigs now. A frozen hip with the spine still
receiving its FULL rotation delta only looks fine if the clip's own
weight-shift is subtle enough not to expose it (true of the minimal
"Breathing Idle," not true of a more expressive "Idle" whose natural
stance likely choreographs the hip and spine rotating together) -- the
spine's motion assumes a hip that moves with it.

Re-enabled root motion using the SAME rest-pose-relative delta technique
already proven for every other bone (both rotation and position), but
as an OPT-IN per family (`"animate_root": true`, new
`_animate_root` state, defaulting false) rather than a global change --
`_process()` is shared by every token, and hero/monster/skeleton/orc all
have a frozen root that's been working fine all session; changing that
globally to fix the Barbarian risked regressing four things that weren't
broken. Only `"hero:barbarian"` opts in.

**Not yet verified live** -- a real, reasoned fix based on reconsidering
which assumption stopped applying (cross-rig -> same-rig), not another
blind guess, but still unseen running.

## Abandoned the retargeting approach entirely -- routed through Mixamo's own Auto-Rigger instead, 2026-09-17

Live result after the root-motion fix above: still twisted, no better.
User called it directly: **"i think this is where we rethink the
plan."** Seven live-tested iterations deep into bridging Meshy's rig
onto free animation libraries (bone names, position, root rotation, root
position, shoulder exclusion, switching to real Mixamo animations, then
root motion again) without a clean result was a real signal the
technique itself -- runtime bone-transform copying between two
independently-authored skeletons, however careful the math -- has more
edge cases than worth chasing blindly, not that one more fix would land
it.

Offered three real options rather than another guess: (1) swap to
KayKit's own pre-rigged Barbarian hero model (proven zero-retargeting
pattern, different art style), (2) pay Meshy to animate this exact
model directly like the Orc (guaranteed correct, reintroduces the
per-model cost problem this whole detour was meant to avoid), (3) keep
iterating on the current approach. User picked a fourth path not on the
list: **download the plain unrigged Meshy model and let Mixamo's own
Auto-Rigger rig it directly**, rather than Meshy's own rigger. This
sidesteps the entire retargeting problem at its root -- if Mixamo builds
both the skeleton AND every animation applied to it, there's nothing
left to reconcile between two different systems' rest poses, the exact
class of problem every prior fix in this file was fighting.

**Real, non-obvious problem hit getting there**: Mixamo's auto-rigger
kept failing with "Sorry, unable to map your existing skeleton" on a
model confirmed (by scanning the raw FBX bytes directly, not assumed) to
have ZERO bone/skeleton data at all -- a well-known, misleading Mixamo
error message that fires for unrelated failures too (confirmed against
multiple community reports, including one titled literally "the
auto-rigger can't map my existing skeleton but my model has no
skeleton"). Actual cause, per those same reports: file size/complexity,
recommended under ~15-30MB. The export was 45MB with a full PBR material
setup (separate base color/metallic/normal/roughness maps). Tested as a
genuine process of elimination, one variable at a time: remeshing to 10K
faces alone changed nothing meaningful (textures dominate FBX file size
for a PBR character, not geometry -- an unintuitive but correct result,
not a fluke), while dropping to a plain base-color-only texture got the
export to 12MB and past the auto-rigger on the very next attempt.
Polygon count was never the actual lever; material complexity was.

Once rigged, every animation was previewed live against the actual
character in Mixamo's own web viewer before downloading -- catching
problems (like "Breathing Idle" looking wrong) before they ever reach
Godot, not after. Rewired `"hero:barbarian"` entirely: `barbarian.fbx`
(the "with skin" download -- mesh + skeleton + its own baked Idle clip)
is now both `path` and `animation_source`, with 5 more "without skin"
clips (`barbarian_walk/death/dying/hit1/hit2.fbx`) providing
walk/death/dying/2 hit reactions. No `bone_name_map` at all -- genuine
Mixamo-built rig on both sides, exact-name matching, same mechanism the
plain `"hero"` entry already uses against Quaternius. `animate_root:
true` kept, since there's no known reason root motion should be unsafe
between two Mixamo-built skeletons the way it was between Meshy's and
Quaternius's.

Both earlier attempts (Quaternius retargeting, then real-Mixamo-onto-
Meshy's-rig) are kept in this file's own history above, not deleted --
the actual lesson generalizes past this one character: when a custom
model needs both a rig AND animations, get BOTH from the same system
that's actually good at retargeting (Mixamo itself) rather than trying
to reconcile a rig from one pipeline with animations from another inside
this project's own runtime code, however carefully that code is written.

**Update, 2026-09-17: verified live -- essentially a full success.**
User confirmed directly in Godot: bone matching (41/41, a genuinely
complete match, not partial like every earlier attempt), walking,
and taking hits all correct with zero further fixes needed. The whole
"reconcile two different rigs" class of problem that ate seven
iterations earlier in this file is gone entirely, exactly as expected
once both the character and its animations came from the same system.

One real, separate issue found: at 0 HP, the Barbarian kept cycling
kneel-then-stand-then-kneel instead of holding the kneeling pose.
Cause: "dying" is force-looped by `_setup_animation()` for every family
(existing code, written around KayKit Skeleton's own
"Skeletons_Inactive_Floor_Pose," a genuine held pose meant to loop) --
but Mixamo's "Kneeling Down" turned out to be a stand-to-kneel
TRANSITION, not a held pose, so looping it replayed the whole
transition every cycle. Fixed with a new opt-out, `_loop_dying`
(defaults true, matching every existing family's unchanged behavior;
only `"hero:barbarian"` sets `"loop_dying": false`) -- a non-looping
clip already freezes naturally on its own last frame once finished (the
same mechanism "death" already relies on), which is the actually-
correct behavior for a transition-into-a-pose clip. **Not yet
re-verified live** -- reasoned and applied narrowly (opt-in per family,
so KayKit Skeleton's own working dying pose can't regress), but this
specific fix hasn't been seen running yet.

## Project decision: static models only for new creatures, animation deferred to a future version -- 2026-09-17

After everything above -- a full session getting one humanoid character
animating correctly, only to learn non-humanoid creatures often have no
clean animation path at all, against the backdrop of a real campaign
needing 27+ distinct creatures (Lost Mine of Phandelver's own Appendix B
count) and the full SRD bestiary running to hundreds -- the project
sponsor made a deliberate, top-level call rather than continuing
creature-by-creature: **every new creature/hero model going forward is a
static 3D model, no rigging or animation pipeline at all. Animation
(the whole Meshy/Mixamo/retargeting apparatus this file documents in
such detail above) is explicitly deferred to a future version, once
there's a stable, playable, presentable VTT built on static models
first.** A model that comes with its own physical display base
(mimicking a real tabletop miniature's base) is completely fine -- not
a problem to work around.

**This needed zero code changes** -- `_setup_animation()` already treats
a missing/absent `animation_source` as a fully valid case (it's exactly
how the very first Phase 0 placeholder capsules worked, before any
animation existed in this project at all), and `_ground_model()`'s own
AABB-measurement grounding already works on ANY mesh shape regardless of
whether it's animated, including one with a built-in base -- it just
measures the real lowest point and grounds there. A new `MODEL_CONFIG`
entry going forward needs only `"path"` (and `"label_height"`) -- no
`"animation_source"`, no `bone_name_map`, no `animate_root`/`loop_dying`,
no live bone-name/clip-name verification loop, none of the machinery
the Barbarian's three-pipeline saga needed. This is purely a workflow
simplification, not an architecture change.

**What this actually unlocks**: the entire "find a model, wire it in"
cycle collapses to sourcing a static model and dropping it into
`MODEL_CONFIG` -- no Mixamo upload, no auto-rigger troubleshooting, no
clip-name/bone-name diagnostics, no multi-round live-testing loop. Given
what the Barbarian alone took, this is the difference between "maybe a
handful of creatures ever get built" and "a real campaign's worth of
creatures is actually achievable."

**Existing animated tokens are unaffected** -- Darkhawk, Wren, the
seeded Goblins, the Skeleton, the Orc, and the Barbarian all keep
animating exactly as they already do; this policy governs new work
going forward, it doesn't retroactively strip anything already built.

## Existing animated tokens removed, animation system archived -- 2026-09-17

The "existing animated tokens are unaffected" call above didn't survive
contact with actually living with a mixed static/animated roster: having
some tokens animate and others not made the two feel like different
tiers of an unfinished feature rather than one coherent static-model
game, and every one of the 5 animated families (hero, monster,
monster:skeleton, monster:orc, hero:barbarian) still carries the same
long-term risk that made animation get deferred in the first place --
none of it is truly "done," just not yet broken by the next Godot
import quirk or asset-file loss. The sponsor made a second, narrower
call: rather than keep 5 animated exceptions alongside an otherwise
static-only project, remove them entirely -- every token, including
these 5, now falls back to the plain placeholder capsule until a static
replacement model is sourced for each one.

**Removed, not deleted.** The full working animation system --
rest-pose-relative bone retargeting (`_process()`), both Meshy bone-name
maps (API-rig and website-Mixamo-template conventions), per-clip
cross-file animation import, the death/dying/hit-reaction state machine,
and all 5 `MODEL_CONFIG` entries with their own detailed doc comments
recounting exactly how each was built -- is preserved at
`_archive/animation-system-2026-09-17/` (one directory above `godot/`,
so Godot's own project scanner never sees it -- a second `class_name
Token` inside the scanned project would conflict with the live one).
That folder's own `README.md` has the full restore procedure. The three
animation-diagnostic tools built to verify these pipelines
(`inspect_bone_name_map.gd`, `inspect_kaykit_skeleton.gd`,
`inspect_meshy_orc.gd`) and the three functional smoke tests that drove
a real `Token.apply_data()` against them (`test_skeleton_token.gd`,
`test_imp_token.gd`, `test_orc_token.gd`, each with its own `.tscn`)
moved into the archive alongside it -- each referenced `Token` fields
(`_death_animation_key`, `_bone_map`, etc.) that no longer exist on the
live, simplified script.

**`Token.gd` itself is substantially simplified**, not just missing
config entries: `MODEL_CONFIG` is now empty, every animation-only
instance variable and the two bone-name-map constants are gone, the
death/dying/hit-reaction block in `apply_data()` is gone (along with the
`is_dead`/`is_dying`/`_was_dead`/`_was_dying` tracking that only existed
to drive it), and `_setup_animation()`/`_resolve_or_import()`/
`_import_animation_clip()`/`_on_source_animation_finished()`/
`_resolve_animation_name()`/`_play_source_animation()`/`_process()`/
`_resume_idle_or_dying()` are all gone. Everything static-model-relevant
is unchanged: `_ground_model()`'s AABB-measurement grounding,
`_add_fallback_capsule()`/`_update_fallback_color()`, `_update_hp_bar()`,
`_stat_block_key()`'s per-name lookup (still live -- a future static
per-name entry uses the exact same two-tier `MODEL_CONFIG` lookup the
animated entries used), and `_face_direction()`'s cosmetic snap-turn.
`_animate_to()` keeps its position tween and facing turn, minus the now
-gone walk-animation trigger.

The asset FILES themselves (`barbarian*.fbx`, `orc_warrior.glb`,
`skeleton_warrior.glb`, `imp.glb`, `mannequin_animations.glb`,
`kaykit_rig_medium_*.glb`, `meshy_orc_*.glb`, `superhero_male.gltf`)
were left exactly where they were on disk -- none of them were ever
committed to git (see `godot/assets/README.md`'s own Licensing section),
so this was a pure code-level change; nothing to restore from git if a
future version needs them back, only from wherever they were originally
sourced (or from the archive folder's own restore notes, which name each
one).

## Seven requested features -- 2026-09-19, planned (items 1, 2, 3, and 7 fixed same day)

User request: interactive character creation, visual dice rolls, a 3D
character viewer, a system to import campaigns and create assets, higher-
quality environment assets, spell effects, and spell radius/AoE templates.
Investigated each against what already exists in `engine-server/`,
`dm-bridge/watch.js`, and the 2D app's own `ui/app.js` before writing
anything, rather than assuming any of these start from zero -- several
turned out to have most of their hard logic already built and just never
exposed through this client's UI. Working order: cheapest/most-grounded
first (7, then 1, then 3), the rest after.

1. **Interactive character creation -- fixed 2026-09-19.** Going in, most of
   the hard logic already existed: `engine-server/engine/characterCreator.js`
   (copied verbatim, 299 lines) computes a full level-1+ sheet from a plain
   draft object -- modifiers, proficiency bonus, HP, saves, skills, AC,
   attack bonus -- and renders it as markdown matching the DnD campaign
   repo's `characters/_template.md` shape, and `dm-bridge/watch.js` already
   had a deterministic (no Claude call, no cost) write-back protocol for it
   -- `create-character-request.json` in, watcher writes the `.md` into
   `DND_REPO_PATH/characters/`, never overwriting an existing file,
   `create-character-response.json` out. What was missing was the actual
   Godot form and a way to reach that mailbox.

   **What got built:** rather than port ~300 lines of character math to
   GDScript (the AoE-shape-math precedent item 7 set, but a much larger and
   more error-prone surface here), `engine-server/server.js` now also loads
   `characterCreator.js` into the same engine realm as `encounter.js`/
   `dmBridge.js` and exposes a new `POST /create-character`: validates the
   draft (`CharacterCreator.validateDraft()`, a real 400 with the actual
   reasons on failure), computes the sheet and markdown synchronously
   server-side, then writes `create-character-request.json` and waits (a new
   `createCharacterLock`, mirroring `/dm-command`'s own `dmBridgeLock` --
   its own separate mailbox pair, so it can't race a concurrent
   `/dm-command`) for `create-character-response.json`, same 20s ceiling
   `ui/app.js`'s own `createCharacterResponseTimeoutMs` uses (this is a
   deterministic file write, not a 2-minute Claude call, so no reason to
   share the DM bridge's own 120s one). Returns `{ok, message, fileName,
   character}` -- `ok` can legitimately be false (a filename collision,
   `DND_REPO_PATH` unset) without that being an HTTP-level error, same "a
   miss isn't a 500" precedent `POST /action`'s own attack/save results
   already establish.

   `Main.gd` gained a new "Create Character" collapsible section (built
   entirely in code, same convention as the AoE Template controls and the
   Conditions grid) mirroring `ui/app.js`'s own form field-for-field --
   name/race/class/level/background/alignment, all 6 ability scores (with
   Standard Array and Roll-4d6-Drop-Lowest buttons matching the 2D app's
   own), an AC override, speed, all 18 skill-proficiency checkboxes,
   languages/tools/features/equipment, an optional spellcasting sub-section,
   an attack (weapon/dice/ability/damage-type), personality traits/ideals/
   bonds/flaws, and backstory. Not gated on a selected token, same
   "DM Assistant"/`trigger_lair_action` precedent -- a new character isn't
   acting through an existing one.

   **New tests:** `engine-server/tests/createCharacter.test.js` (4 tests --
   the real HTTP contract against a simulated watcher, an invalid-draft
   400, an `ok:false` outcome surfaced correctly, two concurrent calls
   serialized -- 53/53 passing engine-server-wide) and
   `godot/tools/test_character_creator.gd` (17 assertions -- every control
   actually gets built, and `_character_draft_from_form()` reads them back
   into the exact shape `characterCreator.js` expects), both wired into
   their respective CI jobs.

2. **Visual dice rolls -- fixed 2026-09-19 (saving throws/ability checks/
   initiative; attack and damage dice are a documented follow-up, not
   covered by this pass).** Nothing to reuse going in -- not even the 2D
   app has this; every roll is resolved as pure math server-side
   (`rollDie()` in `encounter.js`) and reported as a text log line.

   **A real scope decision made before writing any code:** the honest way
   to show a physical die is to decide the result server-side FIRST (the
   real roll, already trustworthy and tested) and animate the physics
   toward that known face -- letting physics decide the outcome itself
   would let a client-side desync or a lucky bounce disagree with what the
   server actually rolled and applied. The more thorough way to GET that
   result client-side would be having `encounter.js` return the raw die
   face as a real structured field (not just baked into the message
   string) -- but `encounter.js` is shared, byte-identical with the 2D
   app's own canonical copy (see `ARCHITECTURE.md`), so that would mean
   editing Campaign-OS's own core rules file too, a materially bigger and
   riskier change than this feature actually needs. Instead: the roll is
   already fully decided by the time its log message is generated, and
   that message's wording is fixed and already tested (`engine-server`'s
   own `tests/server.test.js` already regex-asserts it) -- so `Main.gd`
   parses the real result straight back out of the message text it
   already receives on every `/action` response, a legitimate, testable,
   presentation-side concern per `ARCHITECTURE.md`'s own rules/
   presentation split, with zero changes to either engine repo.

   **What got built:** `godot/scripts/DiceRollVisual.gd`
   (`class_name DiceRollVisual`) -- a real `RigidBody3D` cube (not a
   per-face-labeled d20 mesh; a real numbered polyhedron is an asset-
   creation task this project's own static-models-only decision already
   keeps out of scope, see `Token.gd`'s class doc comment) tossed with a
   genuine random physics impulse, landing on the same invisible floor
   collision `GridManager` already builds for click-to-move raycasting,
   then freezing and revealing the real result via a big `Label3D` once it
   settles. `Main.gd` gained `_extract_d20_rolls()` (two regexes anchored
   on `rollSavingThrow()`/`rollAbilityCheck()`/`rollInitiative()`'s own
   exact wording -- confirmed against real captured server responses, not
   guessed) and `_spawn_dice()`, wired into `_on_action_response()` and the
   three roll buttons (`_last_roll_token_id`, captured at send time, tells
   it where to spawn). An advantage/disadvantage pair spawns both dice,
   highlighting whichever one was actually kept in green by matching its
   VALUE against the reported total -- `rollD20WithMode`'s own `[a, b]`
   pair is in roll order, not sorted by kept/discarded, so index alone
   isn't enough.

   **New test:** `godot/tools/test_dice_roll.gd` -- 14 assertions, its
   regex fixtures captured live from a real running `engine-server`
   instance (plain and advantage/disadvantage saves/checks, an initiative
   roll) rather than hand-typed, plus a physics-timing check (forcing
   elapsed time past the settle threshold in one call rather than actually
   waiting) confirming a settled die freezes and can't have its shown
   result moved by further physics. Wired into `godot-smoke-tests`.

3. **Character viewer (3D model) -- fixed 2026-09-19.** No dedicated scene
   existed at all going in -- only `Main.tscn` (battle map), `PlayerView.tscn`
   (read-only battle map), and `Token.tscn` (in-scene miniature).

   **What got built:** a new `godot/scripts/CharacterViewer.gd`
   (`class_name CharacterViewer`, entirely code-built -- no `.tscn` at all,
   same convention as the AoE Template/Character Creator controls, extended
   here to the 3D scene graph itself: lighting, a `WorldEnvironment`, and a
   tight-orbit `CameraRig` instance around one embedded real `Token` scene).
   Opened via a new "View Character (3D)" button in `Main.gd`'s existing
   Other Actions section (a per-selected-token action, same category as
   Remove Token/Damage there) as a real second OS window -- multiple can be
   open at once for different tokens, unlike the single reused Player
   Window, since there's no shared state between viewer instances to
   conflict. Polls `engine-server` independently on its own timer, same
   "a second independent poller is simpler than pushing updates into a
   child window" reasoning `PlayerView.gd` already established.

   The embedded `Token` is driven through the exact same `apply_data()`
   the board itself calls -- model resolution (whatever `MODEL_CONFIG`
   would show on the real board, automatically staying in sync as real
   models get wired in later), grounding, miniature finish, HP bar, name
   label -- rendered close-up, next to a live stat-sheet panel (HP/AC/all
   6 ability scores with modifiers/conditions/spellcasting/resources).

   **Also built, serving the "browse the model-sourcing library" pairing
   directly:** a "Load Model" field that previews an arbitrary `.glb`/
   `.gltf` file from anywhere on disk -- e.g. straight out of
   `I:\Campaign-OS-3D\Downloaded Static Models\`, which sits entirely
   outside this Godot project -- via `GLTFDocument.append_from_file()`,
   Godot's own runtime, importer-independent glTF reader, rather than
   `ResourceLoader.load()` (which only works for files already inside this
   project's own `res://` tree with a real `.import` already generated).
   `.fbx` isn't supported this way -- Godot's FBX pipeline is editor-
   import-time only (the bundled FBX2glTF converter), with no runtime-
   loader equivalent -- but that's the overwhelming minority of that
   library per its own sourcing notes ("models must be plain/static
   `.glb`, not rigged bipeds"). The preview goes through `Token.gd`'s own
   new `preview_external_model()` (grounding + miniature finish, same
   treatment a real `MODEL_CONFIG` entry gets) rather than a simplified
   re-derivation, and is session-only -- never written back to
   `MODEL_CONFIG`.

   **A real, non-obvious bug found and fixed while building this:**
   `queue_free()` only *schedules* removal (at the next idle frame) -- a
   node is still nominally attached to its old parent at the exact point
   `add_child()` would try to re-add it elsewhere, which Godot rejects
   ("already has a parent"). This bit an early version of
   `preview_external_model()` itself: reapplying a Load Model override
   after a poll tick had rebuilt the token's *real* model in between would
   throw. Fixed by making `preview_external_model()` defensively call
   `remove_child()` (synchronous) on its argument's current parent, if any,
   before re-adding it -- safe regardless of the node's current parenting
   state, not just on a fresh never-parented one.

   **New test:** `godot/tools/test_character_viewer.gd` -- 15 assertions,
   including a genuine end-to-end runtime glTF parse against a `.glb`
   already committed to this repo (Kenney's `floor.glb`, not a mocked
   fixture) and a direct regression check for the exact parenting bug
   above, wired into the `godot-smoke-tests` CI job.

4. **Import campaigns + create assets.** Partial, and browser-locked today.
   `engine-server/engine/campaign.js` (copied verbatim, 569 lines) already
   parses a folder of campaign markdown (characters/locations/sessions/
   notes) via `importMarkdownFiles()` and builds spawnable token drafts
   (`tokenDraftFromItem()` -- pulls ability scores, spellcasting, attack
   rows straight out of a character sheet's own markdown). It takes a
   browser `FileList`, though, so it only works in the 2D app as-is --
   `engine-server` has no endpoint for it and Godot has no file picker.
   Worth being precise about scope: this imports narrative/character DATA
   into tokens; it does not generate 3D assets. Map/environment generation
   is the fully separate, manual Meshy/Higgsfield pipeline documented
   elsewhere in this file -- "import a campaign" and "generate 3D assets
   from one" are two different systems that happen to both be gaps, not one
   feature split in two.

5. **High-quality environment assets.** Content work, not code. On hand
   already: Kenney's dungeon-kit (CC0, committed, used by both existing
   maps), plus gitignored-but-downloaded Quaternius MegaKits (buildings/
   nature/props) and KayKit dungeon packs that have never actually been
   used in a built map yet, and one Higgsfield catalog test import. Only 2
   hand-built maps exist (`Prototype Chamber`, `Entrance Hall`). This is
   "build more maps from what's already sitting in
   `godot/assets/Environment/`" using the existing `godot/tools/
   build_*.gd` one-off-script convention, not a new system to design.

6. **Spell effects.** Zero VFX exists anywhere. `cast_spell`/
   `cast_area_spell` are purely mechanical today -- dice, HP change, one log
   line, no particle/shader feedback in `Main.gd` or `Token.gd` at all. New
   work: a small VFX dispatch keyed by damage type and/or spell name,
   `GPUParticles3D` one-shots at caster/target position, triggered off the
   `/action` response the same way `Token.gd`'s move/attack feedback
   already reacts to a state poll.

7. **Spell radius (AoE template tool) -- fixed 2026-09-19.** Best-grounded
   of the seven going in: the hard geometry already existed
   (`pointInCircle`/`pointInCone`/`pointInLine`, already copied into
   `engine-server/engine/encounter.js`), just never wired to a 3D drawing
   tool. `templateCoveredTokenNames()` turned out to be 2D-UI-side only
   (`ui/app.js`, not the shared engine, correcting this file's own earlier
   Feature Parity Audit note above) and needed real porting, not just
   wiring.

   **What got built:** `godot/scripts/AoeTemplate.gd` (new, `class_name
   AoeTemplate`) ports `pointInCircle`/`pointInCone`/`pointInLine` plus a
   `shape_cells()`/`covered_token_names()` pair mirroring `ui/app.js`'s own
   `templateShapeCells()`/`templateCoveredTokenNames()`, all working in the
   same cell-unit space `encounter.js` itself uses (a cell's center at
   `index - 0.5` -- conveniently exactly what a world position divided by
   `GridManager.cell_size` already gives, so no separate offset math is
   needed anywhere this gets used). `Main.gd` gained: an "AoE Template"
   row (Shape dropdown, Size/Width-in-feet SpinBoxes, a toggle button) built
   entirely in code and spliced into the existing Spell section right above
   the Area Spell Targets list (same "build controls in `_ready()`, no
   hand-edited `.tscn` XML" convention the Conditions grid already uses);
   click-to-place for Circle and click-drag-to-aim for Cone/Line (mirroring
   `ui/app.js`'s own `startTemplateDrag`/`dragTemplateAim`, but reading a
   real continuous 3D floor raycast instead of leaning on "screen pixels
   approximate real angles"); a translucent orange `SurfaceTool`-built mesh
   overlay on the board (a circle as a 32-segment fan, cone/line as a
   fan-triangulated polygon); and, going one step past the 2D app's own
   "just show a label" precedent, the covered set now LIVE auto-checks/
   unchecks the real `_area_target_checkboxes` the existing
   `cast_area_spell` button already reads -- toggling "Draw Template" off
   freezes whatever's checked for a final manual adjustment before casting,
   rather than the tool fighting a DM's own override. No changes needed to
   `cast_area_spell` itself or the server at all: this only ever pre-fills
   the same checkbox list that already fed it.

   **A real pre-existing gap found and fixed along the way:** verifying
   this needed a test that could actually exercise `Main.gd`'s
   `_ready()`-time state, which surfaced that `smoke_test_main.gd`/
   `smoke_test_player_view.gd` never actually did what their own doc
   comments claimed. Both call `quit()` synchronously at the end of
   `_init()`, but `_ready()` (and `@onready` assignment) only actually runs
   during the tree's first real iteration -- confirmed directly by probing
   a known `_ready()`-built value (`_template_shape_option`) and finding it
   null immediately after `add_child()`, but populated by the first
   `_process()` tick. Both existing smoke tests were therefore only ever
   catching a scene-file/parse error, never a genuine `_ready()`-time
   runtime error, since the day they were written. Fixed by deferring
   `quit()` to the first `_process()` tick in both files -- confirmed still
   green afterward, now for real.

   **New test:** `godot/tools/test_aoe_template.gd` -- 15 pure assertions
   against `AoeTemplate`'s own shape math (boundary cases, a 90-degree
   rotation, `shape_cells()`'s point counts) plus 8 more driving a real
   `Main.tscn` instance through a synthetic `_apply_state()` call and
   asserting the checkbox auto-check/uncheck/freeze behavior end to end
   (23/23 passing). Wired into `.github/workflows/test.yml`'s
   `godot-smoke-tests` job alongside the three existing smoke tests.

## Adventure map import -- reviewed 2026-09-19, Godot rendering slice built 2026-09-20

A separate tool session (GitHub Copilot, per its own header) produced
`CAMPAIGN_MAP_IMPORT_REPORT.md` at the repo root -- unprompted, found
sitting untracked while the "Seven requested features" work above was in
progress -- proposing a pipeline to import illustrated adventure maps from
`I:\DnD\Adventures & Modules` (Curse of Strahd, Lost Mine of Phandelver,
etc. -- PDFs/images, not a machine-readable VTT format) and generate 3D
battle maps from them, via a new versioned JSON "map manifest" a DM
annotates (grid, walls, doors, elevation) before Godot generates geometry
from it. This is a real gap worth solving -- item 5's own note above
("only 2 hand-built maps exist... every map is hand-built/hardcoded") --
but a distinct one from either item 4 (markdown campaign/character data
import, `campaign.js`, unrelated) or item 5's own original narrower scope
("build more maps from packs already in `godot/assets/Environment/`");
tracked here as its own direction rather than silently folded into either.

**Committed as-is (not modified) for the historical record** -- see that
file directly for the full original proposal, phased plan, manifest schema,
and Godot scene-generation model. What follows is this project's own review
of it, and the actual decision made.

**Agreed with:** the core reframing (hand-authored scenes shouldn't be the
only path to a 3D map); metadata-first over blind image-to-3D conversion
(auto-deriving walls/doors from pixel content alone is a real computer-
vision problem, correctly kept "assistive only, never authoritative"); "the
Node engine remains authoritative for movement, line of sight, encounter
state... rules" -- exactly `ARCHITECTURE.md`'s own already-stated principle;
GridMap + curated `MeshLibrary` for regular dungeon geometry, consistent
with the Kenney/KayKit tile assets already in this project; the licensing
section (adventure PDFs/map art are copyrighted, keep raw source and
derived art out of git, never distribute); phasing discipline in spirit,
singling out "a selected Lost Mine of Phandelver map running in the 3D
client with real tokens and real server-authoritative rules" as the actual
target for a first slice, deferring procedural dressing/curated kits past it.

**Corrected, in order of how much they change the actual plan:**

1. **The report doesn't check whether the 2D app already solved most of
   Phases 1-3.** Confirmed directly (not assumed): `Campaign-OS/ui/app.js`
   already has map image upload (`mapImageInput` -> `setMapImage`), grid
   calibration (`renderGridHandles`), and click-drag wall drawing
   (`toggleWalls`/`renderWallsOverlay`) -- all writing into the exact same
   `state.maps[name]` shape (`setMapImage`/`addWall`) `engine-server`
   already loads verbatim into this project. "Discover a map, calibrate its
   grid, annotate its walls" is a solved problem today, just in the 2D app,
   not Godot. **This inverts the report's own plan**: a DM annotates the
   map in the already-working 2D app (upload the player-safe image,
   calibrate the grid, draw walls with the existing tool); Campaign-OS-3D's
   job shrinks to reading the resulting `state.maps[name]` and rendering 3D
   geometry from it. No new manifest schema, no new annotation editor.
2. **The manifest's relationship to `state.maps[name].walls` (the actual
   thing `hasLineOfSight`/`cellVisibleToHero` read) is underspecified.**
   "Node engine remains authoritative" is stated but the manifest's
   `geometry.walls` isn't shown flowing into a real `addWall()` call -- if
   it stayed a separate, Godot-only description, line-of-sight would
   silently not respect walls a DM just drew. Whatever gets built, the wall
   data needs to actually BE `state.maps[name].walls`, not a second copy.
3. **A real coordinate-convention footgun.** The manifest's example walls
   use grid-CELL coordinates (`"a": [3, 2]`); the real engine's `addWall()`
   uses VERTEX space (cell corners, "index - 0.5"), explicitly documented
   in this project's own `seedState()` as "NOT the 1..columns cell-index
   space tokens use." This exact off-by-half-cell class of bug has already
   cost real iterations here (`Token.gd`'s grounding saga, `GridManager`'s
   floor-offset fix) -- any implementation reuses the engine's own
   conversion, doesn't re-derive it.
4. **Elevation/multi-level walls aren't reconciled against the real
   engine**, which is flatly 2D -- `hasLineOfSight`/`cellVisibleToHero` have
   no elevation concept at all. Building true single-scene multi-elevation
   dungeons would need real new engine work the report doesn't account for.
   **Decided instead:** model each dungeon level as its own separate named
   map, using the multi-map/`switch_map` mechanism that already exists
   (exactly how Prototype Chamber and Entrance Hall coexist today). Stairs
   become "walk onto this cell -> `switch_map`," not new elevation-aware
   line-of-sight.
5. **Phases 3-5 (a full semantic layout editor, curated per-setting
   procedural dressing kits, CV-assisted grid/wall detection) are each
   independently substantial** -- bigger than anything shipped in this
   project so far, and per point 1, Phase 3 in particular is largely
   already-existing 2D-app functionality, not new Godot work. Deferred:
   tracked as a future direction below, not a near-term commitment.

**One addition the report doesn't make:** fog-of-war hiding tokens isn't
the only spoiler risk -- a DM's map image can have room labels or secret-
door markings baked into its own pixels, which per-cell hidden-token logic
wouldn't touch. Checked directly: `PlayerView.gd`'s `_rebuild_fog()` draws
a fully OPAQUE quad per unexplored cell, above the floor geometry -- it
already occludes the underlying texture too, not just tokens, so this
happens to already be safe. Worth stating explicitly rather than assuming
it, since fog being cell-opaque (not token-only) is what actually makes it
safe here.

**One implementation note the report leaves vague:** Godot can't render
PDFs at all; a raster image from an arbitrary OS path is trivially
loadable at runtime (`Image.load()` + `ImageTexture`, the same
runtime-loading idea `CharacterViewer.gd`'s `GLTFDocument` use already
established for external `.glb` files, just simpler for a plain image) --
but a PDF page needs rasterizing to an image FIRST, outside Godot.
`poppler`'s `pdftoppm` is already available in this environment (already
used for D&D PDF text extraction elsewhere) and handles that one step
directly.

**Decided v1 scope**, a fraction of the full report:
1. Confirm in the 2D app that a real published map (rasterized via
   `pdftoppm` first, if it's a PDF page) can be uploaded, grid-calibrated,
   and wall-annotated using the EXISTING 2D tools -- no new code, just
   proving the existing pipeline handles this input. **Not done yet** --
   item 2 below was built and tested against synthetic data first (a
   deliberate choice, so the renderer is verified and ready the moment a
   real map gets annotated, not blocked on that happening first).
2. **Built 2026-09-20.** On the Campaign-OS-3D side: read
   `state.maps[name]` (image reference, columns/rows/feetPerSquare, walls)
   and render it -- a textured floor plane using the calibrated image, plus
   procedural wall meshes generated from the same wall segments the engine
   already uses for line-of-sight.
3. Multi-level dungeons: separate named maps + `switch_map`, not new
   elevation-aware engine work (point 4 above). Not yet needed -- no
   multi-level map exists to switch between.
4. Licensing constraints from the original report are hard requirements
   from day one regardless of how much scope narrows: player-safe image
   only, never commit source PDFs/derived art, track provenance.

**What got built for item 2:** `GridManager.gd` gained
`raster_image_path`/`walls` parameters on `build()`. A raster image (found
via the new `MapImagePath.gd`, `class_name MapImagePath`) renders as a
single large unshaded `PlaneMesh` -- unshaded because a real scanned/
photographed map already has its own baked lighting, and this project's
own angled `DirectionalLight3D` (tuned for miniatures) would otherwise
darken/tint it unpredictably by view angle. Walls generate real
`StaticBody3D` boxes (mesh + collision) from `encounter.js`'s own
`{x1,y1,x2,y2}` segments -- the exact data `hasLineOfSight()` already
uses, so generated geometry can never disagree with what the server
actually enforces, unlike a hand-authored map's separately modeled walls
(which wouldn't update if a DM added a wall via the DM Assistant
mid-session). Orientation uses `Node3D.look_at()`, not hand-derived
rotation math -- `Token.gd`'s `_face_direction()` already established why
this project avoids reasoning out a rotation sign by hand, and this is the
same class of mistake in a new spot. Only applies alongside a raster or
procedural floor, never a hand-built scene (which already carries its own
matching wall geometry -- doubling it would draw overlapping boxes).

**`MapImagePath.gd`'s own resolution convention is explicitly
provisional**, kept in exactly one place so it's easy to revise: a real
map image lives at `engine-server/state/maps/<slugified-map-name>.<ext>`,
a sibling of the Godot project's own `res://` root, gitignored like
`encounter.json` already is. This is NOT the 2D app's own
`state.maps[name].image` field -- confirmed directly, that's an opaque key
into the 2D app's own browser-local IndexedDB image store
(`CampaignOSImageStore`), unreachable from this Node-free, browser-free
Godot process or from `engine-server` (also plain Node, no browser)
either. Today the actual hand-off is manual: a DM saves/exports the same
source image (already calibrated in the 2D app) into this folder
themselves, named to match the map. Automating that hand-off is real
future work, not assumed solved here -- see item 1 above, still open.

**A real bug found and fixed along the way, not specific to maps:**
`GridManager.build()`'s own child-rebuild loop used `queue_free()`, which
only SCHEDULES removal for the next idle frame -- calling `build()` a
second time before that frame ever happens (confirmed live: exactly what
a test asserting after several back-to-back `build()` calls does) would
see the previous batch of children still present, undercounting what had
actually been replaced. Fixed by switching to synchronous
`remove_child()` + `free()` -- nothing outside this function holds a
reference to these children past this point, and `get_children()` is
already a snapshot array, not a live view, so freeing immediately while
iterating it is safe.

**New test:** `godot/tools/test_raster_map.gd` -- 15 assertions, using a
real image already committed to this repo (Kenney's `Sample.png`) copied
to a throwaway temp path, never touching the real `engine-server/state/
maps/` folder. Includes a numeric verification of the generated wall
geometry -- transforming each box's own local endpoints through its real
resulting transform and checking they land exactly on the real input
vertex-space points, rather than trusting the rotation math by
inspection. Wired into `godot-smoke-tests`.

**Explicitly deferred, tracked as a future direction, not a commitment:**
the custom manifest format, a from-scratch semantic layout editor, curated
per-setting procedural dressing kits, and any CV-assisted wall/grid
detection -- everything in the original report's Phases 3-5.
