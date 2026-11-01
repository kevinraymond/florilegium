// detmath.js — deterministic sin, cos, atan2, log, exp, pow.
// Copyright (c) 2026 Kevin Raymond; JavaScript port (c) 2026 jfoboss. MIT License: see LICENSE.
// fdlibm: Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved. Developed at SunSoft, a Sun Microsystems, Inc. business. Permission to use, copy, modify, and distribute this software is freely granted, provided that this notice is preserved.
//
// The built-in Math.sin/cos/pow/log of different engines (V8, JavaScriptCore, glibc
// under texlua) sometimes differ in the last bit. The garden grows greedily,
// and one such difference can send a branch somewhere else. Here the functions
// follow the fdlibm algorithms (Sun Microsystems, 1993) using only +, -, *, /
// and comparisons, which IEEE 754 requires to compute the same everywhere, so
// the result is bit for bit the same in any engine. The Lua copy is detmath.lua;
// the two must agree bit for bit (checked by test/detmath_cross.js).
//
// Not used: Math.fround, FMA, bit operations on doubles.
"use strict";

// ---------------------------------------------------------------- sin / cos
const S1 = -1.66666666666666324348e-01, S2 = 8.33333333332248946124e-03,
  S3 = -1.98412698298579493134e-04, S4 = 2.75573137070700676789e-06,
  S5 = -2.50507602534068634195e-08, S6 = 1.58969099521155010221e-10;
const C1 = 4.16666666666666019037e-02, C2 = -1.38888888888741095749e-03,
  C3 = 2.48015872894767294178e-05, C4 = -2.75573143513906633035e-07,
  C5 = 2.08757232129817482790e-09, C6 = -1.13596475577881948265e-11;
const INVPIO2 = 6.36619772367581382433e-01;
const PIO2_1 = 1.57079632673412561417e+00;    // first 33 bits of pi/2
const PIO2_1T = 6.07710050650619224932e-11;   // pi/2 - PIO2_1

function ksin(x) {
  const z = x * x, v = z * x;
  const r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
  return x + v * (S1 + z * r);
}
function kcos(x) {
  const z = x * x;
  const r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
  return 1 - (0.5 * z - z * r);
}
// x = n*pi/2 + y, |y| <= pi/4 (Cody–Waite, pi/2 in two parts; exact for |x| < 2^20)
function reduce(x) {
  const n = Math.floor(x * INVPIO2 + 0.5);
  const y = (x - n * PIO2_1) - n * PIO2_1T;
  return [n - 4 * Math.floor(n / 4), y];      // quadrant 0..3
}
function sin(x) {
  if (x !== x || x === Infinity || x === -Infinity) return NaN;
  if (x > -0.7853981633974483 && x < 0.7853981633974483) return ksin(x);
  const [q, y] = reduce(x);
  if (q === 0) return ksin(y);
  if (q === 1) return kcos(y);
  if (q === 2) return -ksin(y);
  return -kcos(y);
}
function cos(x) {
  if (x !== x || x === Infinity || x === -Infinity) return NaN;
  if (x > -0.7853981633974483 && x < 0.7853981633974483) return kcos(x);
  const [q, y] = reduce(x);
  if (q === 0) return kcos(y);
  if (q === 1) return -ksin(y);
  if (q === 2) return -kcos(y);
  return ksin(y);
}

// ---------------------------------------------------------------- atan / atan2
const ATANHI = [4.63647609000806093515e-01, 7.85398163397448278999e-01,
  9.82793723247329054082e-01, 1.57079632679489655800e+00];
const ATANLO = [2.26987774529616870924e-17, 3.06161699786838301793e-17,
  1.39033110312309984516e-17, 6.12323399573676603587e-17];
const AT = [3.33333333333329318027e-01, -1.99999999998764832476e-01,
  1.42857142725034663711e-01, -1.11111104054623557880e-01,
  9.09088713343650656196e-02, -7.69187620504482999495e-02,
  6.66107313738753120669e-02, -5.83357013379057348645e-02,
  4.97687799461593236017e-02, -3.65315727442169155270e-02,
  1.62858201153657823623e-02];

