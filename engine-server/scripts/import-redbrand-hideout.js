"use strict";

// ROADMAP.md's "Adventure map import" entry, decided v1 scope item 1: prove a real
// published adventure map (not a synthetic test fixture) can be calibrated and
// wall-annotated using the same primitives the 2D app's own grid-calibration/wall-
// drawing UI calls (setMapImage/setMapGrid/addWall), then rendered in Godot via
// GridManager's raster-floor + generated-wall-mesh support (built 2026-09-20).
//
// This is a ONE-OFF DATA SCRIPT, not a feature -- same spirit as godot/tools/
// build_prototype_chamber.gd, just on the server-state side instead of a .tscn.
// It contains no copyrighted map artwork itself, only measured grid/wall geometry
// (columns/rows/vertex coordinates) -- the actual image file stays wherever the
// caller's own legally-owned copy already lives and is copied into
// engine-server/state/maps/ (gitignored, never committed, per the roadmap's own
// hard licensing requirement).
//
// Scope: all twelve of the source map's rooms are wall-annotated. This went
// through two passes: an initial 2-room slice (11/12 only) that proved the
// pipeline end to end, then a full-map attempt measured by eye from upscaled
// image crops (DM-level precision, not a laser survey) -- both scripted,
// since no browser-automation tool was available to drive the 2D app's own
// UI directly. The WALLS below are neither of those: they're the REAL
// output of the user actually doing the calibration/wall-drawing in
// Campaign-OS's own browser UI (Adjust Grid + the Walls tool), exported from
// that app's localStorage and transcribed here verbatim (only the object
// {x1,y1,x2,y2} shape was converted to this file's own [x1,y1,x2,y2] array
// shape -- no coordinates were changed). This is the actual workflow
// ROADMAP.md's "decided v1 scope" always intended -- "a DM annotates the map
// in the already-working 2D app" -- finally exercised for real instead of
// approximated by a script guessing pixel positions. Notably, the user's own
// grid calibration independently landed on the same 30x21 grid this
// project's own long-baseline pitch measurement had already derived --
// cross-validating that earlier fix. The central chasm (Room 8) has no
// walls, matching this session's own call: a chasm doesn't block line of
// sight in 5e rules, and this engine has no elevation/pit modeling anyway.
//
// Usage: node scripts/import-redbrand-hideout.js <path-to-source-image>
// The source image is the DM version of Lost Mine of Phandelver's "Redbrand
// Hideout" map (Wizards of the Coast / Mike Schley) -- point this at your own
// legally-owned copy, e.g. from a purchased LMoP PDF's extracted map assets.

const fs = require("node:fs");
const path = require("node:path");

const { loadEngineInto } = require("../lib/loadEngine");
const { loadState, saveState } = require("../server");

const STATE_FILE = path.join(__dirname, "..", "state", "encounter.json");
const MAPS_DIR = path.join(__dirname, "..", "state", "maps");

const MAP_NAME = "Redbrand Hideout";
// Matches MapImagePath.gd's own slugify() convention exactly (lowercase,
// non-alphanumeric runs collapsed to one underscore) -- it resolves this map's
// raster image purely from the map NAME, so the file must land at this exact path.
const DEST_IMAGE_PATH = path.join(MAPS_DIR, "redbrand_hideout.jpg");

// Measured directly from a 2475x1725 scan of the map's DM version. A real DM
// calibrating this same image in the 2D app's UI would eyeball the same grid
// handles to a similar (not pixel-perfect) result; this is that same act,
// scripted instead of dragged, per this session's own agreed methodology.
//
// IMPORTANT, found the hard way while this project's own scripted attempt
// was still standing in for the real 2D-app workflow (see ROADMAP.md):
// GridManager's raster floor stretches the ENTIRE source image across the
// ENTIRE COLUMNS x ROWS grid -- vertex (0,0) is the image's literal
// top-left pixel (parchment border and all), not wherever a particular room
// happens to start. This is exactly what the 2D app's own Adjust Grid tool
// gets right automatically (the drag handles are calibrated against the
// whole visible image), which is a real point in favor of trusting its
// output over a script's own pixel guesswork.
const COLUMNS = 30;
const ROWS = 21;
const FEET_PER_SQUARE = 5;

