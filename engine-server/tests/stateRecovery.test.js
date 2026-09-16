"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createServer, loadState, saveState, seedState } = require("../server");

function tempStateFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), "campaign-os-3d-recovery-")), "encounter.json");
}

test("saveState writes atomically -- no .tmp file left behind, and content is valid JSON", () => {
  const stateFile = tempStateFile();
  saveState(stateFile, seedState());

  assert.ok(fs.existsSync(stateFile));
  const dir = path.dirname(stateFile);
  const leftoverTmp = fs.readdirSync(dir).filter((name) => name.includes(".tmp"));
  assert.deepEqual(leftoverTmp, []);

  const parsed = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  assert.equal(parsed.mapName, "Prototype Chamber");
});

test("saveState keeps a .bak copy of the previously saved state", () => {
  const stateFile = tempStateFile();
  const first = seedState();
  saveState(stateFile, first);
  assert.ok(!fs.existsSync(`${stateFile}.bak`), "no backup yet -- this was the first save");

  const second = { ...first, round: 99 };
  saveState(stateFile, second);

  const backup = JSON.parse(fs.readFileSync(`${stateFile}.bak`, "utf8"));
  assert.equal(backup.round, undefined, "backup should hold the FIRST save, before `round` was added");

  const current = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  assert.equal(current.round, 99);
});

test("loadState seeds a fresh encounter only when the file is simply missing (ENOENT)", () => {
  const stateFile = tempStateFile(); // mkdtemp'd dir exists, but the file itself doesn't
  const state = loadState(stateFile);
  assert.equal(state.mapName, "Prototype Chamber");
});

test("loadState throws instead of silently reseeding when the file is corrupt and no backup exists", () => {
  const stateFile = tempStateFile();
  fs.writeFileSync(stateFile, "{ this is not valid JSON");

  assert.throws(() => loadState(stateFile), /Refusing to start/);
});

test("loadState recovers from the .bak file when the primary file is corrupt", () => {
  const stateFile = tempStateFile();
  const goodState = { ...seedState(), round: 7 };
  fs.writeFileSync(`${stateFile}.bak`, JSON.stringify(goodState));
  fs.writeFileSync(stateFile, "{ not valid json at all");

  const recovered = loadState(stateFile);
  assert.equal(recovered.round, 7);
  assert.equal(recovered.mapName, "Prototype Chamber");
});

test("loadState throws when both the primary file and its backup are corrupt", () => {
  const stateFile = tempStateFile();
  fs.writeFileSync(stateFile, "{ nope");
  fs.writeFileSync(`${stateFile}.bak`, "{ also nope");

  assert.throws(() => loadState(stateFile), /Refusing to start/);
});

test("createServer refuses to start against an unrecoverably corrupt state file", () => {
  const stateFile = tempStateFile();
  fs.writeFileSync(stateFile, "{ corrupt, no backup");

  assert.throws(() => createServer({ stateFile }), /Refusing to start/);
});

test("a corrupted state file recovers via backup on the very next save after recovery", async () => {
  const stateFile = tempStateFile();
  const goodState = { ...seedState(), round: 3 };
  fs.writeFileSync(`${stateFile}.bak`, JSON.stringify(goodState));
  fs.writeFileSync(stateFile, "{ corrupt");

  const { server, baseUrl } = await new Promise((resolve) => {
    const s = createServer({ stateFile });
    s.listen(0, "127.0.0.1", () => resolve({ server: s, baseUrl: `http://127.0.0.1:${s.address().port}` }));
  });
  try {
    const res = await fetch(`${baseUrl}/state`);
    const { state } = await res.json();
    assert.equal(state.round, 3, "server should have recovered from the backup on startup");

    await fetch(`${baseUrl}/reset`, { method: "POST" });
    const reloaded = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    assert.equal(reloaded.mapName, "Prototype Chamber");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
