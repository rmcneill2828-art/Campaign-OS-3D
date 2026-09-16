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

// A bare "*" would let ANY website a user has open in the same browser fire a
// blind cross-origin POST /action against this loopback server while it's
// running. These confirm the allow-list actually discriminates: a local origin
// gets echoed back (what lets a real local dev front end's fetch() calls work),
// a random outside origin gets nothing (what makes the browser's own CORS
// enforcement block that page from completing a JSON-content-typed request).
test("GET /state echoes back an allowed local origin's own Origin header", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/state`, { headers: { Origin: "http://localhost:5500" } });
    assert.equal(res.headers.get("access-control-allow-origin"), "http://localhost:5500");
  } finally {
    await stopTestServer(server);
  }
});

test("GET /state omits Access-Control-Allow-Origin for a non-local Origin", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/state`, { headers: { Origin: "https://evil.example.com" } });
    assert.equal(res.headers.get("access-control-allow-origin"), null);
  } finally {
    await stopTestServer(server);
  }
});

test("GET /state omits Access-Control-Allow-Origin when no Origin header is sent (e.g. Godot's HTTPRequest, curl)", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/state`);
    assert.equal(res.headers.get("access-control-allow-origin"), null);
    assert.equal(res.status, 200); // absence of the header never blocks a non-browser caller
  } finally {
    await stopTestServer(server);
  }
});

test("OPTIONS preflight from 127.0.0.1 gets the CORS headers a browser needs to proceed", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/action`, {
      method: "OPTIONS",
      headers: { Origin: "http://127.0.0.1:5500" }
    });
    assert.equal(res.status, 204);
    assert.equal(res.headers.get("access-control-allow-origin"), "http://127.0.0.1:5500");
    assert.match(res.headers.get("access-control-allow-methods") || "", /POST/);
  } finally {
    await stopTestServer(server);
  }
});

// The one real client-sent payload today (/dm-command's {command, context}) is at
// most a few KB -- this confirms an oversized body is rejected outright (413,
// state left untouched) rather than accepted into memory and parsed.
test("POST /action with an oversized body is rejected with 413, not accepted", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const before = await (await fetch(`${baseUrl}/state`)).json();
    // Comfortably over the 256 KB limit -- a valid JSON action object with one
    // absurdly long field, so a naive length-only check couldn't be fooled by
    // this being "just a big string" rather than a real oversized request.
    const oversized = JSON.stringify({ type: "move_token", target: "Darkhawk", junk: "x".repeat(300 * 1024) });
    const res = await fetch(`${baseUrl}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: oversized
    });
    assert.equal(res.status, 413);

    const after = await (await fetch(`${baseUrl}/state`)).json();
    assert.deepEqual(after.state.tokens, before.state.tokens, "an oversized body must never reach DMBridge.applyActions");
  } finally {
    await stopTestServer(server);
  }
});

test("POST /action with a normal-sized body still works fine (the limit doesn't clip legitimate requests)", async () => {
  const { server, baseUrl } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "move_token", target: "Darkhawk", x: 4, y: 4 })
    });
    assert.equal(res.status, 200);
  } finally {
    await stopTestServer(server);
  }
});
