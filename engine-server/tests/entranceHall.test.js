"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

function startTestServer() {
  const stateFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "campaign-os-3d-")), "encounter.json");
  const server = createServer({ stateFile });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      resolve({ server, baseUrl: `http://127.0.0.1:${port}` });
    });
  });
}

function stopTestServer(server) {
  return new Promise((resolve) => server.close(resolve));
}

test("Phase 8: a pre-existing saved session (no Entrance Hall yet) gets it merged in on load, live combat state untouched", async () => {
  // Simulates exactly the bug hit live: a real player's already-persisted
  // encounter.json, saved by an older server build before Entrance Hall
  // existed -- only Prototype Chamber in `maps`, tokens mid-combat.
  const stateFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "campaign-os-3d-")), "encounter.json");
  const { server: seedServer, baseUrl: seedBaseUrl } = await startTestServer();
  const { state: freshState } = await (await fetch(`${seedBaseUrl}/state`)).json();
  await stopTestServer(seedServer);

  const staleState = {
    ...freshState,
    maps: { "Prototype Chamber": freshState.maps["Prototype Chamber"] }, // Entrance Hall stripped out, as if it never existed
    log: ["Wren attacks Orc 1 for 13 damage. Orc 1 dies."] // stands in for real mid-combat progress
  };
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify(staleState, null, 2));

  const server = createServer({ stateFile });
  try {
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const { port } = server.address();
    const { state } = await (await fetch(`http://127.0.0.1:${port}/state`)).json();

    assert.ok(state.maps["Entrance Hall"], "Entrance Hall should get merged in even though the saved file predates it");
    assert.equal(state.mapName, "Prototype Chamber", "merging a new map must not change the active map");
    assert.deepEqual(state.log, staleState.log, "merging a new map must not touch existing log/combat state");
  } finally {
    await stopTestServer(server);
  }
});

async function postAction(baseUrl, action) {
  const res = await fetch(`${baseUrl}/action`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(action)
  });
  return res.json();
}

test("Phase 8: Entrance Hall is registered as a second map without becoming the active one", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const { state } = await (await fetch(`${baseUrl}/state`)).json();
    assert.equal(state.mapName, "Prototype Chamber"); // unchanged default
    assert.ok(state.maps["Entrance Hall"], "Entrance Hall should exist as a registered map");
    assert.equal(state.maps["Entrance Hall"].columns, 4);
    assert.equal(state.maps["Entrance Hall"].rows, 8);
    assert.equal(state.maps["Entrance Hall"].walls.length, 6);
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 8: switch_map actually moves the active map to Entrance Hall and back", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const switched = await postAction(baseUrl, { type: "switch_map", map: "Entrance Hall" });
    assert.equal(switched.state.mapName, "Entrance Hall");

    const back = await postAction(baseUrl, { type: "switch_map", map: "Prototype Chamber" });
    assert.equal(back.state.mapName, "Prototype Chamber");
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 8: Entrance Hall's walls correctly block LOS through solid sections and stay open through the doorway", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const { state } = await (await fetch(`${baseUrl}/state`)).json();

    // A straight line from inside the tunnel (cell 1,3, in the corridor) to a
    // point past the tunnel's east side wall (cell 3,3, in the walled-off
    // area beside it) must cross the vertex-space wall at x=2 -- blocked.
    assert.equal(los(state, 1, 3, 3, 3), false);

    // A straight line from the corridor's last cell (1,4) into the room
    // through the doorway (which sits at vertex x 0..2, y=4 -- the gap
    // between the two south-wall segments) into the room's near cell (1,5)
    // must NOT be blocked -- that's the one real connection in this map.
    assert.equal(los(state, 1, 4, 1, 5), true);

    // The same line shifted one column over (3,4) to (3,5) crosses the
    // room's SOLID south-wall segment (vertex x 2..4, y=4) instead -- blocked.
    assert.equal(los(state, 3, 4, 3, 5), false);
  } finally {
    await stopTestServer(server);
  }
});

// Loads the same engine copy the server itself uses, purely to call
// hasLineOfSight directly for this file's own LOS test.
const { loadEngineInto } = require("../lib/loadEngine");
const engineWindow = loadEngineInto({}, [
  path.join(__dirname, "..", "engine", "encounter.js")
]);
const CampaignOS = engineWindow.CampaignOS;

function los(state, ax, ay, bx, by) {
  return CampaignOS.hasLineOfSight(state, "Entrance Hall", ax, ay, bx, by);
}
