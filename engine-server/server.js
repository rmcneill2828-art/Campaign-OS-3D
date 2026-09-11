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

  // addToken() returns {state, token}, not a bare state -- unlike setMapImage/setMapGrid/
  // setActiveMap above, which do return bare states.
  state = CampaignOS.addToken(state, { name: "Darkhawk", type: "hero", hp: 91, maxHp: 91, ac: 18 }).state;
  state = CampaignOS.addToken(state, { name: "Wren", type: "hero", hp: 54, maxHp: 54, ac: 15 }).state;

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
      return sendJson(res, 200, { state });
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
      saveState(stateFile, state);
      return sendJson(res, 200, { state, messages: result.messages });
    }

    if (req.method === "POST" && req.url === "/reset") {
      state = seedState();
      saveState(stateFile, state);
      return sendJson(res, 200, { state });
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
