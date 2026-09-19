"use strict";

const fs = require("node:fs");
const path = require("node:path");
const http = require("node:http");

const { loadEngineInto } = require("./lib/loadEngine");

// Load order matters: dmBridge.js reads window.CampaignOS at call time (not at load
// time), but encounter.js must still run first so that object exists before anything
// invokes it -- same order Campaign-OS's own tests/dmBridge.test.js uses.
// characterCreator.js has no such cross-dependency (its own SKILL_LIST/ABILITY_KEYS/
// HIT_DIE_BY_CLASS are self-contained duplicates, same "no shared-module mechanism
// across these plain scripts" convention this project already documents elsewhere),
// so its own position in this list doesn't matter -- appended last.
const engineWindow = loadEngineInto({}, [
  path.join(__dirname, "engine", "encounter.js"),
  path.join(__dirname, "engine", "dmBridge.js"),
  path.join(__dirname, "engine", "characterCreator.js")
]);
const CampaignOS = engineWindow.CampaignOS;
const DMBridge = engineWindow.CampaignOSDMBridge;
const CharacterCreator = engineWindow.CampaignOSCharacterCreator;

const DEFAULT_STATE_FILE = path.join(__dirname, "state", "encounter.json");

// Phase 7: the Claude DM bridge. `dm-bridge/watch.js` here is a byte-for-byte copy of
// Campaign-OS's own dm-bridge/watch.js (same "copied verbatim, never hand-edited"
// convention as engine/encounter.js and engine/dmBridge.js) -- it already reads a
// request.json {id, command, context, state, createdAt}, spawns the local `claude` CLI
// with the exact SYSTEM_PROMPT/action vocabulary this project's own DMBridge.applyActions
// already implements, and writes a response.json {id, message, actions}. Nothing about
// that file needed to change for a 3D client: it has no idea whether the browser or this
// server wrote its request, or whether a Godot window or an HTML page will read its
// response. This server just plays the exact role ui/app.js's own sendDMBridgeCommand()/
// checkDMBridgeResponse() pair already plays for the 2D app -- write the request in the
// same shape, poll for the matching response, apply the returned actions -- so it can't
// drift from what dm-bridge/watch.js actually expects.
const DEFAULT_DM_BRIDGE_DIR = path.join(__dirname, "..", "dm-bridge");
const DM_BRIDGE_TIMEOUT_MS = 120000; // matches ui/app.js's own 2-minute give-up
const DM_BRIDGE_POLL_MS = 1000;

// Seven requested features (ROADMAP.md, 2026-09-19), item 1 -- Create Character.
// dm-bridge/watch.js (copied verbatim, unmodified -- see above) already has a SEPARATE
// deterministic write-back mailbox for this, distinct from request.json/response.json:
// a create-character-request.json {id, fileName, markdown, createdAt} in, a
// create-character-response.json {id, ok, message, respondedAt} out, with its own
// independent poll loop in watch.js (pollCreateCharacter(), never touching
// request.json/response.json). No Claude call happens on this path at all -- the sheet
// is already fully computed (see CharacterCreator.computeCharacter/characterMarkdown
// above) before anything gets written -- so this is a much shorter timeout than the DM
// bridge's own 2-minute one, matching ui/app.js's own createCharacterResponseTimeoutMs
// exactly (a plain local file write should never genuinely take 20s; that ceiling is
// really "how long to wait for a slow-to-start dm-bridge/watch.js process," same as the
// 2D app's own reasoning).
const CREATE_CHARACTER_TIMEOUT_MS = 20000;

// The largest real client-sent body today is a /dm-command's optional
// {title, text} context -- itself capped at 6000 chars by the 2D app's own
// dmBridgeContextMaxChars (ui/app.js), not currently even wired up from the 3D
// client yet. 256 KB is generously above any real payload but small enough that
// a body-size attack against this loopback-only server can't turn into a
// meaningful memory-exhaustion problem. BODY_READ_TIMEOUT_MS guards only the
// "receiving the request body" phase -- unrelated to /dm-command's own up-to-2-
// minute wait for a Claude response, which only starts once the body has
// already fully arrived and been parsed.
const MAX_BODY_BYTES = 256 * 1024;
const BODY_READ_TIMEOUT_MS = 10000;

