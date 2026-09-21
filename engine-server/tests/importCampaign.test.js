"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer } = require("../server");

// Same isolation reasoning as tests/createCharacter.test.js: a real end-to-end test
// would need dm-bridge/watch.js's own DND_REPO_PATH pointed at a real campaign repo
// (already verified live, separately, against a throwaway fake one -- see ROADMAP.md).
// This simulates watch.js answering import-campaign-request.json the same way
// handleImportCampaignRequest()/writeImportCampaignResponse() actually do, isolating
// the integration surface this server owns.
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

function simulateImportCampaignWatcher(bridgeDir, { ok, message, campaign }) {
  const request = JSON.parse(fs.readFileSync(path.join(bridgeDir, "import-campaign-request.json"), "utf8"));
  fs.writeFileSync(
    path.join(bridgeDir, "import-campaign-response.json"),
    JSON.stringify({ id: request.id, ok, message, campaign: campaign || null, respondedAt: new Date().toISOString() }, null, 2)
  );
  return request;
}

function fakeCampaign() {
  return {
    name: "Test Campaign",
    importedAt: new Date().toISOString(),
    files: [{ id: "characters/Kestrel.md-1", title: "Kestrel", path: "characters/Kestrel.md", category: "characters", canSpawnToken: true, isTemplate: false, summary: "A ranger.", wordCount: 2, text: "# Kestrel\nA ranger.", draft: { name: "Kestrel", type: "hero", hp: 12, maxHp: 12, ac: 12 } }],
    categories: { characters: [], locations: [], sessions: [], notes: [] }
  };
}

test("Seven requested features, item 4: POST /import-campaign writes an import-campaign-request.json in the exact shape dm-bridge/watch.js expects", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const pending = fetch(`${baseUrl}/import-campaign`, { method: "POST" });
    await new Promise((resolve) => setTimeout(resolve, 200));

    const request = JSON.parse(fs.readFileSync(path.join(bridgeDir, "import-campaign-request.json"), "utf8"));
    assert.ok(request.id.startsWith("campaign-"));

    const campaign = fakeCampaign();
    simulateImportCampaignWatcher(bridgeDir, { ok: true, message: "Imported 1 file(s) from the campaign repo.", campaign });
    const res = await pending;
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.campaign.files.length, 1);
    assert.equal(body.campaign.files[0].draft.name, "Kestrel");
  } finally {
    await stopTestServer(server);
  }
});

test("Seven requested features, item 4: POST /import-campaign surfaces a real ok:false outcome (e.g. DND_REPO_PATH unset) without treating it as an HTTP error", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const pending = fetch(`${baseUrl}/import-campaign`, { method: "POST" });
    await new Promise((resolve) => setTimeout(resolve, 200));
    simulateImportCampaignWatcher(bridgeDir, { ok: false, message: "DND_REPO_PATH isn't set. Stop the watcher, set it to your campaign repo's path, and try again.", campaign: null });

    const res = await pending;
    assert.equal(res.status, 200); // the request was answered correctly -- the failure is business-level, not a transport error
    const body = await res.json();
    assert.equal(body.ok, false);
    assert.equal(body.campaign, null);
    assert.match(body.message, /DND_REPO_PATH/);
  } finally {
    await stopTestServer(server);
  }
});

// Same "two overlapping calls, both must land correctly" concern as
// createCharacter.test.js's own concurrency test, for import-campaign-request.json/
// import-campaign-response.json's own separate mailbox pair.
test("Seven requested features, item 4: two concurrent POST /import-campaign calls are serialized, not raced", async () => {
  const { server, baseUrl, bridgeDir } = await startTestServer();
  try {
    const firstPending = fetch(`${baseUrl}/import-campaign`, { method: "POST" });
    await new Promise((resolve) => setTimeout(resolve, 200));
    const firstRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "import-campaign-request.json"), "utf8"));

    const secondPending = fetch(`${baseUrl}/import-campaign`, { method: "POST" });
    await new Promise((resolve) => setTimeout(resolve, 200));
    const stillFirstRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "import-campaign-request.json"), "utf8"));
    assert.equal(stillFirstRequest.id, firstRequest.id, "second call should still be queued, not have overwritten the request file");

    simulateImportCampaignWatcher(bridgeDir, { ok: true, message: "Imported 1 file(s) from the campaign repo.", campaign: fakeCampaign() });
    const firstRes = await firstPending;
    assert.equal((await firstRes.json()).ok, true);

    await new Promise((resolve) => setTimeout(resolve, 200));
    const secondRequest = JSON.parse(fs.readFileSync(path.join(bridgeDir, "import-campaign-request.json"), "utf8"));
    assert.notEqual(secondRequest.id, firstRequest.id);

    simulateImportCampaignWatcher(bridgeDir, { ok: true, message: "Imported 1 file(s) from the campaign repo.", campaign: fakeCampaign() });
    const secondRes = await secondPending;
    assert.equal((await secondRes.json()).ok, true);
  } finally {
    await stopTestServer(server);
  }
});
