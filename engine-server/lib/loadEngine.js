"use strict";

const fs = require("node:fs");

// engine/*.js are plain browser scripts copied verbatim from the 2D Campaign-OS
// project -- they attach their public API to `window` (e.g. `window.CampaignOS = {...}`)
// rather than using module.exports, so the original app can load them with a plain
// <script> tag and no build step. Rather than fork a CommonJS variant (which would
// be a second copy to keep in sync on top of the sync-engine.sh copy we already
// have), this loads them the exact same way Campaign-OS's own tests/load-script.js
// does: compile the file's source with `window`/`console` as parameters and run it
// in *this* realm (not a separate vm context, which would make a Node http response's
// JSON.stringify/array handling behave oddly across realms).
function loadEngineInto(window, filePaths) {
  filePaths.forEach((filePath) => {
    const code = fs.readFileSync(filePath, "utf8");
    const run = new Function("window", "console", code);
    run(window, console);
  });
  return window;
}

module.exports = { loadEngineInto };
