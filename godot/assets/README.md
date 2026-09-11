# Assets

Empty on purpose right now -- the Phase 0 prototype uses only Godot's built-in
primitive meshes (capsules, boxes, a procedural sky), no imported art at all, so
the camera/grid/token/click pipeline could be proven out with zero art-production
cost or licensing to think about (see `../../ROADMAP.md`).

When Phase 2 starts, this is where imported glTF assets (models, textures) should
live, organized by category (e.g. `assets/creatures/`, `assets/environment/`).
Good CC0 (public-domain-equivalent, no attribution required) sources to start
from, per `../../ROADMAP.md`'s Phase 2:

- **Kenney** -- https://kenney.nl/assets -- broad, consistent low-poly packs,
  several aimed at dungeon/fantasy content specifically.
- **Quaternius** -- https://quaternius.com/ -- CC0 low-poly characters and
  creatures, animated rigs included on many packs.

Both publish glTF (`.glb`/`.gltf`), which Godot imports natively with no plugin.
Confirm each individual pack's stated license before use even though both sites'
general policy is CC0 -- occasional packs/bonus content are licensed differently.
