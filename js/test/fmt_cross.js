// fixed() against string.format("%.Nf") from texlua.
"use strict";
const { LUA, refdir } = require("./ref.js");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { fixed } = require("../src/fmt.js");

const buf = new DataView(new ArrayBuffer(8));
const hex = (x) => { buf.setFloat64(0, x); let s = ""; for (let i = 0; i < 8; i++) s += buf.getUint8(i).toString(16).padStart(2, "0"); return s; };
let st = 99;
const rnd = () => { st = (st + 0x6D2B79F5) >>> 0; let t = st; t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0; t = (t ^ ((t + (Math.imul(t ^ (t >>> 7), t | 61) >>> 0)) >>> 0)) >>> 0; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };

const xs = [0, -0, 0.25, -0.25, 0.125, 0.375, 2.5, -2.5, 0.05, 0.15, 1.25, 1.005, 0.0625, 999.95, -0.04, -0.0001, 0.5, 1.5, 10.25];
for (let i = 0; i < 300000; i++) {
  const k = i % 5;
  if (k === 0) xs.push((rnd() - 0.5) * 2000);
  else if (k === 1) xs.push((rnd() - 0.5) * 2);
  else if (k === 2) xs.push(Math.round((rnd() - 0.5) * 4096) / 16);    // many exact ties
  else if (k === 3) xs.push(Math.round((rnd() - 0.5) * 65536) / 256);
  else xs.push((rnd() - 0.5) * 1e-3);
}
const tmp = fs.mkdtempSync("/tmp/fmtx-");
fs.writeFileSync(path.join(tmp, "in.txt"), xs.map(hex).join("\n") + "\n");
fs.writeFileSync(path.join(tmp, "run.lua"), `
local out = {}
for h in io.lines(arg[1]) do
  local x = string.unpack(">d", (h:gsub("..", function(c) return string.char(tonumber(c, 16)) end)))
  out[#out + 1] = string.format("%.1f|%.2f|%.3f", x, x, x)
end
local f = io.open(arg[2], "w") f:write(table.concat(out, "\\n"), "\\n") f:close()
`);
execFileSync(LUA, [path.join(tmp, "run.lua"), path.join(tmp, "in.txt"), path.join(tmp, "out.txt")]);
const L = fs.readFileSync(path.join(tmp, "out.txt"), "utf8").trim().split("\n");
let bad = 0;
xs.forEach((x, i) => {
  const j = `${fixed(x, 1)}|${fixed(x, 2)}|${fixed(x, 3)}`;
  if (j !== L[i] && bad++ < 10) console.log(`MISMATCH ${x}: js ${j}  lua ${L[i]}`);
});
console.log(`numbers ${xs.length}, mismatches ${bad}`);
process.exit(bad ? 1 : 0);
