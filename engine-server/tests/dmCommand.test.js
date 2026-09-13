"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

// A real end-to-end test would need the actual `claude` CLI installed, authenticated,
// and willing to spend real money/time on every test run -- not something to depend on
// for a fast, deterministic suite. Instead these tests isolate the real integration
// surface this server actually owns: writing dm-bridge/request.json in the exact shape
// dm-bridge/watch.js's buildPrompt() expects, and correctly picking up + applying a
// response.json once one appears (which is ALL dm-bridge/watch.js -- copied verbatim
// from Campaign-OS, unmodified -- would produce after a real Claude call). Everything
// between those two points (the actual LLM call) is dm-bridge/watch.js's own job, not
// this server's, and isn't re-tested here.
function startTestServer() {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "campaign-os-3d-"));
  const stateFile = path.join(tmpRoot, "encounter.json");
  const bridgeDir = path.join(tmpRoot, "dm-bridge");
  const server = createServer({ stateFile, bridgeDir });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      resolve({ server, baseUrl: `http://127.0.0.1:${port}`, bridgeDir });
    });
  });
}

function stopTestServer(server) {
  return new Promise((resolve) => server.close(resolve));
}

// Simulates dm-bridge/watch.js answering a request -- reads request.json (to grab the
// real id this server just wrote, the same way the real watcher would), writes back a
// response.json in the exact shape watch.js's writeResponse() produces.
function simulateWatcher(bridgeDir, { message, actions }) {
  const request = JSON.parse(fs.readFileSync(path.join(bridgeDir, "request.json"), "utf8"));
  fs.writeFileSync(
    path.join(bridgeDir, "response.json"),
    JSON.stringify({ id: request.id, respondedAt: new Date().toISOString(), message, actions }, null, 2)
  );
  return request;
}

test("Phase 7: POST /dm-command writes a request.json in the exact shape dm-bridge/watch.js's buildPrompt() expects", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    // Fire the request without waiting for the (never-arriving, in this test) response --
    // just long enough for the server to have written request.json, then inspect it.
    const pending = fetch(`${baseUrl}/dm-command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "The goblins charge Darkhawk." })
    });
    await new Promise((resolve) => setTimeout(resolve, 200));

    const request = JSON.parse(fs.readFileSync(path.join(bridgeDir, "request.json"), "utf8"));
    assert.equal(request.command, "The goblins charge Darkhawk.");
    assert.equal(request.context, null);
    assert.ok(request.id.startsWith("req-"));
    assert.equal(request.state.mapName, "Prototype Chamber");
    assert.equal(request.state.grid.columns, 12);
    assert.equal(request.state.grid.rows, 8);
    assert.equal(request.state.wallCount, 5); // the Phase 5 seeded room walls
    assert.equal(request.state.round, 0);
    assert.equal(request.state.activeToken, null);
    const darkhawk = request.state.tokens.find((t) => t.name === "Darkhawk");
    assert.ok(darkhawk, "Darkhawk should be in the bridge snapshot");
    assert.equal(darkhawk.hp, 91);
    assert.deepEqual(darkhawk.abilityScores, { STR: 20, DEX: 14, CON: 18, INT: 10, WIS: 12, CHA: 10 });
    assert.equal(darkhawk.speed, 30);
    assert.equal(darkhawk.movementLeft, 30);

    // Answer it now so the pending fetch resolves instead of hanging for the full
    // 2-minute timeout and slowing the test suite down.
    simulateWatcher(bridgeDir, { message: "Test.", actions: [] });
    const res = await pending;
    assert.equal(res.status, 200);
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 7: POST /dm-command applies the simulated response's actions through the real engine", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const pending = fetch(`${baseUrl}/dm-command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "Darkhawk charges the nearest goblin and swings." })
    });
    await new Promise((resolve) => setTimeout(resolve, 200));
    const request = simulateWatcher(bridgeDir, {
      message: "Darkhawk closes in and swings hard!",
      actions: [
        { type: "move_token", target: "Darkhawk", x: 6, y: 4 },
        { type: "next_turn" }
      ]
    });

    const res = await pending;
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.message, "Darkhawk closes in and swings hard!");
    assert.ok(body.actionMessages.length >= 2);
    const darkhawk = body.state.tokens.find((t) => t.name === "Darkhawk");
    assert.equal(darkhawk.x, 6);
    assert.equal(darkhawk.y, 4);
    assert.equal(body.state.turn.round, 1); // next_turn actually ran through the real engine
    assert.ok(body.visibility); // Phase 5/6 wiring still applies to this response too

    // Persisted, same durability guarantee every other mutating endpoint already has.
    const reloaded = await (await fetch(`${baseUrl}/state`)).json();
    const reloadedDarkhawk = reloaded.state.tokens.find((t) => t.name === "Darkhawk");
    assert.equal(reloadedDarkhawk.x, 6);
    assert.equal(request.id, JSON.parse(fs.readFileSync(path.join(bridgeDir, "response.json"), "utf8")).id);
  } finally {
    await stopTestServer(server);
  }
});

test("Phase 7: POST /dm-command rejects an empty command without writing a request", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/dm-command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "   " })
    });
    assert.equal(res.status, 400);
    assert.ok(!fs.existsSync(path.join(bridgeDir, "request.json")));
  } finally {
    await stopTestServer(server);
  }
});
