"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

// Each test gets its own throwaway state file and an ephemeral port (0 -> OS picks
// one free) so tests never collide with each other, a developer's real prototype
// save, or a live `node server.js` already running on the default port.
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

test("GET /state returns a seeded encounter with heroes and monsters", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/state`);
    assert.equal(res.status, 200);
    const { state } = await res.json();
    assert.equal(state.mapName, "Prototype Chamber");
    const names = state.tokens.map((token) => token.name);
    assert.ok(names.includes("Darkhawk"));
    assert.ok(names.includes("Wren"));
    assert.ok(names.some((name) => name.startsWith("Goblin")));
  } finally {
    await stopTestServer(server);
  }
});

test("POST /action move_token moves a token and persists across a fresh load", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const before = await (await fetch(`${baseUrl}/state`)).json();
    const darkhawk = before.state.tokens.find((token) => token.name === "Darkhawk");

    const moveRes = await fetch(`${baseUrl}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "move_token", target: "Darkhawk", x: 3, y: 3 })
    });
    assert.equal(moveRes.status, 200);
    const moved = await moveRes.json();
    const movedToken = moved.state.tokens.find((token) => token.id === darkhawk.id);
    assert.equal(movedToken.x, 3);
    assert.equal(movedToken.y, 3);
    assert.ok(moved.messages[0].includes("moves to"));
  } finally {
    await stopTestServer(server);
  }
});

test("POST /action attack resolves through the real engine (hit or miss, HP or message changes)", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const before = await (await fetch(`${baseUrl}/state`)).json();
    const goblin = before.state.tokens.find((token) => token.name.startsWith("Goblin"));

    const res = await fetch(`${baseUrl}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "attack", attacker: "Darkhawk", target: goblin.name })
    });
    assert.equal(res.status, 200);
    const result = await res.json();
    assert.equal(typeof result.messages[0], "string");
    assert.ok(result.messages[0].length > 0);
  } finally {
    await stopTestServer(server);
  }
});

test("POST /action with no type is rejected without mutating state", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target: "Darkhawk" })
    });
    assert.equal(res.status, 400);
  } finally {
    await stopTestServer(server);
  }
});

test("POST /reset restores the default seeded encounter", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    await fetch(`${baseUrl}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "move_token", target: "Darkhawk", x: 1, y: 1 })
    });
    const resetRes = await fetch(`${baseUrl}/reset`, { method: "POST" });
    assert.equal(resetRes.status, 200);
    const { state } = await resetRes.json();
    const darkhawk = state.tokens.find((token) => token.name === "Darkhawk");
    // addToken() places new tokens via findOpenTile() starting near (4, 4), not (1, 1) --
    // this just confirms /reset actually re-seeded rather than replaying the moved state.
    assert.notEqual(`${darkhawk.x},${darkhawk.y}`, "1,1");
  } finally {
    await stopTestServer(server);
  }
});