// Schema version history for the persisted encounter.json format itself (NOT the
// shared engine's own in-memory state shape, which mergeNewSeedMaps below already
// handles separately via "merge in any newly-added seed map by name"). Bump
// SCHEMA_VERSION and append a migration whenever a future change actually restructures
// what's on disk (renaming/removing a top-level field, changing a value's shape) --
// something no persisted file has needed yet, so there is exactly one, no-op entry:
//
//   0 (unversioned) -- every save this project has ever produced before this existed.
//   1 (current)      -- adds the schemaVersion field itself; no data changed shape.
//
// Each MIGRATIONS[i] upgrades a state from version i to i+1; migrateState() applies
// every needed step in order and stamps the result. A file claiming a NEWER version
// than this server knows about is a real problem (this server genuinely can't
// correctly interpret it) -- migrateState() throws rather than guess, the same
// "surface it, don't silently paper over it" rule loadState()'s own corruption
// handling already follows, and reuses that exact recovery path (try the backup,
// then refuse to start) since the thrown error propagates out of the same try block.
const SCHEMA_VERSION = 1;
const MIGRATIONS = [
  (state) => state // 0 -> 1: pure stamp, no prior on-disk shape to transform.
];

function migrateState(state) {
  let version = typeof state.schemaVersion === "number" ? state.schemaVersion : 0;
  if (version > SCHEMA_VERSION) {
    throw new Error(
      `State file is schemaVersion ${version}, newer than this server understands (${SCHEMA_VERSION}). Refusing to reinterpret it -- run a newer server, or restore an older save.`
    );
  }
  while (version < SCHEMA_VERSION) {
    const migrate = MIGRATIONS[version];
    if (!migrate) {
      throw new Error(`No migration registered from schemaVersion ${version} to ${version + 1}.`);
    }
    state = migrate(state);
    version += 1;
  }
  return { ...state, schemaVersion: SCHEMA_VERSION };
}

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

  // Phase 8: a second, real hand-built map -- an entrance/corridor/room dungeon built
  // from the Higgsfield "3D Jutsu" catalog (see godot/tools/build_entrance_hall.gd and
  // ROADMAP.md's Phase 8 entry). Registered here via setMapImage/setMapGrid WITHOUT
  // calling setActiveMap -- "Prototype Chamber" stays the default active map, this one
  // just becomes available to switch_map to (via the DM Assistant or a direct action),
  // matching the exact "available maps a DM can switch between" model this engine
  // already supports. No tokens start on it; switching maps never moves a token off
  // its own mapName, so it's simply empty until a DM populates it.
  const entranceHallMap = "Entrance Hall";
  state = CampaignOS.setMapImage(state, entranceHallMap, null, { sourcePath: "3d-generated" });
  state = CampaignOS.setMapGrid(state, entranceHallMap, 4, 8);

  // Wall segments in vertex space (see addWall's own doc comment) tracing the ACTUAL
  // solid geometry build_entrance_hall.gd placed -- not a simple rectangle, since the
  // entrance/corridor (1 module/2 cells wide) is narrower than the room behind it (2
  // modules/4 cells wide). The south end (y=0, the entrance itself) is deliberately
  // left open -- that's the dungeon's entrance from "outside," not a wall -- and the
  // door-aligned segment of the room's south wall (vertex x 0..2) is left open too,
  // the one actual connection between the corridor and the room.
  state = CampaignOS.addWall(state, entranceHallMap, 0, 0, 0, 4); // west side of the entrance/corridor tunnel
  state = CampaignOS.addWall(state, entranceHallMap, 2, 0, 2, 4); // east side of the tunnel (nothing connects sideways there)
  state = CampaignOS.addWall(state, entranceHallMap, 2, 4, 4, 4); // room's south wall, solid half (east of the doorway)
  state = CampaignOS.addWall(state, entranceHallMap, 0, 8, 4, 8); // room's north (far) wall
  state = CampaignOS.addWall(state, entranceHallMap, 0, 4, 0, 8); // room's west wall
  state = CampaignOS.addWall(state, entranceHallMap, 4, 4, 4, 8); // room's east wall

  return { ...state, schemaVersion: SCHEMA_VERSION };
}

