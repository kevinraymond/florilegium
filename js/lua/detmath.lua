-- detmath.lua -- deterministic sin, cos, atan2, log, exp, pow.
-- Copyright (c) 2026 Kevin Raymond; JavaScript port (c) 2026 jfoboss. MIT License: see LICENSE.
-- fdlibm: Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved. Developed at SunSoft, a Sun Microsystems, Inc. business. Permission to use, copy, modify, and distribute this software is freely granted, provided that this notice is preserved.
-- Mirrors detmath.js: the same operations in the same order, so the reference (texlua)
-- and the JS port give the same result bit for bit. See the comment in detmath.js.
-- Always return floats, like the native math.sin and the ^ operator.

local M = {}
local floor = math.floor

local S1, S2, S3 = -1.66666666666666324348e-01, 8.33333333332248946124e-03, -1.98412698298579493134e-04
local S4, S5, S6 = 2.75573137070700676789e-06, -2.50507602534068634195e-08, 1.58969099521155010221e-10
local C1, C2, C3 = 4.16666666666666019037e-02, -1.38888888888741095749e-03, 2.48015872894767294178e-05
local C4, C5, C6 = -2.75573143513906633035e-07, 2.08757232129817482790e-09, -1.13596475577881948265e-11
local INVPIO2 = 6.36619772367581382433e-01
local PIO2_1 = 1.57079632673412561417e+00
local PIO2_1T = 6.07710050650619224932e-11
local INF = 1 / 0

local function ksin(x)
  local z = x * x
  local v = z * x
  local r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
  return x + v * (S1 + z * r)
end
local function kcos(x)
  local z = x * x
  local r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
  return 1.0 - (0.5 * z - z * r)
end
local function reduce(x)
  local n = floor(x * INVPIO2 + 0.5) + 0.0
  local y = (x - n * PIO2_1) - n * PIO2_1T
  return n - 4.0 * floor(n / 4), y
end
function M.sin(x)
  x = x * 1.0
  if x ~= x or x == INF or x == -INF then return 0 / 0 end
  if x > -0.7853981633974483 and x < 0.7853981633974483 then return ksin(x) end
  local q, y = reduce(x)
  if q == 0 then return ksin(y) end
  if q == 1 then return kcos(y) end
  if q == 2 then return -ksin(y) end
  return -kcos(y)
end
function M.cos(x)
  x = x * 1.0
  if x ~= x or x == INF or x == -INF then return 0 / 0 end
  if x > -0.7853981633974483 and x < 0.7853981633974483 then return kcos(x) end
  local q, y = reduce(x)
  if q == 0 then return kcos(y) end
  if q == 1 then return -ksin(y) end
  if q == 2 then return -kcos(y) end
  return ksin(y)
end

local ATANHI = { 4.63647609000806093515e-01, 7.85398163397448278999e-01,
  9.82793723247329054082e-01, 1.57079632679489655800e+00 }
local ATANLO = { 2.26987774529616870924e-17, 3.06161699786838301793e-17,
  1.39033110312309984516e-17, 6.12323399573676603587e-17 }
local AT = { 3.33333333333329318027e-01, -1.99999999998764832476e-01,
  1.42857142725034663711e-01, -1.11111104054623557880e-01,
  9.09088713343650656196e-02, -7.69187620504482999495e-02,
  6.66107313738753120669e-02, -5.83357013379057348645e-02,
  4.97687799461593236017e-02, -3.65315727442169155270e-02,
  1.62858201153657823623e-02 }

function M.atan(x)
  x = x * 1.0
  if x ~= x then return x end
  local neg = x < 0
  local a = neg and -x or x
  if a >= 7.378697629483821e19 then
    if neg then return -(ATANHI[4] + ATANLO[4]) end
    return ATANHI[4] + ATANLO[4]
  end
  local id
  if a < 0.4375 then
    if a < 1.862645149230957e-9 then return x end
    id = -1
  elseif a < 1.1875 then
    if a < 0.6875 then id = 0 a = (2 * a - 1) / (2 + a)
    else id = 1 a = (a - 1) / (a + 1) end
  elseif a < 2.4375 then id = 2 a = (a - 1.5) / (1 + 1.5 * a)
  else id = 3 a = -1 / a end
  local xx = id < 0 and x or a
  local z = xx * xx
  local w = z * z
  local s1 = z * (AT[1] + w * (AT[3] + w * (AT[5] + w * (AT[7] + w * (AT[9] + w * AT[11])))))
  local s2 = w * (AT[2] + w * (AT[4] + w * (AT[6] + w * (AT[8] + w * AT[10]))))
  if id < 0 then return xx - xx * (s1 + s2) end
  local r = ATANHI[id + 1] - ((xx * (s1 + s2) - ATANLO[id + 1]) - xx)
  if neg then return -r end
  return r
