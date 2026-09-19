# Campaign Map Import and 3D Generation Report

**Prepared by:** GitHub Copilot  
**Date:** 2026-09-19  
**Status:** Research and implementation recommendation; not yet an approved architecture decision.

> **Outcome, 2026-09-19:** Reviewed against this project's actual codebase and
> committed as-is below for the historical record -- the review itself, the
> corrections made to this plan, and the actually-decided (narrower) v1 scope
> live in `ROADMAP.md`'s "Adventure map import" entry, not in this file. The
> single biggest correction: the 2D Campaign-OS app already has a working map
> image upload + grid calibration + wall-drawing tool writing into the exact
> `state.maps[name]` shape this project's engine already shares -- the
> decided plan reuses that directly rather than building the new manifest
> format and annotation editor this report proposes.

## Purpose

This report proposes a path for importing adventures from
`I:\DnD\Adventures & Modules` into Campaign OS 3D and creating usable 3D
battle maps from their supplied map files.

It updates the roadmap's prior "hand-authored Godot scenes only" direction:
hand-authored scenes should remain valuable for showcase locations, but they
should no longer be the only way a campaign map reaches the 3D client.

## Executive recommendation

Build an **assisted, metadata-first map import pipeline**, rather than trying
to fully and automatically convert illustrated adventure maps into accurate 3D
geometry.

The recommended sequence is:

1. Discover PDFs and image maps in an adventure/module directory.
2. Import a selected image or PDF page as a calibrated raster floor texture.
3. Have the DM confirm grid scale, playable bounds, walls, doors, elevations,
   player-safe art, and similar gameplay semantics.
4. Save that meaning in a versioned map manifest.
5. Generate 3D floors, walls, doors, collision, navigation, and deterministic
   set dressing from the manifest.
6. Use authored Godot or GLB scenes only where a location merits premium,
   bespoke work.

This makes existing adventure maps useful immediately, keeps critical game
semantics reviewable, and allows regenerated 3D content as the environment
asset library improves.

## Source-material findings

`I:\DnD\Adventures & Modules` is an adventure-library archive rather than a
machine-readable VTT campaign format.

- The main source types are PDF documents, JPG/JPEG/GIF images, and ZIP
  archives.
- It contains major module collections including *Curse of Strahd*, *Lost Mine
  of Phandelver*, *Tomb of Annihilation*, and *Storm King's Thunder*.
- `I:\DnD\Adventures & Modules\Lost Mine of Phandelver\Lost Mine of Phandelver Maps`
  is a representative image-map directory.
- Some maps have separate player and DM variants, such as
  `CragmawHideout_PlayerVersion...jpg` and
  `CragmawHideout_DMVersion...jpg`.
- No Markdown campaign files were found in this source tree, so this importer
  is separate from Campaign OS's existing Markdown campaign importer.

The directory can be scanned and catalogued automatically. However, its maps
do not reliably include structured data for walls, doors, scale, elevation,
secret areas, encounter zones, or player-safe visibility.

## Automation boundary

| Capability | Appropriate level of automation | Notes |
|---|---|---|
| Find PDFs, images, and archives | Fully automatic | Index paths, hashes, timestamps, dimensions, and thumbnails. |
| Extract or rasterize selected PDF pages | Fully automatic | Keep page number and source provenance. |
| Group files by adventure/module | Fully automatic | Derive from the source directory structure. |
| Generate a textured 3D ground plane | Fully automatic | Once crop and scale are confirmed. |
| Detect grids, labels, rooms, or wall candidates | Assistive only | Detection can provide suggestions for approval. |
| Infer collision, doors, secret doors, elevation, or navigation | DM-confirmed | Never derive authoritative game semantics from illustrated pixels alone. |
| Generate 3D walls/floors/props from approved semantics | Fully automatic after annotation | Deterministic and rebuildable. |

## Recommended map manifest

Store each map's approved semantic meaning separately from its visual source
art. Raster imagery is presentation; the manifest is the authoritative,
portable source for map geometry and gameplay-relevant data.

```json
{
  "schemaVersion": 1,
  "id": "lmop/cragmaw-hideout/main-level",
  "source": {
    "path": "I:/DnD/Adventures & Modules/Lost Mine of Phandelver/Lost Mine of Phandelver Maps/CragmawHideout_PlayerVersion.jpg",
    "sha256": "..."
  },
  "raster": {
    "cropPx": [0, 0, 2250, 1568],
    "pixelsPerGrid": 70,
    "grid": { "columns": 32, "rows": 22, "feetPerCell": 5 }
  },
  "levels": [{ "id": "main", "elevation": 0 }],
  "geometry": {
    "walls": [{ "id": "wall-001", "a": [3, 2], "b": [3, 10], "height": 3 }],
    "doors": [{ "id": "door-001", "cell": [3, 7], "orientation": "east_west" }],
    "stairs": [{ "from": "main", "to": "upper", "bounds": [12, 8, 2, 4] }]
  },
  "gameplay": {
    "spawnZones": [
      { "id": "party-entry", "polygon": [[1, 1], [3, 1], [3, 3], [1, 3]] }
    ]
  },
  "dressing": {
    "seed": 184702,
    "preset": "goblin_cave"
  }
}
```