// A saved session's stateFile is a full snapshot from whatever seedState()
// looked like the last time this file was written -- adding a brand new map
// to seedState() (e.g. Phase 4's "Entrance Hall") does nothing for anyone
// already mid-session with a persisted encounter.json on disk, since this
// function's normal path never re-runs seedState() once a file exists. Bit
// this project's own DM bridge integration test caught live: switch_map
// correctly refused to invent a map that "doesn't exist" from its own
// snapshot's availableMaps, and a plain server restart didn't help because
// it just reloaded the same stale file. Fix: merge in any map present in
// the CURRENT seedState() but missing from the loaded file, by name, leaving
// every already-persisted map/token/turn/log untouched -- a brand new map
// is a pure addition, never a field-level change to an existing one, so
// there's nothing to reconcile beyond "is this name already there."
function mergeNewSeedMaps(state) {
  const seeded = seedState();
  const missingMapNames = Object.keys(seeded.maps || {}).filter((name) => !(state.maps || {})[name]);
  if (!missingMapNames.length) return state;
  const mergedMaps = { ...state.maps };
  missingMapNames.forEach((name) => {
    mergedMaps[name] = seeded.maps[name];
  });
  return { ...state, maps: mergedMaps };
}

function backupFilePath(stateFile) {
  return `${stateFile}.bak`;
}

// Only a missing file (first run, or a fresh /reset-worthy setup) is "no state yet" --
// anything else (corrupt JSON, a permission error, a disk read failure) is real data
// that a silent reseed would have quietly thrown away. Falls back to the last-known-good
// backup saveState() keeps updated; only gives up (and throws, refusing to start with
// fabricated data standing in for a real save) once that backup is unusable too.
function loadState(stateFile) {
  try {
    const raw = fs.readFileSync(stateFile, "utf8");
    return mergeNewSeedMaps(migrateState(JSON.parse(raw)));
  } catch (err) {
    if (err.code === "ENOENT") {
      return seedState();
    }
    const backupFile = backupFilePath(stateFile);
    try {
      const raw = fs.readFileSync(backupFile, "utf8");
      const recovered = mergeNewSeedMaps(migrateState(JSON.parse(raw)));
      console.error(`Warning: ${stateFile} failed to load (${err.message}). Recovered from backup ${backupFile} instead.`);
      return recovered;
    } catch (backupErr) {
      throw new Error(
        `Refusing to start: ${stateFile} failed to load (${err.message}) and its backup ${backupFile} is also unavailable (${backupErr.message}). Fix or restore the state file manually -- it will not be silently reseeded.`
      );
    }
  }
}

