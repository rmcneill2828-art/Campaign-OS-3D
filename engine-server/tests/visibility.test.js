"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

// Same throwaway-server-per-test pattern as tests/server.test.js.
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

async function postAction(baseUrl, action) {
  const res = await fetch(`${baseUrl}/action`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(action)
  });
  return res.json();
}

test("Phase 5: Prototype Chamber's seeded walls trace the same room build_prototype_chamber.gd built", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const { state } = await (await fetch(`${baseUrl}/state`)).json();
    const walls = state.maps["Prototype Chamber"].walls;
    assert.equal(walls.length, 5);
    // Exact segments, not just a count -- a wrong wall (e.g. door in the wrong
    // place, or missing a side) should fail this test, not silently pass because
    // "some walls exist."
    assert.deepEqual(walls, [
      { x1: 0, y1: 0, x2: 12, y2: 0 },
      { x1: 0, y1: 0, x2: 0, y2: 8 },
      { x1: 12, y1: 0, x2: 12, y2: 8 },
      { x1: 0, y1: 8, x2: 6, y2: 8 },
      { x1: 7, y1: 8, x2: 12, y2: 8 }
    ]);
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 5: GET /state and POST /action both report visibility computed from the real walls", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const { visibility } = await (await fetch(`${baseUrl}/state`)).json();
    assert.equal(visibility.mapName, "Prototype Chamber");
    // Both heroes spawn near (4,4) via findOpenTile, well inside the walled room
    // with no vision range set (unlimited sight, walls only) -- every cell in the
    // open 12x8 interior should be currentlyVisible, none of it should require
    // walking through a wall to reach.
    assert.ok(visibility.currentlyVisible.length > 0);
    assert.ok(visibility.currentlyVisible.some(([x, y]) => x === 1 && y === 1));
    assert.ok(visibility.currentlyVisible.some(([x, y]) => x === 12 && y === 8));

    const moved = await postAction(baseUrl, { type: "move_token", target: "Darkhawk", x: 1, y: 1 });
    assert.ok(moved.visibility);
    assert.equal(moved.visibility.mapName, "Prototype Chamber");
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 5: revealed (explored) memory accumulates after actions, matching the 2D app's own saveEncounter() hook", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const before = await (await fetch(`${baseUrl}/state`)).json();
    assert.equal(before.visibility.revealed.length, 0); // nothing saved yet -- revealVisibleTiles only runs after a mutating action

    const after = await postAction(baseUrl, { type: "move_token", target: "Darkhawk", x: 1, y: 1 });
    assert.ok(after.visibility.revealed.length > 0);
    assert.ok(after.visibility.revealed.some(([x, y]) => x === 1 && y === 1));

    // Persisted across a fresh load, same durability guarantee every other piece
    // of state already has (see server.test.js's own move_token persistence test).
    const reloaded = await (await fetch(`${baseUrl}/state`)).json();
    assert.deepEqual(reloaded.visibility.revealed.sort(), after.visibility.revealed.sort());
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 5: hasLineOfSight is blocked through the seeded walls, open through the door gap", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const { state } = await (await fetch(`${baseUrl}/state`)).json();
    // hasLineOfSight(state, mapName, ax, ay, bx, by) takes CELL coordinates and
    // converts each to its own vertex-space cell-center point internally
    // (x-0.5, y-0.5) -- these test points are chosen so that conversion lands
    // exactly where intended relative to the seeded wall segments, not
    // reimplementing that math here.

    // Straight up through cell column 6 crosses the north wall (0,0)-(12,0) at
    // vertex x=5.5, well inside its [0,12] span -- must be blocked.
    assert.equal(los(state, 6, 1, 6, -1), false);

    // Straight down through cell column 3 crosses the south wall's WEST segment
    // (0,8)-(6,8) at vertex x=2.5, inside its [0,6] span -- must be blocked.
    assert.equal(los(state, 3, 8, 3, 10), false);

    // Straight down through cell column 7 crosses y=8 at vertex x=6.5 -- inside
    // the door GAP (neither south segment covers x=[6,7]) -- must NOT be blocked.
    assert.equal(los(state, 7, 8, 7, 10), true);
  } finally {
    await stopTestServer(server);
  }
});

// Loads the same engine copy the server itself uses, purely to call
// hasLineOfSight directly for this one test -- everything else in this file
// goes through the real HTTP API like every other test in this project.
const { loadEngineInto } = require("../lib/loadEngine");
const engineWindow = loadEngineInto({}, [
  path.join(__dirname, "..", "engine", "encounter.js")
]);
const CampaignOS = engineWindow.CampaignOS;

function los(state, ax, ay, bx, by) {
  return CampaignOS.hasLineOfSight(state, "Prototype Chamber", ax, ay, bx, by);
}