end
local PI, PI_LO, PI_O_2 = 3.1415926535897931160e+00, 1.2246467991473531772e-16, 1.5707963267948965580e+00
function M.atan2(y, x)
  y, x = y * 1.0, x * 1.0
  if x ~= x or y ~= y then return 0 / 0 end
  if x == 1 then return M.atan(y) end
  local yneg = y < 0 or (y == 0 and 1 / y < 0)
  local xneg = x < 0 or (x == 0 and 1 / x < 0)
  if y == 0 then
    if xneg then if yneg then return -PI end return PI end
    return y
  end
  if x == 0 then if yneg then return -PI_O_2 end return PI_O_2 end
  local z = M.atan(math.abs(y / x))
  if not xneg then if yneg then return -z end return z end
  if yneg then return (z - PI_LO) - PI end
  return PI - (z - PI_LO)
end

local LN2_HI, LN2_LO = 6.93147180369123816490e-01, 1.90821492927058770002e-10
local LG1, LG2, LG3 = 6.666666666666735130e-01, 3.999999999940941908e-01, 2.857142874366239149e-01
local LG4, LG5, LG6 = 2.222219843214978396e-01, 1.818357216161805012e-01, 1.531383769920937332e-01
local LG7 = 1.479819860511658591e-01
local SQRT2 = 1.4142135623730951
local TWO32 = 4294967296.0

function M.log(x)
  x = x * 1.0
  if x ~= x or x < 0 then return 0 / 0 end
  if x == 0 then return -INF end
  if x == INF then return INF end
  local k = 0.0
  while x >= TWO32 do x = x / TWO32 k = k + 32 end
  while x >= 2 do x = x / 2 k = k + 1 end
  while x < 2.3283064365386963e-10 do x = x * TWO32 k = k - 32 end
  while x < 1 do x = x * 2 k = k - 1 end
  if x > SQRT2 then x = x / 2 k = k + 1 end
  local f = x - 1
  local s = f / (2 + f)
  local z = s * s
  local w = z * z
  local t1 = w * (LG2 + w * (LG4 + w * LG6))
  local t2 = z * (LG1 + w * (LG3 + w * (LG5 + w * LG7)))
  local R = t2 + t1
  local hfsq = 0.5 * f * f
  return k * LN2_HI - ((hfsq - (s * (hfsq + R) + k * LN2_LO)) - f)
end

local INVLN2 = 1.44269504088896338700e+00
local P1, P2, P3 = 1.66666666666666019037e-01, -2.77777777770155933842e-03, 6.61375632143793436117e-05
local P4, P5 = -1.65339022054652515390e-06, 4.13813679705723846039e-08
local function pow2(k)
  local r = 1.0
  if k >= 0 then
    while k >= 32 do r = r * TWO32 k = k - 32 end
    while k > 0 do r = r * 2 k = k - 1 end
  else
    while k <= -32 do r = r / TWO32 k = k + 32 end
    while k < 0 do r = r / 2 k = k + 1 end
  end
  return r
end
function M.exp(x)
  x = x * 1.0
  if x ~= x then return x end
  if x > 709.782712893384 then return INF end
  if x < -745.1332191019411 then return 0.0 end
  local k = floor(x * INVLN2 + 0.5) + 0.0
  local hi = x - k * LN2_HI
  local lo = k * LN2_LO
  local r = hi - lo
  local t = r * r
  local c = r - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
  local y = 1 - ((lo - (r * c) / (2 - c)) - hi)
  if k < -1000 then return y * pow2(k + 1000) * pow2(-1000) end
  return y * pow2(k)
end

function M.pow(x, y)
  x, y = x * 1.0, y * 1.0
  if y == 0 then return 1.0 end
  if x ~= x or y ~= y then return 0 / 0 end
  if floor(y) == y and y >= -64 and y <= 64 then
    local n = y < 0 and -y or y
    local r = 1.0
    for _ = 1, n do r = r * x end
    if y < 0 then return 1 / r end
    return r
  end
  if x == 0 then if y > 0 then return 0.0 end return INF end
  if x < 0 then return 0 / 0 end
  if x == 1 then return 1.0 end
  return M.exp(y * M.log(x))
end

return M