// Writes go to a temp file and rename() into place -- rename is atomic on the same
// volume on both POSIX and NTFS, so a crash or power loss mid-write can never leave
// stateFile holding a partially-written JSON body. The previous good copy is preserved
// as stateFile.bak first (best-effort -- a failed backup copy shouldn't block saving
// the actual state) so loadState() has something to recover from if a later write's
// content is itself bad for some other reason.
function saveState(stateFile, state) {
  const dir = path.dirname(stateFile);
  fs.mkdirSync(dir, { recursive: true });

  if (fs.existsSync(stateFile)) {
    try {
      fs.copyFileSync(stateFile, backupFilePath(stateFile));
    } catch (err) {
      console.error(`Warning: failed to update backup ${backupFilePath(stateFile)}: ${err.message}`);
    }
  }

  const tmpFile = path.join(dir, `.${path.basename(stateFile)}.${process.pid}.tmp`);
  fs.writeFileSync(tmpFile, JSON.stringify(state, null, 2));
  fs.renameSync(tmpFile, stateFile);
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
//
// Phase 6 added `visibleTokenIds` -- the exact same two-filter rule
// ui/playerView.js's own renderMapGrid() applies before ever rendering a token
// (`!hiddenFromPlayers` AND `isVisibleToParty`), just read directly off the real
// dmBridge.js-adjacent engine functions here instead of re-deriving the rule
// client-side in GDScript, where a subtly different reimplementation could drift
// from what the 2D app actually does.
function computeVisibility(state) {
  const mapName = state.mapName;
  if (!mapName) return { mapName: null, currentlyVisible: [], revealed: [], visibleTokenIds: [] };
  const currentlyVisible = CampaignOS.visibleCellsForParty(state, mapName);
  const revealedTiles = state.maps?.[mapName]?.revealedTiles || {};
  const revealed = Object.keys(revealedTiles).map((key) => key.split(",").map(Number));
  const visibleTokenIds = (state.tokens || [])
    .filter((token) => token.mapName === mapName && !token.hiddenFromPlayers)
    .filter((token) => CampaignOS.isVisibleToParty(state, token))
    .map((token) => token.id);
  return { mapName, currentlyVisible, revealed, visibleTokenIds };
}

// Mirrors ui/app.js's own buildBridgeStateSnapshot() field-for-field -- the shape
// dm-bridge/watch.js's buildPrompt() reads (see its own comment on where each field
// gets used: grid/wallCount/round/activeToken/lairActionUsedThisRound/availableMaps at
// the top, then a big per-token line built from everything else). Read directly off
// this project's own copy of the same engine functions (currentGrid, effectiveSpeed,
// tokensOnCurrentMap) rather than re-derived by hand, so this can't drift from what the
// 2D app actually sends for the exact same fields.
function buildBridgeStateSnapshot(state) {
  const tokens = CampaignOS.tokensOnCurrentMap(state);
  const activeTokenId = state.turn?.tokenId;
  const availableMaps = Object.keys(state.maps || {}).filter((name) => name !== state.mapName);
  return {
    mapName: state.mapName,
    grid: CampaignOS.currentGrid(state),
    wallCount: (state.maps?.[state.mapName]?.walls || []).length,
    round: state.turn?.round || 0,
    activeToken: tokens.find((token) => token.id === activeTokenId)?.name || null,
    lairActionUsedThisRound: state.lairActionRound === (state.turn?.round || 0),
    availableMaps,
    tokens: tokens.map((token) => ({
      name: token.name,
      type: token.type,
      x: token.x,
      y: token.y,
      hp: token.hp,
      maxHp: token.maxHp,
      ac: token.ac,
      speed: CampaignOS.effectiveSpeed(token),
      movementLeft: Math.max(0, CampaignOS.effectiveSpeed(token) - (token.movementUsed || 0)),
      conditions: token.conditions,
      abilityScores: token.abilityScores,
      spellcasting: token.spellcasting,
      spellSlots: token.spellSlots,
      resources: token.resources,
      hitDice: token.hitDice,
      damageResistances: token.damageResistances,
      damageVulnerabilities: token.damageVulnerabilities,
      damageImmunities: token.damageImmunities,
      concentratingOn: token.concentratingOn,
      dying: token.dying,
      dead: token.dead,
      exhaustion: token.exhaustion,
      legendaryActions: token.legendaryActions,
      regeneration: token.regeneration,
      rechargeAbilities: token.rechargeAbilities,
      extraAttacks: token.extraAttacks,
      visionRange: token.visionRange,
      actionUsed: Boolean(token.actionUsed),
      bonusActionUsed: Boolean(token.bonusActionUsed),
      hiddenFromPlayers: Boolean(token.hiddenFromPlayers)
    }))
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Polls responsePath the same 1s-ish cadence ui/app.js's own checkDMBridgeResponse()
// uses, until a response with a matching `id` shows up or timeoutMs runs out. A
// mid-write partial JSON read (dm-bridge/watch.js writing the file at the exact moment
// this reads it) is treated the same as "not there yet" and retried next tick, not a
// hard failure -- matching ui/app.js's own "partial write mid-poll -- try again" handling.
async function waitForBridgeResponse(responsePath, id, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const raw = fs.readFileSync(responsePath, "utf8");
      const parsed = JSON.parse(raw);
      if (parsed && parsed.id === id) return parsed;
    } catch (err) {
      // ENOENT (watch.js hasn't written yet) or a mid-write partial JSON parse
      // failure -- both just mean "keep waiting," not an error to surface.
    }
    await sleep(DM_BRIDGE_POLL_MS);
  }
  return null;
}

// Godot's HTTPRequest isn't a browser and doesn't enforce/send CORS at all, so none
// of this affects the actual game client either way -- it's here for the browser-
// based callers this API also supports (a plain browser tab / curl / a future
// web-based front end). A bare "*" would let ANY website a user happens to have
// open in the same browser fire a blind cross-origin POST /action against this
// loopback server while it's running -- CORS is what stops the browser from doing
// that for a JSON-content-typed fetch() (it preflights, and the browser only sends
// the real request if that preflight is allowed). Allow-listing 127.0.0.1/localhost
// specifically (any port -- a local dev front end can run on anything) keeps every
// legitimate local origin working while closing that off to the wider web.
function isAllowedLocalOrigin(origin) {
  if (!origin) return false;
  let url;
  try {
    url = new URL(origin);
  } catch (err) {
    return false;
  }
  return (url.protocol === "http:" || url.protocol === "https:") &&
    (url.hostname === "127.0.0.1" || url.hostname === "localhost");
}

function applyCorsHeaders(req, res) {
  const origin = req.headers.origin;
  if (!isAllowedLocalOrigin(origin)) return;
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
}

function sendJson(res, status, body) {
  const json = JSON.stringify(body);
  // A plain writeHead(status, headers) call here MERGES with anything already set
  // via res.setHeader() (applyCorsHeaders, called once up front for every request) --
  // it doesn't need to (and shouldn't) repeat the CORS headers itself.
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(json)
  });
  res.end(json);
}

