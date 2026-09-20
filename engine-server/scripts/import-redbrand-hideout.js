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
// Scope: this v1 slice only wall-annotates two of the source map's twelve rooms
// (11 and 12, in Lost Mine of Phandelver's "Redbrand Hideout") -- enough to prove
// the pipeline handles real image calibration + real wall geometry + real rendered
// line-of-sight, without needing to trace an entire hand-painted dungeon's every
// wall by eye first. The rest of the map's rooms are simply left unannotated,
// same "accepted, documented gap" precedent Prototype Chamber's own L-shaped void
// already established -- hasLineOfSight's own documented behavior for a map with
// no walls drawn in a given area is "no restriction," not an error.
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
// IMPORTANT, found the hard way (see ROADMAP.md): GridManager's raster floor
// stretches the ENTIRE source image across the ENTIRE COLUMNS x ROWS grid --
// vertex (0,0) is the image's literal top-left pixel (parchment border and
// all), not wherever a particular room happens to start. COLUMNS/ROWS must
// therefore cover the WHOLE image at the map's real grid pitch, and every
// wall coordinate must be measured from that same pixel-(0,0) origin -- not
// from a room's own floor corner, which is what an earlier version of this
// script got wrong (walls landed in the border above the title text instead
// of on Rooms 11/12).
//
// A SECOND, subtler lesson from the same debugging session: an initial
// pitch estimate of ~80px/square came from eyeballing a single 4-square span
// inside Room 11 -- close, but a small per-square error like that compounds
// across the WHOLE image width once used to derive a total column count (a
// 2.5% pitch error x 31 columns is nearly a full square of drift at the far
// edge, visible as the engine's grid overlay not matching the map's own
// printed grid). Re-measured with a long-baseline column/row-average
// brightness autocorrelation (averaging over ~1500 rows/columns cancels
// per-tile furniture/texture noise, leaving the periodic grid-line signal;
// checking the peak at several large multiples of the period, not just one,
// pins the true pitch down far more precisely than any single local
// measurement): true pitch is ~82.3px/square, not 80 -- Room 11/12's own
// RELATIVE square counts (measured locally, and far more reliable as a
// simple integer count) didn't need to change, only COLUMNS/ROWS.
const COLUMNS = 30;
const ROWS = 21;
const FEET_PER_SQUARE = 5;

// Vertex-space wall segments (integer corners 0..COLUMNS / 0..ROWS, same
// convention encounter.js's own addWall() documents and Prototype Chamber/
// Entrance Hall's seedState() calls already use) for Rooms 11 and 12 only,
// with door gaps left as separate segments. Room 11 occupies vertex (2,3) to
// (6,7); Room 12 occupies (6,3) to (10,6) -- both measured from the full
// image's own pixel (0,0), per the note above.
const WALLS = [
  // Rooms 11+12's shared north wall (one continuous run, no gap)
  [2, 3, 10, 3],
  // Room 11's west wall
  [2, 3, 2, 7],
  // Room 11's south wall, split around its door
  [2, 7, 4, 7],
  [5, 7, 6, 7],
  // Shared wall between Room 11 and Room 12, split around its door
  [6, 3, 6, 4],
  [6, 5, 6, 7],
  // Room 12's east wall (closing off toward Room 7, out of this slice's scope)
  [10, 3, 10, 6],
  // Room 12's south wall (shallower than Room 11's -- see ROADMAP.md notes)
  [6, 6, 10, 6]
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
  console.log(`Added "${MAP_NAME}" to ${STATE_FILE}: ${COLUMNS}x${ROWS} grid, ${WALLS.length} wall segments (Rooms 11-12 only).`);
  console.log(`Switch to it with a "switch_map" action (or via the DM Assistant) to see it rendered.`);
}

main();
