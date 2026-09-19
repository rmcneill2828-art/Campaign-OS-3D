"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

// Same isolation reasoning as tests/dmCommand.test.js: a real end-to-end test would
// need dm-bridge/watch.js's own DND_REPO_PATH pointed at a real campaign repo. Instead
// this simulates watch.js answering create-character-request.json the same way
// handleCreateCharacterRequest()/writeCreateCharacterResponse() actually do, isolating
// the integration surface this server owns -- writing the request in the exact shape
// watch.js expects, and correctly applying whatever create-character-response.json
// says once it appears.
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

function simulateCreateCharacterWatcher(bridgeDir, { ok, message }) {
  const request = JSON.parse(fs.readFileSync(path.join(bridgeDir, "create-character-request.json"), "utf8"));
  fs.writeFileSync(
    path.join(bridgeDir, "create-character-response.json"),
    JSON.stringify({ id: request.id, ok, message, respondedAt: new Date().toISOString() }, null, 2)
  );
  return request;
}

function validDraft(overrides = {}) {
  return {
    name: "Kestrel",
    race: "Half-Elf",
    className: "Ranger",
    level: 3,
    background: "Outlander",
    alignment: "Chaotic Good",
    abilityScores: { STR: 12, DEX: 17, CON: 14, INT: 10, WIS: 15, CHA: 8 },
    proficientSkills: ["Perception", "Survival"],
    speed: 30,
    languages: "Common, Elvish",
    equipment: "Longbow, leather armor",
    attack: { weaponName: "Longbow", diceSize: "1d8", ability: "DEX", damageType: "piercing" },
    ...overrides
  };
}

test("Seven requested features, item 1: POST /create-character writes a create-character-request.json in the exact shape dm-bridge/watch.js expects", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const pending = fetch(`${baseUrl}/create-character`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validDraft())
    });
    await new Promise((resolve) => setTimeout(resolve, 200));

    const request = JSON.parse(fs.readFileSync(path.join(bridgeDir, "create-character-request.json"), "utf8"));
    assert.ok(request.id.startsWith("char-"));
    assert.equal(request.fileName, "Kestrel.md");
    assert.ok(request.markdown.startsWith("# Kestrel"));
    assert.match(request.markdown, /\*\*Class & Level:\*\* Ranger 3/);
    assert.match(request.markdown, /\| Longbow \| \+5 \| 1d8\+3 piercing \|/); // prof (+2 at level 3) + DEX mod (+3)

    simulateCreateCharacterWatcher(bridgeDir, { ok: true, message: "Created characters/Kestrel.md in the campaign repo." });
    const res = await pending;
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.fileName, "Kestrel.md");
    assert.equal(body.character.name, "Kestrel");
    // Ranger (d10 hit die) level 3, CON 14 (+2 mod): 12 at level 1, +8 per level after
    // (average roll 6, + CON mod 2) -- 12 + 8 + 8 = 28. A real, independently-derived
    // number, not just "computeCharacter returned something."
    assert.equal(body.character.hp, 28);
  } finally {
    await stopTestServer(server);
  }
});

test("Seven requested features, item 1: POST /create-character rejects an invalid draft without writing a request, and doesn't wait for a response", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const res = await fetch(`${baseUrl}/create-character`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "", className: "NotAClass", abilityScores: {} })
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.ok(body.errors.length >= 3); // name, className, and all 6 ability scores missing
    assert.ok(!fs.existsSync(path.join(bridgeDir, "create-character-request.json")));
  } finally {
    await stopTestServer(server);
  }
});

test("Seven requested features, item 1: POST /create-character surfaces a real ok:false outcome (e.g. a filename collision) without treating it as an HTTP error", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const pending = fetch(`${baseUrl}/create-character`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validDraft({ name: "Darkhawk" }))
    });
    await new Promise((resolve) => setTimeout(resolve, 200));
    simulateCreateCharacterWatcher(bridgeDir, { ok: false, message: "A character file named \"Darkhawk.md\" already exists -- pick a different name." });

    const res = await pending;
    assert.equal(res.status, 200); // the request was answered correctly -- the failure is business-level, not a transport error
    const body = await res.json();
    assert.equal(body.ok, false);
    assert.match(body.message, /already exists/);
  } finally {
    await stopTestServer(server);
  }
});

// Same "two overlapping calls, both must land correctly" concern as dmCommand.test.js's
// own concurrency test, for create-character-request.json/create-character-response.json's
// own separate mailbox pair.
test("Seven requested features, item 1: two concurrent POST /create-character calls are serialized, not raced", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const firstPending = fetch(`${baseUrl}/create-character`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validDraft({ name: "Kestrel" }))
    });
    await new Promise((resolve) => setTimeout(resolve, 200));
    const firstRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "create-character-request.json"), "utf8"));
    assert.equal(firstRequest.fileName, "Kestrel.md");

    const secondPending = fetch(`${baseUrl}/create-character`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validDraft({ name: "Thistle" }))
    });
    await new Promise((resolve) => setTimeout(resolve, 200));
    const stillFirstRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "create-character-request.json"), "utf8"));
    assert.equal(stillFirstRequest.id, firstRequest.id, "second call should still be queued, not have overwritten the request file");

    simulateCreateCharacterWatcher(bridgeDir, { ok: true, message: "Created characters/Kestrel.md in the campaign repo." });
    const firstRes = await firstPending;
    const firstBody = await firstRes.json();
    assert.equal(firstBody.fileName, "Kestrel.md");

    await new Promise((resolve) => setTimeout(resolve, 200));
    const secondRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "create-character-request.json"), "utf8"));
    assert.equal(secondRequest.fileName, "Thistle.md");
    assert.notEqual(secondRequest.id, firstRequest.id);

    simulateCreateCharacterWatcher(bridgeDir, { ok: true, message: "Created characters/Thistle.md in the campaign repo." });
    const secondRes = await secondPending;
    const secondBody = await secondRes.json();
    assert.equal(secondBody.fileName, "Thistle.md");
  } finally {
    await stopTestServer(server);
  }
});