class BodyError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    let bytes = 0;
    let oversized = false;
    let settled = false;

    const finish = (isResolve, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (isResolve) resolve(value);
      else reject(value);
    };

    // Only the timeout destroys the socket -- the client is stalled/misbehaving, so
    // there's no well-formed response to send it anyway, and dropping the connection
    // frees the server from waiting on it further.
    const timer = setTimeout(() => {
      req.destroy();
      finish(false, new BodyError(408, "Request body took too long to arrive."));
    }, BODY_READ_TIMEOUT_MS);

    req.on("data", (chunk) => {
      bytes += chunk.length;
      if (bytes > MAX_BODY_BYTES) {
        // Stop buffering (this is what actually bounds memory use -- `data` never
        // grows past the limit) but deliberately DON'T destroy the socket here: an
        // abrupt close mid-upload is what a client sees as a raw connection reset,
        // not a clean HTTP error. Draining the rest of the (now-discarded) body and
        // responding normally on 'end' is what lets sendJson's 413 actually reach
        // the caller as a real response instead of a socket error.
        oversized = true;
        return;
      }
      data += chunk;
    });
    req.on("end", () => {
      if (oversized) {
        return finish(false, new BodyError(413, `Request body exceeds the ${MAX_BODY_BYTES}-byte limit.`));
      }
      if (!data) return finish(true, {});
      try {
        finish(true, JSON.parse(data));
      } catch (err) {
        finish(false, new BodyError(400, "Malformed JSON body."));
      }
    });
    req.on("error", (err) => finish(false, err));
  });
}

