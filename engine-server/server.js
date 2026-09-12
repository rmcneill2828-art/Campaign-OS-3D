"use strict";

const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");

const { loadEngineInto } = require("./lib/loadEngine");

// Load order matters: dmBridge.js reads window.CampaignOS at call time (not at load
// time), but encounter.js must still run first so that object exists before anything
// invokes it -- same order Campaign-OS's own tests/dmBridge.test.js uses.
const engineWindow = loadEngineInto({}, [
  path.join(__dirname, "engine", "encounter.js"),
  path.join(__dirname, "engine", "dmBridge.js")
]);
const CampaignOS = engineWindow.CampaignOS;
const DMBridge = engineWindow.CampaignOSDMBridge;

const DEFAULT_STATE_FILE = path.join(__dirname, "state", "encounter.json");

// A fresh board to play with on first run (or after /reset). This is a convenience
// starting point for the 3D prototype, not campaign data -- real campaign import
// (engine/campaign.js, already copied alongside encounter.js/dmBridge.js) is a later
// phase, see ../ROADMAP.md.
function seedState() {
  let state = CampaignOS.createState();
  const mapName = "Prototype Chamber";

  // setActiveMap() refuses to switch to a map with no "real map data" (an uploaded
  // image, in the 2D app's world) -- see hasRealMapData() in encounter.js. The 3D
  // client renders its own floor/wall geometry from columns/rows instead of an
  // image, so a non-empty sourcePath marker is enough to satisfy that check; nothing
  // ever reads this string as an actual file path here.
  state = CampaignOS.setMapImage(state, mapName, null, { sourcePath: "3d-generated" });
  state = CampaignOS.setMapGrid(state, mapName, 12, 8);
  state = CampaignOS.setActiveMap(state, mapName);

  // Phase 5: real wall segments for hasLineOfSight/cellVisibleToHero/etc. (see
  // engine/encounter.js) to actually mean something on this map, instead of the
  // "no walls drawn" fast path that leaves every cell unconditionally visible.
  // These 5 segments trace the SAME room shape godot/tools/build_prototype_chamber.gd
  // built in 3D -- a solid perimeter around the full 12x8 playable area (vertex
  // coordinates 0..12 / 0..8, the corners between cells, matching addWall's own
  // documented convention -- NOT the 1..columns cell-index space tokens use) with a
  // gap in the south wall (vertex x 6..7, y 8) exactly where that scene's own
  // DOOR_COLUMN=7 opening sits. If that map scene's layout ever changes, these must
  // change with it -- there's no single shared source for a hand-built room's shape
  // between the two projects, same duplicated-by-hand convention this codebase
  // already uses for ABILITY_KEYS/SKILL_LIST/etc. across engine.js/Main.gd.
  state = CampaignOS.addWall(state, mapName, 0, 0, 12, 0); // north
  state = CampaignOS.addWall(state, mapName, 0, 0, 0, 8); // west
  state = CampaignOS.addWall(state, mapName, 12, 0, 12, 8); // east
  state = CampaignOS.addWall(state, mapName, 0, 8, 6, 8); // south, west of the door
  state = CampaignOS.addWall(state, mapName, 7, 8, 12, 8); // south, east of the door

  // addToken() returns {state, token}, not a bare state -- unlike setMapImage/setMapGrid/
  // setActiveMap above, which do return bare states.
  //
  // Both heroes originally shipped with no abilityScores at all (Phase 0's seed only
  // set name/hp/ac) -- harmless for move/attack, but every saving throw/ability check/
  // spell attack bonus silently fell back to +0 (savingThrowBonus()/abilityCheckBonus()'s
  // own documented sparse-data fallback), which read as "bonuses aren't working" once
  // Phase 3's Roll Save/Check/Cast Spell UI actually put that in front of a real user --
  // confirmed live: goblins (spawned from a real SRD stat block) showed their true -1 STR,
  // Darkhawk/Wren showed a flat +0 no matter what. Not a UI bug -- fixed at the source by
  // giving these two prototype heroes real (if invented -- this is throwaway seed data,
  // not the actual campaign's real character sheets) ability scores, and giving Wren
  // basic spellcasting stats + slots so cast_spell's attack-roll path has something real
  // to exercise too instead of always hitting "no stated spell attack bonus, skipped."
  state = CampaignOS.addToken(state, {
    name: "Darkhawk", type: "hero", hp: 91, maxHp: 91, ac: 18,
    abilityScores: { STR: 20, DEX: 14, CON: 18, INT: 10, WIS: 12, CHA: 10 }
  }).state;
  state = CampaignOS.addToken(state, {
    name: "Wren", type: "hero", hp: 54, maxHp: 54, ac: 15,
    abilityScores: { STR: 8, DEX: 14, CON: 14, INT: 18, WIS: 12, CHA: 10 },
    spellcasting: { saveDC: 15, attackBonus: 7 },
    spellSlots: { 1: { max: 4, current: 4 }, 2: { max: 3, current: 3 }, 3: { max: 3, current: 3 } }
  }).state;

  // parseCommand is the supported entry point for spawning a real SRD stat block --
  // spawnMonster() itself isn't part of CampaignOS's public API (see dmBridge.js's own
  // spawn_monster case, which does exactly this).
  const spawned = CampaignOS.parseCommand(state, "spawn 2 goblin");
  state = spawned.state;

  return state;
}

