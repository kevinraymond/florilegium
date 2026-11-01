// fmt.js — numbers as Lua (C printf) prints them, bit for bit.
// Copyright (c) 2026 Kevin Raymond; JavaScript port (c) 2026 jfoboss. MIT License: see LICENSE.
"use strict";

// "%.Nf": printf prints the exact decimal value of the binary number,
// rounded to nearest, ties to even. Number.toFixed rounds the same way
// except on an exact tie, where it takes the larger. A tie is only
// possible if x is a multiple of 2^-(N+1) and x * 2^(N+1) is odd;
// this is checked exactly (multiplying by a power of two loses no bits).
const P2 = [2, 4, 8, 16, 32, 64, 128];
function fixed(x, n) {
  if (x !== x) return "-nan";                 // as glibc does for 0/0 in Lua
  if (x === Infinity) return "inf";
  if (x === -Infinity) return "-inf";
  if (x === 0) return (1 / x < 0 ? "-" : "") + (0).toFixed(n);
  const t = x * P2[n];                        // x * 2^(n+1)
  if (Number.isInteger(t) && Math.abs(t) % 2 === 1) {
    // exact tie: |x| * 10^n = k + 1/2, take the even one of k and k+1
    const a = Math.abs(x);
    const lo = a.toFixed(n);                  // toFixed gave k+1 (the larger)
    // k+1 as digits without the point
    const digits = lo.replace(".", "");
    const last = +digits[digits.length - 1];
    let s = lo;
    if (last % 2 === 1) {                     // k+1 is odd -> the even one is k
      s = decDown(lo);
    }
    return (x < 0 ? "-" : "") + s;
  }
  return x.toFixed(n);
}
// decrease a decimal string by one unit in the last place ("0.3" -> "0.2", "1.0" -> "0.9")
function decDown(s) {
  const ch = s.split("");
  for (let i = ch.length - 1; i >= 0; i--) {
    if (ch[i] === ".") continue;
    if (ch[i] === "0") { ch[i] = "9"; continue; }
    ch[i] = String(+ch[i] - 1);
    break;
  }
  let r = ch.join("");
  if (/^0\d/.test(r)) r = r.replace(/^0+(?=\d)/, "");
  return r;
}

module.exports = { fixed };
