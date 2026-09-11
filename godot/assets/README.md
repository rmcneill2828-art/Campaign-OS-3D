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
```

## Adding more monsters/heroes later

`Token.gd`'s `MODEL_CONFIG` constant maps a token **type** (`"hero"` /
`"monster"`) to one model -- every monster currently renders as the Imp
regardless of which SRD stat block it actually is (goblin, troll, whatever).
A real per-name mapping (goblin -> some goblin-ish model, etc.) is a natural
follow-up once more monster models are actually on hand -- see ROADMAP.md.
