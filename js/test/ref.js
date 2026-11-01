// The reference Lua for the cross-checks: the repository's own *.lua with every `a ^ b`
// rewritten to `__pow(a, b)` (tools/rewrite_pow.py), so the reference can use detmath's pow.
// Built fresh into a temp dir on each run: the reference is always the current Lua.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const LUA = process.env.LUA || "texlua";
const root = path.resolve(__dirname, "../..");
let dir = null;

function refdir() {
  if (dir) return dir;
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "florilegium-ref-"));
  const tool = path.join(__dirname, "../tools/rewrite_pow.py");
  for (const f of fs.readdirSync(root)) {
    if (f.endsWith(".lua")) execFileSync("python3", [tool, path.join(root, f), path.join(dir, f)], { stdio: "ignore" });
  }
  return dir;
}

module.exports = { LUA, refdir };