function loadState(stateFile) {
  try {
    const raw = fs.readFileSync(stateFile, "utf8");
    return JSON.parse(raw);
  } catch (err) {
    return seedState();
  }
}

function saveState(stateFile, state) {
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
}

// Phase 5: computed (not persisted, except revealedTiles -- see below) line-of-sight
// data alongside every response, so a client can start consuming it without this
// project's DM client needing to render anything different itself yet (the current
// 3D client deliberately still shows everything unfiltered, matching the 2D app's
// own DM canvas, which never fogs itself either -- only its separate Player Window
// does. See ROADMAP.md's Phase 5 entry). `currentlyVisible` is fresh every call
// (party position can move between polls); `revealed` reads back the persisted
// per-map memory revealVisibleTiles (called after every mutating action below)
// keeps up to date, the same explored-tile bookkeeping the 2D app's own
// saveEncounter() hook performs on every save.
function computeVisibility(state) {
  const mapName = state.mapName;
  if (!mapName) return { mapName: null, currentlyVisible: [], revealed: [] };
  const currentlyVisible = CampaignOS.visibleCellsForParty(state, mapName);
  const revealedTiles = state.maps?.[mapName]?.revealedTiles || {};
  const revealed = Object.keys(revealedTiles).map((key) => key.split(",").map(Number));
  return { mapName, currentlyVisible, revealed };
}

function sendJson(res, status, body) {
  const json = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(json),
    // Permissive CORS: Godot's HTTPRequest isn't a browser and doesn't enforce CORS
    // anyway, but this keeps the door open for testing the API from a plain browser
    // tab / curl / a future web-based front end without revisiting this file.
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
  });
  res.end(json);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
    });
    req.on("end", () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (err) {
        reject(err);
      }
    });
    req.on("error", reject);
  });
}

// Factory rather than a module-level side effect, so tests (and any future second
// consumer) can spin up an isolated server against a throwaway state file/port
// instead of sharing the one real prototype save file and a fixed port.
function createServer({ stateFile = DEFAULT_STATE_FILE } = {}) {
  let state = loadState(stateFile);

  const server = http.createServer(async (req, res) => {
    if (req.method === "OPTIONS") {
      return sendJson(res, 204, {});
    }

    if (req.method === "GET" && req.url === "/state") {
      return sendJson(res, 200, { state, visibility: computeVisibility(state) });
    }

    // One action per call, same shape the 2D app's live-actions.json entries use
    // (see Campaign-OS's CLAUDE.md "Live-session control contract" section) --
    // {type, ...fields}, dispatched through the same engine/dmBridge.js this project
    // copied verbatim, so the action vocabulary (attack, move_token, cast_spell,
    // spawn_monster, ...) is identical and won't drift from the 2D app's own docs.
    if (req.method === "POST" && req.url === "/action") {
      let action;
      try {
        action = await readJsonBody(req);
      } catch (err) {
        return sendJson(res, 400, { error: "Malformed JSON body." });
      }
      if (!action || typeof action.type !== "string") {
        return sendJson(res, 400, { error: "Action must be an object with a string \"type\"." });
      }
      const result = DMBridge.applyActions(state, [action]);
      state = result.state;
      // Fold newly-visible cells into the active map's explored memory, same choke
      // point the 2D app's own saveEncounter() uses (every mutation flows through
      // here) -- a true no-op (same state reference back) for the common case of a
      // map with no walls at all, per revealVisibleTiles's own fast path.
      if (state.mapName) state = CampaignOS.revealVisibleTiles(state, state.mapName);
      saveState(stateFile, state);
      return sendJson(res, 200, { state, messages: result.messages, visibility: computeVisibility(state) });
    }

    if (req.method === "POST" && req.url === "/reset") {
      state = seedState();
      if (state.mapName) state = CampaignOS.revealVisibleTiles(state, state.mapName);
      saveState(stateFile, state);
      return sendJson(res, 200, { state, visibility: computeVisibility(state) });
    }

    sendJson(res, 404, { error: "Not found." });
  });

  return server;
}

if (require.main === module) {
  const port = Number(process.env.PORT || 8787);
  const server = createServer({});
  server.listen(port, "127.0.0.1", () => {
    console.log(`Campaign OS 3D engine-server listening on http://127.0.0.1:${port}`);
    console.log("GET /state | POST /action {type, ...} | POST /reset");
  });
}

module.exports = { createServer, seedState };
