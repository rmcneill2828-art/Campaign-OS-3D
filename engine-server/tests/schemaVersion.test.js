"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { seedState, loadState, saveState, migrateState, SCHEMA_VERSION } = require("../server");

function tempStateFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), "campaign-os-3d-schema-")), "encounter.json");
}

test("seedState() stamps the current schema version", () => {
  assert.equal(seedState().schemaVersion, SCHEMA_VERSION);
});

test("migrateState() is a no-op on an already-current state", () => {
  const state = seedState();
  const migrated = migrateState(state);
  assert.equal(migrated.schemaVersion, SCHEMA_VERSION);
  assert.deepEqual(migrated.tokens, state.tokens);
  assert.deepEqual(migrated.maps, state.maps);
});

// Every save this project produced before this feature existed has no schemaVersion
// field at all -- migrateState() must treat that as version 0 and bring it forward,
// not choke on the missing field or (worse) silently treat unversioned data as
// already-current without ever running it through a real migration path.
test("migrateState() stamps a legacy (unversioned) save up to the current version, data untouched", () => {
  const legacy = seedState();
  delete legacy.schemaVersion; // simulates a real pre-versioning save file
  assert.equal(legacy.schemaVersion, undefined);

  const migrated = migrateState(legacy);
  assert.equal(migrated.schemaVersion, SCHEMA_VERSION);
  assert.deepEqual(migrated.tokens, legacy.tokens);
  assert.deepEqual(migrated.maps, legacy.maps);
  assert.deepEqual(migrated.log, legacy.log);
});

// A file claiming a version newer than this server understands is a real problem --
// an older server has no business guessing at a newer on-disk shape. This is the
// scenario a future downgrade (or a state file shared from a newer checkout) would
// hit; refusing loudly is much safer than silently misinterpreting it.
test("migrateState() throws on a schemaVersion newer than this server understands", () => {
  const fromTheFuture = { ...seedState(), schemaVersion: SCHEMA_VERSION + 1 };
  assert.throws(() => migrateState(fromTheFuture), /newer than this server understands/);
});

test("loadState() migrates a legacy on-disk file with no schemaVersion field", () => {
  const stateFile = tempStateFile();
  const legacy = seedState();
  delete legacy.schemaVersion;
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify(legacy));

  const loaded = loadState(stateFile);
  assert.equal(loaded.schemaVersion, SCHEMA_VERSION);
  assert.equal(loaded.mapName, legacy.mapName);
});

// A future-versioned on-disk file is a load FAILURE, not "no state yet" -- it must
// go through the exact same backup-then-refuse path real corruption already does,
// not be silently reseeded (which would discard a real, just-too-new save) or
// silently accepted (which would let an older server misinterpret it).
test("loadState() refuses to silently reseed over a future-versioned file with no usable backup", () => {
  const stateFile = tempStateFile();
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(stateFile, JSON.stringify({ ...seedState(), schemaVersion: SCHEMA_VERSION + 1 }));

  assert.throws(() => loadState(stateFile), /Refusing to start/);
});

test("loadState() recovers via backup when the primary file is future-versioned but the backup isn't", () => {
  const stateFile = tempStateFile();
  const goodBackup = { ...seedState(), mapName: "Entrance Hall" };
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  fs.writeFileSync(`${stateFile}.bak`, JSON.stringify(goodBackup));
  fs.writeFileSync(stateFile, JSON.stringify({ ...seedState(), schemaVersion: SCHEMA_VERSION + 1 }));

  const recovered = loadState(stateFile);
  assert.equal(recovered.schemaVersion, SCHEMA_VERSION);
  assert.equal(recovered.mapName, "Entrance Hall");
});

test("saveState() persists whatever schemaVersion the in-memory state already carries", () => {
  const stateFile = tempStateFile();
  saveState(stateFile, seedState());
  const onDisk = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  assert.equal(onDisk.schemaVersion, SCHEMA_VERSION);
});
