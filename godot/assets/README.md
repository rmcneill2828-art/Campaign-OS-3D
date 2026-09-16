# Assets

## What's here

- **`Environment/dungeon-kit/`** -- Kenney's "Mini Dungeon" kit. **CC0** (public
  domain equivalent, no attribution required) -- committed to this repo.
  `GridManager.gd` uses `Models/GLB format/floor.glb` (+ `floor-detail.glb` for
  visual variety) directly; the FBX/OBJ format variants and preview images
  aren't used and are gitignored as plain repo hygiene (see `.gitignore`), not
  a license restriction.
- **`Creatures/hero-pack/`** and **`Creatures/monster-pack/`** -- the raw,
  as-downloaded Quaternius packs ("Universal Base Characters", "Bestiary -
  Dungeon Monsters Kit"), kept around for reference (license text, previews)
  but NOT scanned by Godot (`.gdignore` in each) and NOT committed to git --
  see Licensing below.
- **`creatures/hero/`** and **`creatures/monster/`** -- the small, flattened
  set of files `Token.gd` actually loads at runtime, copied out of the raw
  packs above (see "Why flattened copies" below). Also not committed.
- **`Creatures/animation-library/`** -- the raw, as-downloaded Quaternius
  "Universal Animation Library" packs (both v1 and v2 were downloaded; only
  v1's non-root-motion export is actually used, see below). Same QAL license
  and not-committed treatment as the hero/monster packs.
- **`creatures/animations/mannequin_animations.glb`** -- the flattened file
  `Token.gd` actually loads (`UAL1_Standard.glb`, the **non**-`_RM` variant --
  see Licensing below for why). Also not committed.
- **`creatures/monster/skeleton_warrior.glb`** (+ its sibling
  `skeleton_texture.png`) and **`creatures/animations/kaykit_rig_medium_special.glb`**/
  **`kaykit_rig_medium_general.glb`** -- Phase 8's flattened KayKit files,
  same pattern as the two above. `_movementbasic.glb`/`_combatmelee.glb`/
  `_simulation.glb` were also flattened while surveying the pack's real clip
  list (`godot/tools/inspect_kaykit_skeleton.gd`) but aren't actually loaded
  by `Token.gd` -- harmless to delete, kept only as a convenient local copy
  if a future monster wants a clip from one of them too. **Not committed**
  either, despite being genuinely CC0 with no license reason to exclude them
  -- `.gitignore`'s existing blanket `godot/assets/creatures/` rule (there
  for the QAL-licensed Quaternius files next to them) sweeps these up too,
  the same "convenience, not license" sweep-up its own comment already
  applies to the raw KayKit pack folders. A fresh clone needs to re-run the
  copy step below for these too, same as the Quaternius-derived files.
- **`creatures/monster/orc_warrior.glb`** and **`creatures/animations/meshy_orc_*.glb`**
  (idle/walk/death/hit1/hit2/kneel, 6 files) -- Phase 8's custom-generated
  model for the SRD "Orc," no free pack covered it. Generated on demand via
  the Composio-connected Meshy API (text-to-3D -> remesh -> rig+texture ->
  one animation-library clip per file) rather than downloaded from a fixed
  pack -- there's no raw source folder to point back to the way the
  Quaternius/KayKit entries above have; regenerating means re-running the
  same API calls, not re-flattening a re-downloaded zip. Cost 78 Meshy
  credits total for this one monster, including a real follow-up fix (see
  `ROADMAP.md`'s Phase 8 entry: the first texture came out scrambled
  because it was baked for a different mesh topology than the one that got
  rigged -- fixed with a proper `MESHY_CREATE_RETEXTURE_TASK` against the
  actual final geometry). See `MODEL_CONFIG`'s own comment in `Token.gd`
  for the exact pipeline and why every clip needed the `{clip, source}`
  cross-file import form. **Not committed** -- same gitignore sweep-up as
  the KayKit files above, no license reason either (this is the user's own
  generated content) but swept into the same ignored tree by convenience.
- **`creatures/hero/barbarian.glb`** -- the first per-name HERO model
  (`MODEL_CONFIG`'s `"hero:barbarian"`), a different pipeline than the Orc
  above: a free static model downloaded from Meshy's own library (not
  text-to-3D generated), then rigged through Meshy's WEBSITE Rigging tool
  with "Skeleton template: Mixamo" selected -- a choice only the website
  UI exposes, not the API `orc_warrior.glb` went through, producing genuine
  `mixamorig:`-prefixed bone names. **Not committed** -- same gitignore
  sweep-up as the Orc files above, no license reason established either way
  (Meshy's own ToS governs this the same unverified way noted for the Orc).
- **`creatures/animations/mixamo_idle.fbx`, `mixamo_walk.fbx`,
  `mixamo_death.fbx`, `mixamo_reaction.fbx`, `mixamo_hit_reaction.fbx`** --
  the Barbarian's actual animation source, real Adobe Mixamo clips
  (mixamo.com), manually downloaded "without skin" (a handful of files, not
  a bulk/automated pull -- see `ROADMAP.md`'s own note on why automating
  Mixamo was ruled out for building a whole creature library, but a few
  manual downloads for one shared animation set weren't). License: free,
  no royalties, commercial and non-commercial use both fine, no attribution
  required (already confirmed in `ROADMAP.md`'s earlier Mixamo research
  note) -- same "don't redistribute the raw files standalone" restriction
  every other pack here already follows, so **not committed**, same
  gitignore sweep-up as everything else in this tree.
  Tried first: `MESHY_MIXAMO_TEMPLATE_TO_QUATERNIUS_UAL1_BONE_MAP`, a
  rest-pose-relative retargeting scheme bridging the Barbarian's rig onto
  the existing Quaternius UAL1 library (same file the plain `"hero"` entry
  above uses). Got legs/spine/face looking correct after several live-
  tested fixes, but never fully resolved the shoulders even after two more
  rounds -- real diminishing returns trying to reconcile two genuinely
  different rigs' rest poses through rotation math alone. Real Mixamo
  animations sidestep the whole problem: they use the EXACT SAME bone-
  naming convention Meshy's own "Skeleton template: Mixamo" rig output
  does, confirmed directly (both real files extracted and compared, not
  assumed), so this is now the same plain exact-name bone matching the
  `"hero"` entry's own Quaternius pairing already relies on -- no
  bone_name_map, no delta math, nothing left to mismatch. The Quaternius-
  based map/mechanism is left in place (not deleted) as real, working,
  tested infrastructure for a FUTURE Meshy-rigged model where downloading
  matching Mixamo clips isn't practical for some reason -- just no longer
  what the Barbarian itself uses.
  All 5 downloaded FBX files share the exact same internal clip name
  (`"mixamo.com"`) -- confirmed directly against the actual files (a
  well-known, real Mixamo export quirk, not assumed), which is why
  `Token.gd`'s clip-import helper needed a new `"as"` field (see its own
  doc comment) to store each under a distinct key rather than have them
  silently overwrite each other. No dedicated "dying" (kneeling/downed)
  pose was among what got downloaded -- left unset rather than forcing a
  short reaction clip to loop awkwardly as a stand-in.
- **`Environment/kenney-dungeon/`** -- an exact duplicate of `dungeon-kit`
  above (same "Mini Dungeon (2.0)" pack, re-downloaded under a different
  folder name). Zero new content -- gitignored, safe to delete whenever.
- **`Environment/quaternius-buildings/`**, **`Environment/quaternius-props/`**,
  **`Environment/quaternius-nature/`** -- three more Quaternius packs
  ("Medieval Village MegaKit" / 176 pieces: walls, doors, windows, roofs,
  stairs, overhangs; "Fantasy Props MegaKit" / 94 pieces: furniture, barrels,
  books, weapons, tableware, etc.; "Stylized Nature MegaKit" / 68 pieces:
  trees, bushes, rocks, grass, flowers), downloaded for Phase 4's
  hand-authored maps. **Genuinely CC0** this time (confirmed per-pack, see
  Licensing below), but still gitignored for now as plain repo hygiene --
  each raw download bundles ~70-180 models across FBX/OBJ/glTF/Textures all
  at once, most of which won't end up in any given map. No flattened copies
  exist yet since nothing has used them yet; see "Why flattened copies" below
  for the pattern once a real map picks specific pieces.
- **`Creatures/hero-pack/KayKit_Adventurers_2.0_FREE/`**,
  **`Creatures/monster-pack/KayKit_Skeletons_1.1_FREE/`**,
  **`Creatures/animation-library/KayKit_Character_Animations_1.1/`**,
  **`Environment/kaykit-dundeons/`** -- Kay Lousberg's "KayKit" packs,
  downloaded as a real per-name monster/hero option (see KayKit below) and a
  stylistically-different dungeon-kit alternative. **Genuinely CC0**
  (confirmed per-pack). **Phase 8 (2026-09-13): Skeletons wired into
  `Token.gd`** -- `Skeleton_Warrior.glb` + a merged animation source (the
  Character Animations pack's Rig_Medium `Special.glb` for its own
  skeleton-specific idle/walk/death/dying clips, `General.glb` for generic
  Hit_A/Hit_B reactions imported into the same player at runtime) drive any
  monster token named "Skeleton" (matching the SRD stat block spawnMonster()
  produces), via a new per-monster-name entry in `Token.gd`'s own
  `MODEL_CONFIG` (`"monster:skeleton"`) -- see that file's own doc comment
  for the two-tier type/name lookup this introduced. Rig compatibility
  verified directly (`godot/tools/inspect_kaykit_skeleton.gd`: 23/23 bones
  match across every animation file checked), not assumed from a shared
  "Rig_Medium" folder name, exactly the check this section used to flag as
  outstanding. Adventurers (hero replacement) and Dungeon Remastered
  (environment) remain downloaded and cataloged only, same "gather now,
  integrate when a real feature needs it" pattern as the Quaternius MegaKits
  above.

## Licensing -- read before adding more assets from either site

**Kenney** (`Environment/dungeon-kit/`) is genuinely CC0 -- copy, modify,
redistribute, commit to git, no restriction at all. Confirmed by reading its
own `License.txt`, not assumed from Kenney's general reputation.

**Not every Quaternius pack uses the same license -- check each one
individually, don't generalize from a previous pack.** The three environment
MegaKits (`quaternius-buildings/`, `quaternius-props/`, `quaternius-nature/`)
are genuinely **CC0 1.0 Universal** (confirmed by reading each pack's own
`License_Standard.txt` -- literally the same filename convention the QAL
packs below use, but different license text inside), while the
character/monster/animation packs are the more restrictive QAL. They're
currently gitignored anyway (see `.gitignore`), but that's for a completely
different reason than the Creatures/ packs below -- repo hygiene (unused
format variants), not a license requirement. Feel free to un-ignore and
commit them wholesale if you'd rather not deal with the flatten-on-demand
workflow -- nothing about their license argues against it.

**Quaternius** (`Creatures/`) is a different, more specific license than the
"just CC0" shorthand used earlier in this project's own history --
confirmed by actually reading `License_Standard.txt` inside each pack, not
assumed. It's the **Quaternius Asset License (QAL) v1.0**
(https://quaternius.com/license.html): free to use, modify, and ship inside a
game with no attribution required, **but you may not redistribute the raw
asset files themselves** (section 3(a) -- no reselling, repackaging, or
otherwise distributing them as standalone files, even for free, even
modified). Committing them to a git repo would do exactly that -- anyone who
clones the repo could pull the raw model files back out on their own -- so
they're gitignored and stay local-only. **This project is fine either way**
(the license permits using them here); what it doesn't permit is checking the
raw files into version control. If you re-clone this repo on another machine,
you'll need to re-download these two packs and re-run the copy step below.

Both packs used here are the free "Standard" tier, which only includes a
**subset** of each pack's full content:
- Universal Base Characters: only `Superhero_Male_FullBody` /
  `Superhero_Female_FullBody` (no fantasy-armor variants -- that's a separate
  "Modular Character Outfits" pack, not currently used, see the main
  conversation history/ROADMAP.md for why it was skipped for Phase 2).
- Bestiary - Dungeon Monsters Kit: only `Imp` and `Puglin` (5 of the 7
  monsters shown on the pack's own marketing image require buying the
  "SOURCE" tier).

**Neither free-tier character pack includes any baked animations** (confirmed
by reading each file's own glTF/glb JSON directly, not assumed from the
"Rigged"/"Retargetable" marketing tags) -- both are a rigged mesh with no
animation clips of their own. Animation comes from a separate pack instead
(see below).

### Animation Library

Two packs are on quaternius.com under "Universal Animation Library" -- v1 and
v2, each covering a different, non-overlapping set of clips (v1: Idle/Walk/Jog/
Sprint/basic combat/emotes; v2: more elaborate sword combos, climbing,
zombie-specific moves, etc.). Both were downloaded; **only v1's `UAL1_Standard.glb`
is currently used** (`Idle_Loop` + `Walk_Loop`, see `Token.gd`) -- v2 is sitting
in `Creatures/animation-library/` unused for now, a natural place to look when
adding more animation states (attack, death, etc.) later.

Each pack's `Unreal-Godot` folder has two files: a plain one and one suffixed
`_RM`. `_RM` = **root motion** -- the animation physically translates the
skeleton's root bone forward during a walk/run cycle (meant for games where
the animation itself drives movement). This project's tokens already have
their position driven externally (`GridManager`/`Main.gd`'s own tween, from
the server's real grid coordinates) -- using the root-motion variant would
fight that, moving the visual model away from its assigned tile independently
of the actual game state. **Always use the plain (non-`_RM`) file here.**

**Skeleton compatibility was verified by direct comparison, not assumed from
the "Retargetable" tag**: `UAL1_Standard.glb`'s skeleton bone *names* match
`superhero_male.gltf`'s exactly, and `imp.glb`'s bones are a strict subset of
the same set (missing only finger/toe-tip bones neither model's silhouette
needs to move independently). `Token.gd`'s `_setup_animation()` uses this
directly -- copying bone poses by name from a hidden instance of the animation
file onto the visible model's own skeleton every frame -- rather than trying
to graft the animation library's `AnimationPlayer` tracks onto a different
scene's node structure, which would depend on Godot's glTF importer producing
identical scene layouts across different files, an assumption this project
got burned by more than once already this phase (see `ROADMAP.md`'s Phase 2
entry on the floating-model/floor-height bugs).

### KayKit (Kay Lousberg)

Downloaded to fix a real, named gap: every monster token renders as the same
Imp model today regardless of which SRD stat block it actually is (see
"Adding more monsters/heroes later" below). **Genuinely CC0 for all four
packs** (confirmed by reading each `License.txt` directly, not assumed from
Quaternius's own precedent in this same file -- different creator, no reason
to assume the same terms), attribution optional, not required.

- **KayKit Adventurers** (`Creatures/hero-pack/KayKit_Adventurers_2.0_FREE/`)
  -- 6 self-contained hero models (`Characters/gltf/*.glb`): Barbarian,
  Knight, Mage, Ranger, Rogue, Rogue_Hooded. Plus weapon/shield/prop
  accessories under `Assets/gltf/` (swords, bows, staffs, shields, etc.) as
  separate attachable meshes, not currently used.
- **KayKit Skeletons** (`Creatures/monster-pack/KayKit_Skeletons_1.1_FREE/`)
  -- 4 self-contained skeleton models (`characters/gltf/*.glb`):
  Skeleton_Warrior, Skeleton_Mage, Skeleton_Rogue, Skeleton_Minion -- a real
  match for the engine's actual "skeleton" SRD monster, not a reuse of
  something else. Plus weapon accessories under `assets/gltf/`.
- **KayKit Character Animations** (`Creatures/animation-library/KayKit_Character_Animations_1.1/`)
  -- the full shared animation library, split by rig size
  (`Animations/gltf/Rig_Medium/`, `Rig_Large/`) and further by category into
  8 files per rig (`Rig_Medium_General.glb`, `_MovementBasic.glb`,
  `_MovementAdvanced.glb`, `_CombatMelee.glb`, `_CombatRanged.glb`,
  `_Simulation.glb`, `_Special.glb`, `_Tools.glb`) -- together 130+
  individual clips, well beyond Quaternius's ~40. Both Adventurers and
  Skeletons also bundle a 2-file subset of this same library locally
  (`General` + `MovementBasic` only) for convenience; this full pack is the
  one to actually use as the shared animation source, same "one shared
  source, not a per-character copy" pattern `mannequin_animations.glb`
  already established for Quaternius.
- **KayKit Dungeon Remastered** (`Environment/kaykit-dundeons/`) -- 200+
  dungeon pieces (`.../Assets/gltf/`), a stylistically different alternative
  to Kenney's `dungeon-kit`. Packaged as a Godot addon folder structure
  (`addons/kaykit_dungeon_remastered/`) from its GitHub distribution rather
  than itch.io's plain zip -- the actual models live at
  `addons/kaykit_dungeon_remastered/Assets/gltf/` either way.

**Rig compatibility, verified the same way as Quaternius's -- not assumed
from Adventurers/Skeletons both shipping a "Rig_Medium" folder name alone**:
before wiring any of this into `Token.gd`, confirm Adventurers' and
Skeletons' actual skeleton bone names match the Character Animations pack's
`Rig_Medium` skeleton the same direct-comparison way `imp.glb`/
`superhero_male.gltf` were checked against Quaternius's UAL1 earlier in this
file -- don't assume a shared rig NAME implies shared bone names without
checking. **KayKit's rig is a different, separate skeleton from
Quaternius's** (different creator, no shared convention).

**Update, Phase 8 (2026-09-13): done.** The Skeletons check above came back
23/23 matched (`godot/tools/inspect_kaykit_skeleton.gd`), and `Token.gd`'s
`MODEL_CONFIG` is now genuinely per-model-family -- each entry names its own
`animation_source` file, so Quaternius families keep using
`mannequin_animations.glb` while the skeleton family uses a KayKit one,
with no shared global constant forcing them to match. See `Token.gd`'s own
doc comment on `MODEL_CONFIG` for the full shape, including the later
`{clip, source}` per-field form Meshy's orc needed.

### Meshy AI (custom-generated, Phase 8)

Unlike every pack above, `orc_warrior.glb` and its animations aren't from a
fixed downloadable pack at all -- they were generated on demand via the
Composio-connected Meshy API (text-to-3D -> remesh -> rig+texture -> one
preset animation-library clip per file), the first entry in this project's
own "custom created models" research (see `ROADMAP.md`'s Phase 8 entry for
the full pipeline and a real gotcha hit along the way: texturing and
rigging had to target the SAME remeshed/low-poly geometry, not the
original high-poly preview, or the two outputs end up on different,
incompatible topologies). **Licensing not independently verified the way
Kenney/Quaternius/KayKit's were above** -- Meshy's own terms of service
govern ownership/usage of content generated through a paid account, and
haven't been read line-by-line here the way this project insists on doing
for a real license file elsewhere in this document; treat that as an open
item if this content's licensing status ever actually matters (e.g.
distributing this repo's assets beyond personal use), rather than an
established, confirmed fact the way the CC0/QAL findings above are.

### Higgsfield "3D Jutsu" catalog (Phase 8 test import, now a real Phase 4 map)

**`Environment/higgsfield-test/`** -- 8 real assets pulled from Higgsfield's
"3D Jutsu" scene-builder catalog (a Composio-connected toolkit): the
original 3 test pieces (`dun_wall_torch`, `dun_treasure_chest`,
`dun_corridor_straight`) plus 5 more pulled specifically to build a real
second map (`dun_room_floor`, `dun_room_wall`, `dun_arch_doorway`,
`dun_wall_corner`, `dun_wall_doorway`) -- see `godot/scenes/maps/
entrance_hall.tscn` and `ROADMAP.md`'s Phase 4 entry. The catalog itself
turned out to be a genuinely rich, cohesive modular dungeon set (85 hits
searching just "dungeon" -- full corridor pieces, walls, stairs, doors,
dense atmospheric props) -- see `ROADMAP.md`'s Phase 8 entry for the full
exploration, including a real pipeline bug found and fixed
(`_fixed.tscn` alongside each raw `.glb`: Godot's glTF importer leaves
`vertex_color_use_as_albedo` off, so every piece renders flat white despite
carrying real per-vertex color data underneath -- confirmed directly, not
assumed, and fixed via `godot/tools/fix_higgsfield_vertex_colors.gd`; all 8
pieces have a `_fixed.tscn` counterpart, and only the fixed versions are
ever referenced from `build_entrance_hall.gd`/the saved map scene).

**Licensing: genuinely unresolved, not established the way CC0/QAL are
above.** Higgsfield's own Terms of Use has no section covering the
pre-made catalog specifically, and their blog post says the catalog mixes
their own curated assets with actual Mixamo characters -- not one uniform
source. Discussed directly with the user: acceptable for this project's
own private, non-commercial, never-distributed use (most such
restrictions target distribution/resale, not personal use), but this is a
materially lower level of certainty than every other source in this file,
and NOT something to assume still holds if this project is ever published
or distributed, even for free -- get Higgsfield's explicit confirmation
first if that ever changes. **Not committed** (see `.gitignore`) for that
same reason, on top of the usual repo-hygiene convention every other
vendor-sourced folder here already follows.

## Why flattened copies instead of referencing the raw pack folders directly

`Token.gd` loads `res://assets/creatures/hero/superhero_male.gltf` and
`res://assets/creatures/monster/imp.glb`, not the deeply-nested paths inside
`Creatures/hero-pack/.../Godot - UE/` or `Creatures/monster-pack/.../GLB
(Godot-Unreal)/`. Two reasons: those paths contain spaces and `[brackets]`
that are needlessly fragile to reference from code/scenes long-term, and
flattening makes a future per-monster-name art-matching system (mirroring
Campaign-OS's own 2D Token Library) much easier to extend than reaching into
the raw pack structure each time.

**After extracting any raw Quaternius pack into `Creatures/<pack-name>/`, also
drop an empty `.gdignore` file in it** (`touch "Creatures/<pack-name>/.gdignore"`)
before opening/reloading the project in Godot. Without it, Godot scans and
tries to import the whole raw download -- which is how a missing one on the
animation-library pack surfaced as a "Blender executable required" import
prompt (one of Universal Animation Library 2's bonus files ships a `.blend`
source alongside the `.glb` exports this project actually uses) the first
time this project hit it. Same reasoning as the FBX/OBJ-format `.gdignore`
entries already covering the Kenney pack's unused format variants.

If you re-download these packs after a fresh clone, recreate the flattened
copies:

```text
mkdir -p godot/assets/creatures/hero godot/assets/creatures/monster
touch "godot/assets/Creatures/hero-pack/.gdignore" \
      "godot/assets/Creatures/monster-pack/.gdignore" \
      "godot/assets/Creatures/animation-library/.gdignore"

HERO_SRC="godot/assets/Creatures/hero-pack/Universal Base Characters[Standard]/Base Characters/Godot - UE"
cp "$HERO_SRC/Superhero_Male_FullBody.gltf" godot/assets/creatures/hero/superhero_male.gltf
cp "$HERO_SRC/Superhero_Male_FullBody.bin" godot/assets/creatures/hero/superhero_male.bin
cp "$HERO_SRC"/T_Hair_1_BaseColor.png "$HERO_SRC"/T_Hair_1_Normal.png \
   "$HERO_SRC"/T_Eye_Brown.png "$HERO_SRC"/T_Eye_Normal.png \
   "$HERO_SRC"/T_Superhero_Male_Normal.png "$HERO_SRC"/T_Superhero_Male_Dark.png \
   "$HERO_SRC"/T_Superhero_Male_Roughness.png godot/assets/creatures/hero/

# Quaternius's own gltf export references two texture filenames with a "_png"
# typo that doesn't match any file that actually exists in the download
# (T_Hair_1_Normal_png.png / T_Eye_Normal_png.png) -- fix the references in
# OUR copy of the gltf (never redistributed, so nothing to worry about there):
sed -i \
  -e 's/Superhero_Male_FullBody\.bin/superhero_male.bin/' \
  -e 's/T_Hair_1_Normal_png\.png/T_Hair_1_Normal.png/' \
  -e 's/T_Eye_Normal_png\.png/T_Eye_Normal.png/' \
  godot/assets/creatures/hero/superhero_male.gltf

MONSTER_SRC="godot/assets/Creatures/monster-pack/Bestiary - Dungeon Monsters Kit[Standard]/Exports/GLB (Godot-Unreal)"
cp "$MONSTER_SRC/Imp.glb" godot/assets/creatures/monster/imp.glb

mkdir -p godot/assets/creatures/animations
cp "godot/assets/Creatures/animation-library/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb" \
   godot/assets/creatures/animations/mannequin_animations.glb

# Phase 8 -- KayKit Skeletons + its own animation-library files. Genuinely
# CC0 (no gtlf-typo/bin-rename fixups needed, unlike Quaternius above), just
# swept into the same gitignored tree by convenience, not license -- see
# this file's own KayKit section.
SKELETON_SRC="godot/assets/Creatures/monster-pack/KayKit_Skeletons_1.1_FREE/characters/gltf"
cp "$SKELETON_SRC/Skeleton_Warrior.glb" godot/assets/creatures/monster/skeleton_warrior.glb
cp "$SKELETON_SRC/skeleton_texture.png" godot/assets/creatures/monster/skeleton_texture.png

ANIM_SRC="godot/assets/Creatures/animation-library/KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium"
cp "$ANIM_SRC/Rig_Medium_Special.glb" godot/assets/creatures/animations/kaykit_rig_medium_special.glb
cp "$ANIM_SRC/Rig_Medium_General.glb" godot/assets/creatures/animations/kaykit_rig_medium_general.glb
```

## Adding more monsters/heroes later

`Token.gd`'s `MODEL_CONFIG` constant maps a token **type** (`"hero"` /
`"monster"`) to one model -- every monster currently renders as the Imp
regardless of which SRD stat block it actually is (goblin, troll, whatever).
A real per-name mapping (goblin -> some goblin-ish model, etc.) is a natural
follow-up once more monster models are actually on hand -- see ROADMAP.md.