// Factory rather than a module-level side effect, so tests (and any future second
// consumer) can spin up an isolated server against a throwaway state file/port
// instead of sharing the one real prototype save file and a fixed port.
function createServer({ stateFile = DEFAULT_STATE_FILE, bridgeDir = DEFAULT_DM_BRIDGE_DIR } = {}) {
  let state = loadState(stateFile);
  const bridgeRequestPath = path.join(bridgeDir, "request.json");
  const bridgeResponsePath = path.join(bridgeDir, "response.json");
  // A separate mailbox pair from request.json/response.json above -- dm-bridge/watch.js
  // polls this one independently (pollCreateCharacter(), never touching the DM-command
  // pair), so a /create-character call and a /dm-command call in flight at the same time
  // can't clobber each other's files.
  const createCharacterRequestPath = path.join(bridgeDir, "create-character-request.json");
  const createCharacterResponsePath = path.join(bridgeDir, "create-character-response.json");

  // request.json/response.json are a single shared mailbox -- fixed filenames
  // dm-bridge/watch.js (verbatim-copied from the 2D app, never hand-edited) reads and
  // writes. A second /dm-command arriving while one is still in flight would overwrite
  // the first's request.json before watch.js ever reads it, or have its own response
  // raced by the first's. This lock serializes the whole write-request -> await-response
  // -> apply-and-save cycle so only one command is ever in flight against those shared
  // files at a time; later callers wait their turn instead of racing. `.then(fn, fn)`
  // (not just `.then(fn)`) is what makes the lock advance even after a prior command
  // errored or timed out -- otherwise one bad command would wedge every command queued
  // behind it forever.
  let dmBridgeLock = Promise.resolve();
  let dmBridgeQueueDepth = 0;
  const DM_BRIDGE_MAX_QUEUE_DEPTH = 5;
  function withDmBridgeLock(fn) {
    const result = dmBridgeLock.then(fn, fn);
    dmBridgeLock = result.then(() => {}, () => {});
    return result;
  }

  // Same "serialize the whole cycle" reasoning as withDmBridgeLock above, for
  // create-character-request.json/create-character-response.json's own mailbox pair --
  // but no queue-depth cap/429 rejection: unlike a Claude call, this path is a
  // deterministic file write expected to resolve in well under CREATE_CHARACTER_TIMEOUT_MS,
  // so a real pileup here would mean something is actually broken (watch.js not running,
  // a stuck filesystem), not ordinary load a DM would ever generate.
  let createCharacterLock = Promise.resolve();
  function withCreateCharacterLock(fn) {
    const result = createCharacterLock.then(fn, fn);
    createCharacterLock = result.then(() => {}, () => {});
    return result;
  }

  const server = http.createServer(async (req, res) => {
    applyCorsHeaders(req, res);

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
        return sendJson(res, err.status || 400, { error: err.message || "Malformed JSON body." });
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

    // Phase 7: one round trip for the whole "ask Claude what should happen" loop --
    // Godot (or curl, or a browser) POSTs {command, context}, and this handler does
    // everything ui/app.js's sendDMBridgeCommand()/checkDMBridgeResponse() pair does
    // across two separate polling loops, in one blocking-from-the-CALLER's-perspective
    // call: write request.json, wait for dm-bridge/watch.js to answer, apply the
    // returned actions through the exact same DMBridge.applyActions this project's
    // /action endpoint already uses, and hand back the updated state. This does NOT
    // block the server's event loop while waiting -- other requests (GET /state, a
    // Godot poll tick) are served normally in the meantime, same as Node's http server
    // always behaves under an async handler.
    if (req.method === "POST" && req.url === "/dm-command") {
      let body;
      try {
        body = await readJsonBody(req);
      } catch (err) {
        return sendJson(res, err.status || 400, { error: err.message || "Malformed JSON body." });
      }
      const command = typeof body.command === "string" ? body.command.trim() : "";
      if (!command) {
        return sendJson(res, 400, { error: "\"command\" must be a non-empty string." });
      }

      if (dmBridgeQueueDepth >= DM_BRIDGE_MAX_QUEUE_DEPTH) {
        return sendJson(res, 429, {
          error: `DM bridge is busy -- ${dmBridgeQueueDepth} commands already queued ahead of this one. Try again shortly.`
        });
      }
      const queuedAhead = dmBridgeQueueDepth; // 0 == runs immediately, no one ahead
      dmBridgeQueueDepth++;

      let outcome;
      try {
        outcome = await withDmBridgeLock(async () => {
          const id = `req-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
          const request = {
            id,
            command,
            // Campaign lore injection (ui/app.js's dmBridgeContext) isn't wired up on the
            // 3D side yet -- no campaign-context UI exists in Godot to source it from.
            // watch.js's buildPrompt() already treats a null context as "none provided",
            // so this is a real, working default, not a stub standing in for missing work.
            context: (body.context && typeof body.context.text === "string") ? body.context : null,
            state: buildBridgeStateSnapshot(state),
            createdAt: new Date().toISOString()
          };

          try {
            fs.mkdirSync(bridgeDir, { recursive: true });
            fs.writeFileSync(bridgeRequestPath, JSON.stringify(request, null, 2));
          } catch (err) {
            return { status: 500, body: { error: `Could not write to the DM bridge folder: ${err.message}` } };
          }

          const response = await waitForBridgeResponse(bridgeResponsePath, id, DM_BRIDGE_TIMEOUT_MS);
          if (!response) {
            return {
              status: 504,
              body: { error: `No response after ${Math.round(DM_BRIDGE_TIMEOUT_MS / 1000)}s -- make sure "node dm-bridge/watch.js" is running, then try again.` }
            };
          }

          const result = DMBridge.applyActions(state, Array.isArray(response.actions) ? response.actions : []);
          state = result.state;
          if (state.mapName) state = CampaignOS.revealVisibleTiles(state, state.mapName);
          saveState(stateFile, state);
          return {
            status: 200,
            body: {
              state,
              message: typeof response.message === "string" ? response.message : "",
              actionMessages: result.messages,
              visibility: computeVisibility(state),
              queuedAhead
            }
          };
        });
      } finally {
        dmBridgeQueueDepth--;
      }
      return sendJson(res, outcome.status, outcome.body);
    }

    // Seven requested features (ROADMAP.md, 2026-09-19), item 1 -- Create Character.
    // Deterministic, not an LLM call: CharacterCreator.computeCharacter()/
    // characterMarkdown() (already loaded verbatim above, same as CampaignOS/DMBridge)
    // fully compute the sheet right here, synchronously, before anything is written --
    // there's nothing left to draft. Mirrors ui/app.js's own createCharacterForm submit
    // handler exactly (validate -> compute -> write create-character-request.json ->
    // wait for dm-bridge/watch.js's create-character-response.json), just server-side
    // instead of in-browser, so the Godot client doesn't need its own GDScript port of
    // ~300 lines of character math (a real duplication/drift risk) the way AoeTemplate.gd
    // reasonably ported the much smaller AoE shape functions -- this is "a rule," in
    // ARCHITECTURE.md's own terms, and belongs in the shared engine layer.
    if (req.method === "POST" && req.url === "/create-character") {
      let draft;
      try {
        draft = await readJsonBody(req);
      } catch (err) {
        return sendJson(res, err.status || 400, { error: err.message || "Malformed JSON body." });
      }
      const errors = CharacterCreator.validateDraft(draft || {});
      if (errors.length) {
        return sendJson(res, 400, { errors });
      }

      const character = CharacterCreator.computeCharacter(draft);
      const markdown = CharacterCreator.characterMarkdown(character);
      const fileName = CharacterCreator.fileNameForCharacter(character.name);

      const outcome = await withCreateCharacterLock(async () => {
        const id = `char-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        try {
          fs.mkdirSync(bridgeDir, { recursive: true });
          fs.writeFileSync(
            createCharacterRequestPath,
            JSON.stringify({ id, fileName, markdown, createdAt: new Date().toISOString() }, null, 2)
          );
        } catch (err) {
          return { status: 500, body: { error: `Could not write to the DM bridge folder: ${err.message}` } };
        }

        const response = await waitForBridgeResponse(createCharacterResponsePath, id, CREATE_CHARACTER_TIMEOUT_MS);
        if (!response) {
          return {
            status: 504,
            body: { error: `No response after ${Math.round(CREATE_CHARACTER_TIMEOUT_MS / 1000)}s -- make sure "node dm-bridge/watch.js" is running, then try again.` }
          };
        }
        // response.ok can legitimately be false (DND_REPO_PATH not set, a filename
        // collision, a write error -- see dm-bridge/watch.js's own
        // handleCreateCharacterRequest) without this being an HTTP-layer failure: the
        // request was received and answered correctly, same "a miss isn't a 500" precedent
        // POST /action's own attack/save results already establish. The caller checks
        // body.ok, same as ui/app.js's own response.ok branch does.
        return { status: 200, body: { ok: response.ok, message: response.message, fileName, character } };
      });
      return sendJson(res, outcome.status, outcome.body);
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
    console.log("GET /state | POST /action {type, ...} | POST /dm-command | POST /create-character | POST /reset");
  });
}

module.exports = { createServer, seedState, loadState, saveState, migrateState, SCHEMA_VERSION };