The manifest should use stable IDs for walls, doors, rooms, and objects so the
Godot client can identify an interaction without relying on unstable scene-node
paths. The Node engine remains authoritative for movement, line of sight,
encounter state, doors, and combat rules.

## Godot scene-generation model

```text
MapRoot
|- RasterGround             # Imported map image on a PlaneMesh
|- GeneratedGeometry
|  |- Floors
|  |- Walls
|  |- Doors
|  `- Stairs
|- Dressing                 # Seeded, deterministic environment props
|- Collision
|- NavigationRegion3D
`- Lighting
```

### Structural generation

For a regular dungeon grid, use `GridMap` and a curated `MeshLibrary` for
coarse modular content such as floor cells, straight/corner walls, doorframes,
stairs, and pillars.

Use normal scene nodes and custom procedural placement for irregular walls,
interactive doors, secret doors, special props, hand-tuned decoration, and any
object that needs a stable semantic ID.

The map's original raster art can stay visible as a tabletop/diorama floor
texture in early versions. Generated floors and props can progressively cover,
blend with, or replace it as the asset kit and art direction mature.

### Collision and navigation

- Static walls, closed doors, and large props should use `StaticBody3D` and
  `CollisionShape3D`.
- Generate or bake navigation at editor/import time where possible.
- Treat Godot navigation as visual/path-preview support. The Node rules engine
  must remain authoritative for D&D grid movement and line-of-sight legality.
- Opening and closing a door should update the semantic state and the relevant
  generated collision/navigation topology; a visual-only obstacle is not enough.

## Implementation phases

### Phase 1: source inventory and provenance

- Add Node-side local tooling to scan `I:\DnD\Adventures & Modules`.
- Index maps, PDFs, images, archives, page/image dimensions, hashes, and
  thumbnails.
- Let the DM select only the intended battle-map page/image; do not bulk-import
  the entire library.
- Define the manifest schema and source-provenance rules.

### Phase 2: calibrated raster maps in 3D

- Import one player-safe source image as a 3D ground-plane material.
- Confirm crop, grid origin, columns, rows, and feet per square.
- Synchronize map selection, token positions, grid, and existing encounter
  state with the Node server.
- Add a simple raised wall overlay created from DM annotation.

**First vertical slice:** a selected *Lost Mine of Phandelver* map should run
in the 3D client using its original player-safe art, current tokens, and
server-authoritative encounter mechanics.

### Phase 3: semantic layout editor

- Add annotations for walls, doors, windows, stairs, levels, room regions,
  spawn zones, and terrain.
- Support import from a simple JSON or SVG representation where available.
- Generate collision, occlusion, visibility boundaries, and map bounds from
  the same manifest.

### Phase 4: procedural geometry and dressing

- Generate modular floors, walls, door scenes, stairs, railings, and ceilings.
- Build curated environment kits by setting: dungeon stone, timber house, cave,
  sewer, crypt, and similar reusable styles.
- Use a fixed seed for generic prop placement and explicit manifest overrides
  for hand-tuned placements.

### Phase 5: premium authored scenes and analysis assistance

- Support a map mode per location: raster-only, hybrid, procedural, or fully
  authored.
- Use authored Godot/GLB scenes for memorable locations where the investment is
  worthwhile.
- Add grid, OCR, room, and wall detection only as an approval-queue assistant.
  It must never silently produce authoritative collision or fog data.

## Licensing and privacy constraints

1. Treat `I:\DnD\Adventures & Modules` as local/private input. Ownership of a
   PDF or module does not itself grant redistribution rights for artwork, maps,
   handouts, tokens, or extracted derivatives.
2. Keep raw adventure PDFs and extracted publisher map art out of Git,
   distributable builds, and public asset packs unless the relevant rights
   explicitly allow it.
3. Separate original-source paths/hashes, local derivative cache files, and
   assets that may legally be redistributed.
4. Preserve separate DM and player map variants. A DM image can reveal secret
   rooms, keyed labels, encounter markers, and other information that must not
   be delivered to a player client.
5. Track licensing/provenance separately for map art, 3D models, textures,
   audio, fonts, and generated derivatives.

## Useful Godot references

- [Runtime file loading and saving](https://docs.godotengine.org/en/4.7/tutorials/io/runtime_file_loading_and_saving.html)
- [Using GridMaps](https://docs.godotengine.org/en/4.7/tutorials/3d/using_gridmaps.html)
- [3D navigation overview](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_introduction_3d.html)
- [Available 3D formats](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)
- [Foundry VTT licensing guide](https://foundryvtt.com/article/licensing-guide/)

## Decision requested before implementation

Approve the following architectural principle before the importer is built:

> Campaign map import creates a reviewed semantic map manifest. Godot renders
> and derives 3D geometry from that manifest, while the Node engine remains the
> authoritative source for gameplay state and rules.

This is the smallest reliable route from the existing adventure library to
repeatable, playable 3D maps without depending on unreliable automatic
interpretation of published map art.
