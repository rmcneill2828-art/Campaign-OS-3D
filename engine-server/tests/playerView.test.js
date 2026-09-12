"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

// Same throwaway-server-per-test pattern as the other test files.
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

test("Phase 6: visibleTokenIds includes heroes and in-sight monsters by default (no walls block anything in the open room)", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const { state, visibility } = await (await fetch(`${baseUrl}/state`)).json();
    const allIds = state.tokens.map((token) => token.id);
    // Everyone spawns inside the same open room with no obstruction between
    // them -- matching ui/playerView.js's own "if any PC can see it" union
    // rule, every token should be visible with the seeded room's default
    // token placement.
    assert.deepEqual([...visibility.visibleTokenIds].sort(), [...allIds].sort());
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 6: hiddenFromPlayers always wins, even in plain sight", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const before = await (await fetch(`${baseUrl}/state`)).json();
    const goblin = before.state.tokens.find((token) => token.name.startsWith("Goblin"));

    const after = await postAction(baseUrl, { type: "set_visibility", target: goblin.name, hidden: true });
    assert.ok(!after.visibility.visibleTokenIds.includes(goblin.id));

    // Un-hiding brings it back -- confirms this is really reading the live
    // hiddenFromPlayers flag each call, not a one-way filter.
    const revealed = await postAction(baseUrl, { type: "set_visibility", target: goblin.name, hidden: false });
    assert.ok(revealed.visibility.visibleTokenIds.includes(goblin.id));
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 6: a token behind a real interior wall drops out of visibleTokenIds, and reappears once the wall is removed", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const before = await (await fetch(`${baseUrl}/state`)).json();
    const goblin = before.state.tokens.find((token) => token.name.startsWith("Goblin"));

    // Both heroes into one corner, the goblin into the opposite corner --
    // the room's own perimeter walls don't block this diagonal at all, so
    // it starts genuinely visible (same as the "no walls block anything"
    // test above, just from different cells).
    await postAction(baseUrl, { type: "move_token", target: "Darkhawk", x: 1, y: 1 });
    await postAction(baseUrl, { type: "move_token", target: "Wren", x: 1, y: 1 });
    const beforeWall = await postAction(baseUrl, { type: "move_token", target: goblin.name, x: 12, y: 8 });
    assert.ok(beforeWall.visibility.visibleTokenIds.includes(goblin.id));

    // A real interior wall straight across the room, added the same way the
    // 2D app's own Walls tool would (add_wall, the exact dmBridge action) --
    // must cross the (1,1)-to-(12,8) diagonal both heroes and the goblin
    // currently sit on.
    const walled = await postAction(baseUrl, { type: "add_wall", x1: 0, y1: 4, x2: 12, y2: 4 });
    assert.ok(!walled.visibility.visibleTokenIds.includes(goblin.id));

    // Removing it (remove_wall_near, the exact dmBridge action a DM's Walls
    // tool uses to erase a wall) restores visibility -- confirms this is a
    // live recomputation every call, not a one-way/cached filter.
    const unwalled = await postAction(baseUrl, { type: "remove_wall_near", x: 6, y: 4 });
    assert.ok(unwalled.visibility.visibleTokenIds.includes(goblin.id));
  } finally {
    await stopTestServer(server);
  }
});
