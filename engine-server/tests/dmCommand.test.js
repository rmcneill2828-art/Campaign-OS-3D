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

// A second /dm-command firing before the first got its response used to be a real bug:
// both share the same request.json/response.json filenames (dm-bridge/watch.js's own
// fixed paths, verbatim-copied from the 2D app, can't change), so the second call's
// write could clobber the first's still-unanswered request, or either call could pick
// up a response meant for the other. The server now serializes the whole cycle so a
// later command doesn't even write its request.json until the earlier one has fully
// finished (response applied, state saved) -- this drives two overlapping commands
// through that path and checks each ends up with its OWN actions applied, in order,
// never the other's.
test("Phase 7: two concurrent POST /dm-command calls are serialized, not raced", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const firstPending = fetch(`${baseUrl}/dm-command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "Darkhawk moves to the door." })
    });
    // Give the first call time to actually write request.json before the second fires,
    // so we know the second is the one queueing behind an in-flight command, not just
    // racing it by luck.
    await new Promise((resolve) => setTimeout(resolve, 200));
    const firstRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "request.json"), "utf8"));
    assert.equal(firstRequest.command, "Darkhawk moves to the door.");

    const secondPending = fetch(`${baseUrl}/dm-command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command: "Wren fires an arrow." })
    });
    // The second call must NOT have overwritten request.json yet -- it's still queued
    // behind the first, which hasn't been answered.
    await new Promise((resolve) => setTimeout(resolve, 200));
    const stillFirstRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "request.json"), "utf8"));
    assert.equal(stillFirstRequest.id, firstRequest.id, "second call should still be queued, not have overwritten request.json");

    // Answer the first -- only once this resolves should the second get its turn.
    simulateWatcher(bridgeDir, {
      message: "Darkhawk reaches the door.",
      actions: [{ type: "move_token", target: "Darkhawk", x: 2, y: 2 }]
    });
    const firstRes = await firstPending;
    assert.equal(firstRes.status, 200);
    const firstBody = await firstRes.json();
    assert.equal(firstBody.message, "Darkhawk reaches the door.");
    assert.equal(firstBody.queuedAhead, 0);
    const firstDarkhawk = firstBody.state.tokens.find((t) => t.name === "Darkhawk");
    assert.equal(firstDarkhawk.x, 2);
    assert.equal(firstDarkhawk.y, 2);

    // Now the second call's request.json should appear -- answer that one too.
    await new Promise((resolve) => setTimeout(resolve, 200));
    const secondRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "request.json"), "utf8"));
    assert.equal(secondRequest.command, "Wren fires an arrow.");
    assert.notEqual(secondRequest.id, firstRequest.id);

    simulateWatcher(bridgeDir, {
      message: "Wren's arrow finds its mark.",
      actions: [{ type: "move_token", target: "Wren", x: 5, y: 5 }]
    });
    const secondRes = await secondPending;
    assert.equal(secondRes.status, 200);
    const secondBody = await secondRes.json();
    assert.equal(secondBody.message, "Wren's arrow finds its mark.");
    assert.equal(secondBody.queuedAhead, 1, "second call should report it was queued behind one other");
    const secondWren = secondBody.state.tokens.find((t) => t.name === "Wren");
    assert.equal(secondWren.x, 5);
    assert.equal(secondWren.y, 5);
    // The first command's own effect should still be intact in the final saved state.
    const secondDarkhawk = secondBody.state.tokens.find((t) => t.name === "Darkhawk");
    assert.equal(secondDarkhawk.x, 2);
    assert.equal(secondDarkhawk.y, 2);
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