function atan(x) {
  if (x !== x) return NaN;
  const neg = x < 0;
  let a = neg ? -x : x;
  if (a >= 7.378697629483821e19) return neg ? -(ATANHI[3] + ATANLO[3]) : ATANHI[3] + ATANLO[3];   // 2^66
  let id;
  if (a < 0.4375) {
    if (a < 1.862645149230957e-9) return x;                                   // 2^-29
    id = -1;
  } else if (a < 1.1875) {
    if (a < 0.6875) { id = 0; a = (2 * a - 1) / (2 + a); }
    else { id = 1; a = (a - 1) / (a + 1); }
  } else if (a < 2.4375) { id = 2; a = (a - 1.5) / (1 + 1.5 * a); }
  else { id = 3; a = -1 / a; }
  const xx = id < 0 ? x : a;
  const z = xx * xx, w = z * z;
  const s1 = z * (AT[0] + w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10])))));
  const s2 = w * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * AT[9]))));
  if (id < 0) return xx - xx * (s1 + s2);
  const r = ATANHI[id] - ((xx * (s1 + s2) - ATANLO[id]) - xx);
  return neg ? -r : r;
}
const PI = 3.1415926535897931160e+00, PI_LO = 1.2246467991473531772e-16;
const PI_O_2 = 1.5707963267948965580e+00;
// atan2(y, x) = math.atan(y, x) in Lua 5.3
function atan2(y, x) {
  if (x !== x || y !== y) return NaN;
  if (x === 1) return atan(y);
  const yneg = y < 0 || (y === 0 && 1 / y < 0);
  const xneg = x < 0 || (x === 0 && 1 / x < 0);
  if (y === 0) return xneg ? (yneg ? -PI : PI) : y;
  if (x === 0) return yneg ? -PI_O_2 : PI_O_2;
  const z = atan(Math.abs(y / x));
  if (!xneg) return yneg ? -z : z;
  return yneg ? (z - PI_LO) - PI : PI - (z - PI_LO);
}

// ---------------------------------------------------------------- log / exp
const LN2_HI = 6.93147180369123816490e-01, LN2_LO = 1.90821492927058770002e-10;
const LG1 = 6.666666666666735130e-01, LG2 = 3.999999999940941908e-01,
  LG3 = 2.857142874366239149e-01, LG4 = 2.222219843214978396e-01,
  LG5 = 1.818357216161805012e-01, LG6 = 1.531383769920937332e-01,
  LG7 = 1.479819860511658591e-01;
const SQRT2 = 1.4142135623730951;
const TWO32 = 4294967296;

function log(x) {
  if (x !== x || x < 0) return NaN;
  if (x === 0) return -Infinity;
  if (x === Infinity) return Infinity;
  let k = 0;                                   // x = m * 2^k, m in [1, 2): dividing by powers of two is exact
  while (x >= TWO32) { x /= TWO32; k += 32; }
  while (x >= 2) { x /= 2; k += 1; }
  while (x < 2.3283064365386963e-10) { x *= TWO32; k -= 32; }   // 2^-32
  while (x < 1) { x *= 2; k -= 1; }
  if (x > SQRT2) { x /= 2; k += 1; }
  const f = x - 1;
  const s = f / (2 + f), z = s * s, w = z * z;
  const t1 = w * (LG2 + w * (LG4 + w * LG6));
  const t2 = z * (LG1 + w * (LG3 + w * (LG5 + w * LG7)));
  const R = t2 + t1, hfsq = 0.5 * f * f;
  return k * LN2_HI - ((hfsq - (s * (hfsq + R) + k * LN2_LO)) - f);
}

const INVLN2 = 1.44269504088896338700e+00;
const P1 = 1.66666666666666019037e-01, P2 = -2.77777777770155933842e-03,
  P3 = 6.61375632143793436117e-05, P4 = -1.65339022054652515390e-06,
  P5 = 4.13813679705723846039e-08;
function pow2(k) {                             // 2^k for integer k: exact multiplications only
  let r = 1;
  if (k >= 0) { while (k >= 32) { r *= TWO32; k -= 32; } while (k > 0) { r *= 2; k -= 1; } }
  else { while (k <= -32) { r /= TWO32; k += 32; } while (k < 0) { r /= 2; k += 1; } }
  return r;
}
function exp(x) {
  if (x !== x) return NaN;
  if (x > 709.782712893384) return Infinity;
  if (x < -745.1332191019411) return 0;
  const k = Math.floor(x * INVLN2 + 0.5);
  const hi = x - k * LN2_HI, lo = k * LN2_LO, r = hi - lo;
  const t = r * r;
  const c = r - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
  const y = 1 - ((lo - (r * c) / (2 - c)) - hi);
  if (k < -1000) return y * pow2(k + 1000) * pow2(-1000);   // no intermediate underflow to zero
  return y * pow2(k);
}

// x ^ y as in Lua (C pow), but the same everywhere
function pow(x, y) {
  if (y === 0) return 1;
  if (x !== x || y !== y) return NaN;
  if (Math.floor(y) === y && y >= -64 && y <= 64) {   // integer power: by repeated multiplication
    let n = y < 0 ? -y : y, r = 1;
    for (let i = 0; i < n; i++) r *= x;
    return y < 0 ? 1 / r : r;
  }
  if (x === 0) return y > 0 ? 0 : Infinity;
  if (x < 0) return NaN;
  if (x === 1) return 1;
  return exp(y * log(x));
}

module.exports = { sin, cos, atan, atan2, log, exp, pow };
