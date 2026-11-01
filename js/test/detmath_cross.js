// Cross-check of detmath.js and detmath.lua: bit for bit over a large set of inputs.
// node test/detmath_cross.js [N]
"use strict";
const { LUA, refdir } = require("./ref.js");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const D = require("../src/detmath.js");

const N = +(process.argv[2] || 200000);
const buf = new DataView(new ArrayBuffer(8));
const hex = (x) => { buf.setFloat64(0, x); let s = ""; for (let i = 0; i < 8; i++) s += buf.getUint8(i).toString(16).padStart(2, "0"); return s; };

// our own input generator, so the set is reproducible
let st = 12345;
const rnd = () => { st = (st + 0x6D2B79F5) >>> 0; let t = st; t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0; t = (t ^ ((t + (Math.imul(t ^ (t >>> 7), t | 61) >>> 0)) >>> 0)) >>> 0; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const R = (a, b) => a + (b - a) * rnd();

const cases = [];   // [fn, a, b]
const special = [0, -0, 1, -1, 0.5, 2, 1e-300, -1e-300, 1e300, Math.PI, -Math.PI, Math.PI / 2, Math.PI / 4,
  0.4375, 0.6875, 1.1875, 2.4375, 0.7853981633974483, -0.7853981633974483, 1.4142135623730951, 7.378697629483821e19];
for (const s of special) {
  cases.push(["sin", s, 0], ["cos", s, 0], ["atan", s, 0]);
  if (s > 0) cases.push(["log", s, 0]);
  cases.push(["exp", s / 1e297 > 1 ? 1 : s, 0]);
  for (const t of special) cases.push(["atan2", s, t]);
}
const fracs = [2.4, 1 / 2.4, 1 / 3, 1.3, 0.8, 0.85, 0.6, 1.4, 6, 0.7, 0.55, 0.95, 0.62, 0.75, 0.5, 0.9, 2.3, 1.6, 3, 2, 1.15, 0.4];
for (let i = 0; i < N; i++) {
  const k = i % 8;
  if (k === 0) cases.push(["sin", R(-200, 200), 0]);
  else if (k === 1) cases.push(["cos", R(-200, 200), 0]);
  else if (k === 2) cases.push(["sin", R(-1e-3, 1e-3), 0]);
  else if (k === 3) cases.push(["atan2", R(-20, 20), R(-20, 20)]);
  else if (k === 4) cases.push(["log", Math.pow(10, R(-12, 8)), 0]);
  else if (k === 5) cases.push(["exp", R(-60, 60), 0]);
  else if (k === 6) cases.push(["pow", R(0, 12), fracs[i % fracs.length]]);
  else cases.push(["pow", R(-3, 3), [2, 3, 6][i % 3]]);
}

const tmp = fs.mkdtempSync("/tmp/detx-");
fs.writeFileSync(path.join(tmp, "in.txt"), cases.map(([f, a, b]) => `${f} ${hex(a)} ${hex(b)}`).join("\n") + "\n");
const luaDir = path.resolve(__dirname, "../lua");
fs.writeFileSync(path.join(tmp, "run.lua"), `
package.path = ${JSON.stringify(luaDir + "/?.lua;")} .. package.path
local D = require("detmath")
local function un(h) return (string.unpack(">d", (h:gsub("..", function(c) return string.char(tonumber(c, 16)) end)))) end
local function hx(x) return (string.pack(">d", x):gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local out = {}
for line in io.lines(arg[1]) do
  local f, a, b = line:match("(%S+) (%S+) (%S+)")
  a, b = un(a), un(b)
  local r
  if f == "atan2" or f == "pow" then r = D[f](a, b) else r = D[f](a) end
  out[#out + 1] = hx(r)
end
local fh = io.open(arg[2], "w") fh:write(table.concat(out, "\\n"), "\\n") fh:close()
`);
const t0 = Date.now();
execFileSync(LUA, [path.join(tmp, "run.lua"), path.join(tmp, "in.txt"), path.join(tmp, "out.txt")]);
const luaOut = fs.readFileSync(path.join(tmp, "out.txt"), "utf8").trim().split("\n");
const canon = (h) => { buf.setBigUint64(0, BigInt("0x" + h)); const x = buf.getFloat64(0); return x !== x ? "nan" : h; };
let bad = 0;
cases.forEach(([f, a, b], i) => {
  const r = (f === "atan2" || f === "pow") ? D[f](a, b) : D[f](a);
  if (canon(hex(r)) !== canon(luaOut[i])) {
    if (bad++ < 10) console.log(`MISMATCH ${f}(${a}${f === "atan2" || f === "pow" ? ", " + b : ""}): js ${r} lua ${luaOut[i]}`);
  }
});
// and accuracy against the built-ins, so determinism costs no quality
let maxRel = { sin: 0, cos: 0, atan2: 0, log: 0, exp: 0, pow: 0 };
const ref = { sin: Math.sin, cos: Math.cos, atan2: Math.atan2, log: Math.log, exp: Math.exp, pow: Math.pow };
cases.forEach(([f, a, b]) => {
  if (!ref[f]) return;
  const r = (f === "atan2" || f === "pow") ? D[f](a, b) : D[f](a);
  const e = (f === "atan2" || f === "pow") ? ref[f](a, b) : ref[f](a);
  if (!isFinite(e) || !isFinite(r) || Math.abs(e) < 1e-300) return;
  if ((f === "sin" || f === "cos") && Math.abs(a) > 1e4) return;   // working range of angles
  if ((f === "sin" || f === "cos") && Math.abs(e) < 1e-12) return;  // near a zero of the function: absolute error
  const rel = Math.abs(r - e) / Math.abs(e);
  if (rel > maxRel[f]) maxRel[f] = rel;
});
console.log(`cases ${cases.length}, JS/Lua mismatches: ${bad} (${Date.now() - t0} ms)`);
console.log("largest relative error against the built-ins:", Object.entries(maxRel).map(([k, v]) => `${k} ${v.toExponential(1)}`).join(", "));
process.exit(bad ? 1 : 0);
