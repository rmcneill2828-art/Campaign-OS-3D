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

## Licensing -- read before adding more assets from either site

**Kenney** (`Environment/dungeon-kit/`) is genuinely CC0 -- copy, modify,
redistribute, commit to git, no restriction at all. Confirmed by reading its
own `License.txt`, not assumed from Kenney's general reputation.

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

**Neither free-tier pack includes any baked animations** (confirmed by
reading each file's own glTF/glb JSON directly, not assumed from the
"Rigged"/"Retargetable" marketing tags) -- both are a rigged mesh with no
animation clips, so they render in their raw bind pose (a T-pose, arms spread,
for the hero) until a separate animation-source pack is added. Quaternius
publishes a free "Universal Animation Library" pack specifically designed to
retarget onto any of their "Retargetable" rigs -- that's the natural next
download when picking animation back up (see ROADMAP.md).

## Why flattened copies instead of referencing the raw pack folders directly

`Token.gd` loads `res://assets/creatures/hero/superhero_male.gltf` and
`res://assets/creatures/monster/imp.glb`, not the deeply-nested paths inside
`Creatures/hero-pack/.../Godot - UE/` or `Creatures/monster-pack/.../GLB
(Godot-Unreal)/`. Two reasons: those paths contain spaces and `[brackets]`
that are needlessly fragile to reference from code/scenes long-term, and
flattening makes a future per-monster-name art-matching system (mirroring
Campaign-OS's own 2D Token Library) much easier to extend than reaching into
the raw pack structure each time.

If you re-download these packs after a fresh clone, recreate the flattened
copies:

```text
mkdir -p godot/assets/creatures/hero godot/assets/creatures/monster

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
```

## Adding more monsters/heroes later

`Token.gd`'s `MODEL_CONFIG` constant maps a token **type** (`"hero"` /
`"monster"`) to one model -- every monster currently renders as the Imp
regardless of which SRD stat block it actually is (goblin, troll, whatever).
A real per-name mapping (goblin -> some goblin-ish model, etc.) is a natural
follow-up once more monster models are actually on hand -- see ROADMAP.md.