// Vertex-space wall segments (integer corners 0..COLUMNS / 0..ROWS, same
// convention encounter.js's own addWall() documents and Prototype Chamber/
// Entrance Hall's seedState() calls already use). Transcribed verbatim from
// the user's own Campaign-OS session -- see the file header for provenance.
// Not grouped/commented by room (unlike the two prior scripted attempts this
// replaced) since these came out of the 2D app in whatever order the user
// drew them, not room-by-room.
const WALLS = [
  [2, 3, 2, 7], [2, 7, 4, 7], [5, 7, 6, 7], [6, 7, 6, 5], [6, 3, 6, 4],
  [6, 6, 10, 6], [11, 3, 11, 6], [10, 3, 10, 6], [16, 3, 16, 4],
  [16, 4, 15, 4], [15, 4, 15, 6], [15, 6, 14, 6], [19, 3, 19, 5],
  [19, 6, 17, 6], [4, 7, 4, 8], [7, 8, 7, 12], [8, 8, 8, 9], [8, 9, 10, 9],
  [7, 8, 5, 8], [4, 8, 2, 8], [2, 8, 2, 13], [4, 13, 7, 13], [7, 12, 7, 13],
  [4, 13, 4, 15], [4, 15, 7, 15], [3, 13, 3, 16], [11, 6, 12, 6],
  [16, 5, 16, 6], [16, 4, 16, 5], [16, 7, 16, 6], [16, 6, 16, 12],
  [16, 12, 20, 12], [20, 3, 20, 6], [20, 7, 20, 10], [20, 10, 23, 10],
  [23, 10, 23, 3], [23, 3, 20, 3], [20, 12, 26, 12], [23, 10, 28, 10],
  [28, 10, 28, 12], [28, 12, 27, 12], [27, 12, 27, 13], [26, 12, 26, 13],
  [3, 16, 2, 16], [2, 16, 2, 19], [7, 19, 7, 16], [7, 16, 4, 16],
  [19, 13, 16, 13], [16, 13, 16, 17], [16, 17, 19, 17], [19, 17, 19, 15],
  [19, 15, 20, 15], [19, 13, 19, 14], [19, 14, 20, 14], [14, 16, 16, 16],
  [13, 17, 15, 17], [15, 17, 15, 19], [15, 19, 20, 19], [16, 17, 16, 18],
  [16, 18, 20, 18], [20, 15, 20, 18], [20, 19, 23, 19], [23, 19, 23, 18],
  [23, 18, 25, 18], [25, 18, 25, 19], [25, 19, 28, 19], [28, 19, 28, 16],
  [28, 14, 28, 13], [28, 14, 28, 15], [28, 13, 27, 13], [26, 13, 25, 13],
  [25, 13, 25, 14], [25, 14, 23, 14], [23, 14, 23, 13], [23, 13, 20, 13],
  [20, 13, 20, 14], [6, 7, 9, 7], [9, 7, 9, 8], [19, 6, 20, 6],
  [20, 18, 20, 19], [19, 5, 19, 6], [17, 5, 17, 6], [7, 15, 8, 15],
  [2, 13, 3, 13], [15, 19, 16, 19], [8, 15, 8, 12], [8, 12, 9, 12],
  [9, 12, 9, 11], [9, 11, 10, 11], [10, 11, 10, 9], [9, 8, 10, 8],
  [10, 8, 10, 7], [10, 7, 11, 7], [12, 6, 12, 7], [12, 7, 11, 7],
  [14, 6, 14, 7], [14, 7, 15, 7], [15, 7, 15, 10], [15, 10, 14, 11],
  [14, 11, 13, 11], [13, 11, 13, 13], [13, 13, 14, 14], [14, 14, 14, 16],
  [13, 17, 13, 18], [13, 18, 12, 18], [12, 18, 12, 17], [12, 17, 11, 17],
  [11, 17, 11, 19], [11, 19, 11, 20], [10, 20, 10, 17], [10, 17, 9, 17],
  [9, 17, 8, 16], [8, 16, 7, 16], [22, 3, 23, 3], [2, 3, 19, 3]
];

function main() {
  const sourceImagePath = process.argv[2];
  if (!sourceImagePath) {
    console.error("Usage: node scripts/import-redbrand-hideout.js <path-to-source-image>");
    console.error('Point this at your own legally-owned copy of Lost Mine of Phandelver\'s');
    console.error('"Redbrand Hideout" DM-version map image.');
    process.exit(1);
  }
  if (!fs.existsSync(sourceImagePath)) {
    console.error(`Source image not found: ${sourceImagePath}`);
    process.exit(1);
  }

  const CampaignOS = loadEngineInto({}, [path.join(__dirname, "..", "engine", "encounter.js")]).CampaignOS;

  fs.mkdirSync(MAPS_DIR, { recursive: true });
  fs.copyFileSync(sourceImagePath, DEST_IMAGE_PATH);
  console.log(`Copied map image to ${DEST_IMAGE_PATH} (gitignored, not tracked).`);

  let state = loadState(STATE_FILE);
  // `image` itself is a 2D-app-only IndexedDB key (see MapImagePath.gd's own doc
  // comment) -- Godot resolves the real file purely from the map name, so this is
  // just a human-readable marker, not something anything actually reads.
  state = CampaignOS.setMapImage(state, MAP_NAME, null, {
    sourcePath: "real-adventure-map-import",
    attribution: "Lost Mine of Phandelver, Wizards of the Coast -- art by Mike Schley"
  });
  state = CampaignOS.setMapGrid(state, MAP_NAME, COLUMNS, ROWS);
  // addWall() only ever appends -- clear first so re-running this script (e.g.
  // after fixing a coordinate) replaces the wall list instead of duplicating
  // stale segments alongside the corrected ones.
  state = CampaignOS.clearWalls(state, MAP_NAME);
  for (const [x1, y1, x2, y2] of WALLS) {
    state = CampaignOS.addWall(state, MAP_NAME, x1, y1, x2, y2);
  }

  saveState(STATE_FILE, state);
  console.log(`Added "${MAP_NAME}" to ${STATE_FILE}: ${COLUMNS}x${ROWS} grid, ${WALLS.length} wall segments (all 12 rooms).`);
  console.log(`Switch to it with a "switch_map" action (or via the DM Assistant) to see it rendered.`);
}

main();
