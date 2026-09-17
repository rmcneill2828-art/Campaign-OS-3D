# Archived: skeletal animation system (2026-09-17)

Deliberately placed OUTSIDE `godot/` (the actual Godot project root, where
`godot/project.godot` lives) so Godot's own project scanner never sees these
files -- a second `class_name Token` inside the scanned project would
conflict with the live one in `godot/scripts/Token.gd`. Every `.gd`/`.tscn`
file in here has been renamed with a trailing `.txt` for the same reason
(belt and braces): plain text, not a script Godot could ever import.

## Why this exists

2026-09-17 project decision (see `ROADMAP.md`'s own entry, and the PROJECT
DECISION comment at the top of `godot/scripts/Token.gd`): every token is now
a static model, no skeletal animation. This folder preserves the full,
actually-working animation system built and live-tested before that
decision, so reintroducing animation in a future version means restoring
this logic, not rebuilding it from scratch after ~10 live-debugging
iterations across two pipeline strategies (Meshy-rig + free-animation
retargeting, then Mixamo's own Auto-Rigger).

## Contents

- `Token.gd.txt` -- the complete `Token.gd` as it stood immediately before
  the static-only refactor: rest-pose-relative bone retargeting (`_process`),
  the two Meshy bone-name maps (API-rig and website-Mixamo-template
  conventions), per-clip animation import across separate source files
  (`_resolve_or_import`/`_import_animation_clip`), the death/dying/hit-
  reaction state machine in `apply_data()`, and all five working
  MODEL_CONFIG entries (`hero`, `monster`, `monster:skeleton`,
  `monster:orc`, `hero:barbarian`) with their own extensive doc comments
  recounting exactly how each was built.
- `tools/inspect_bone_name_map.gd.txt` -- verifies a `bone_name_map` against
  a real character model + animation-source pair.
- `tools/inspect_kaykit_skeleton.gd.txt` -- verified KayKit Skeleton's own
  bone-name compatibility (23/23 bones).
- `tools/inspect_meshy_orc.gd.txt` -- verified the Meshy-generated Orc's
  bone-name compatibility (24/24 bones).
- `tools/test_orc_token.gd.txt`, `tools/test_skeleton_token.gd.txt`,
  `tools/test_imp_token.gd.txt` (+ their `.tscn.txt` scenes) -- functional
  smoke tests that drove a real `Token.apply_data()` and printed the
  resolved animation keys; each references `Token` fields (e.g.
  `_death_animation_key`, `_hit_animation_keys`) that no longer exist on
  the live, simplified `Token.gd`.

## To restore

1. Copy `Token.gd.txt` back over `godot/scripts/Token.gd` (or hand-merge its
   MODEL_CONFIG entries and animation functions/vars into whatever
   `Token.gd` has become by then).
2. Copy the `tools/*.txt` files back into `godot/tools/`, stripping the
   trailing `.txt`.
3. Re-download/re-source the actual model + animation asset files these
   configs reference (`barbarian*.fbx`, `orc_warrior.glb`,
   `skeleton_warrior.glb`, `imp.glb`, `mannequin_animations.glb`,
   `kaykit_rig_medium_*.glb`, `meshy_orc_*.glb`, `superhero_male.gltf`) --
   none of these binary assets are committed to git (see
   `godot/assets/README.md`), so they aren't in this archive either; they
   were never deleted from disk by this refactor, only the code that
   referenced them.
4. Re-run a headless editor pass (`--headless --editor --path godot --quit`)
   so Godot re-scans the restored files before anything tries to load them.
