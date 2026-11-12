-- florilegium-tracery.lua -- Gothic tracery for florilegium: a window drawn from its genome.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- A window of tracery (florilegium-species.lua: M.tsample) drawn with ink, in the local
-- unit of the current transform: the span (the width between the jambs' construction
-- lines) is the unit the genome's lengths are fractions of. Everything is circles and
-- lines struck from a few points, as a mason set them out (the frames report, part B,
-- after Havemann and Fellner 2004): an arch is a chain of arcs, an opening is the
-- chain moved inward by its bar's half-width, and a figure in the head is the largest
-- circle that fits the stone left between the arches, found by a search over its
-- center. The openings are what is drawn: each is washed in the ink and outlined, and
-- the stone between them stays paper, as the page is; a bar that runs through stone
-- (a sub-arch's, a mullion's branch) is drawn by its two edges.

local ink = require("florilegium-ink")
local M = {}
M.version = "2.0.1"                 -- the release; florilegium.lua checks that every file has the same

local sin, cos, atan, acos, sqrt, abs, pi = math.sin, math.cos, math.atan, math.acos, math.sqrt, math.abs, math.pi
local floor, ceil, min, max, huge = math.floor, math.ceil, math.min, math.max, math.huge
local tone = ink.tone

-- ---------------------------------------------------------------- arcs
-- An arc piece: { cx, cy, r, a0, a1, convex }, from angle a0 to a1 (radians), clockwise
-- when a1 < a0. A chain is a list of pieces from the left springing to the apex, the left
-- half of an arch; `convex` says the opening is inside the circle (under an arch), false
-- for the reversed arcs of an ogee, where it is outside.

-- append an arc to ink's path as Béziers of at most a quarter turn each
local function arcto(cx, cy, r, a0, a1, first)
  local n = max(1, ceil(abs(a1 - a0) / (pi / 2) - 1e-9))
  local da = (a1 - a0) / n
  local k = 4 / 3 * math.tan(da / 4)
  local a = a0
  if first then ink.moveto(cx + r * cos(a), cy + r * sin(a)) end
  for _ = 1, n do
    local b = a + da
    local c0, s0, c1, s1 = cos(a), sin(a), cos(b), sin(b)
    ink.curveto(cx + r * (c0 - k * s0), cy + r * (s0 + k * c0), cx + r * (c1 + k * s1), cy + r * (s1 - k * c1),
      cx + r * c1, cy + r * s1)
    a = b
  end
end
local function piece_to(p, first) arcto(p[1], p[2], p[3], p[4], p[5], first) end
local function at(p, a) return p[1] + p[3] * cos(a), p[2] + p[3] * sin(a) end
local function ends(p)
  local x0, y0 = at(p, p[4])
  local x1, y1 = at(p, p[5])
  return x0, y0, x1, y1
end
-- the angle, from the center of a circle, of the upper (or lower) point where it meets
-- the vertical line x; nil if it does not reach it
local function angle_at_x(cx, cy, r, x, lower)
  local dx = x - cx
  if abs(dx) > r then return nil end
  local dy = sqrt(r * r - dx * dx)
  return atan(lower and -dy or dy, dx)
end
-- the same chain, its circles' radii moved so the curve moves `off` toward the opening
-- (convex pieces shrink, concave ones grow); the ends on the jamb line xj and the axis
-- xm are found again, tangent joins keep their angles
local function offset(chain, off, xj, xm, ys)
  local out = {}
  for i, p in ipairs(chain) do
    local r = p[6] and p[3] - off or p[3] + off
    local q = { p[1], p[2], r, p[4], p[5], p[6] }
    if i == 1 then
      if ys and p[2] < ys - 1e-9 and abs(ys - p[2]) < r then
        -- a center below the springing (segmental): the arc starts on the springing line
        q[4] = atan(ys - p[2], -sqrt(r * r - (ys - p[2]) ^ 2))
      else
        q[4] = angle_at_x(p[1], p[2], r, xj, not p[6]) or p[4]
      end
    end
    if i == #chain then q[5] = angle_at_x(p[1], p[2], r, xm, not p[6]) or p[5] end
    out[i] = q
  end
  -- a ring outside a reversed apex (an ogee's): parallel arcs would meet in a spire, or
  -- not meet at all, so the reversed arc is struck again from the ring's inflection,
  -- tangent there, to an apex `off` above the arch's own
  local last, prev = chain[#chain], out[#chain - 1]
  if off < 0 and not last[6] and prev then
    local ix, iy = at(prev, prev[5])
    local ux, uy = cos(prev[5]), sin(prev[5])
    local _, ay = at(last, last[5])
    local dx, dy = xm - ix, ay - off - iy
    local dot = dx * ux + dy * uy
    if dot > 1e-9 then
      local dd = sqrt(dx * dx + dy * dy)
      local t = min(20 * dd, dd * dd / (2 * dot))           -- the TikZ library caps it the same
      local cx, cy = ix + t * ux, iy + t * uy
      local a0, a1 = atan(iy - cy, ix - cx), atan(ay - off - cy, xm - cx)
      local d = a1 - a0
      while d > pi do d = d - 2 * pi end
      while d < -pi do d = d + 2 * pi end
      out[#chain] = { cx, cy, t, a0, a0 + d, false }
    end
  end
  return out
end
-- the right half: the chain mirrored about the axis xm, walked from the apex down
local function mirrored(chain, xm)
  local out = {}
  for i = #chain, 1, -1 do
    local p = chain[i]
    out[#out + 1] = { 2 * xm - p[1], p[2], p[3], pi - p[5], pi - p[4], p[6] }
  end
  return out
end
-- the chain walked the other way, each piece from its end to its start
local function reversed(chain)
  local out = {}
  for i = #chain, 1, -1 do
    local p = chain[i]
    out[#out + 1] = { p[1], p[2], p[3], p[5], p[4], p[6] }
  end
  return out
end
local function apex(chain, xm)
  local p = chain[#chain]
  local _, y = at(p, p[5])
  return xm, y
end

-- ---------------------------------------------------------------- arches
-- the left half of an arch over [xl, xr] springing at ys, as its construction line
local function half_arch(w, xl, xr, ys, kind)
  kind = kind or w.arch
  local s = xr - xl
  local xm = (xl + xr) / 2
  if kind == "round" then
    return { { xm, ys, s / 2, pi, pi / 2, true } }
  elseif kind == "segmental" then
    local R = max(w.excess, 0.52) * s
    local cy = ys - sqrt(R * R - s * s / 4)
    return { { xm, cy, R, angle_at_x(xm, cy, R, xl), pi / 2, true } }
  elseif kind == "fourcentered" then
    -- the four-centered arch: shoulders of radius r1 at the springing, the crown
    -- arcs centered on the axis below them, tangent, meeting at the apex
    local r1 = w.shoulder * s
    local h = w.rise * s
    r1 = min(r1, 0.9 * h)
    local dx = s / 2 - r1
    local R2 = (dx * dx + h * h - r1 * r1) / (2 * (h - r1))
    local c1x = xl + r1
    local c2y = ys + h - R2
    local ux, uy = c1x - xm, ys - c2y
    local d = sqrt(ux * ux + uy * uy)
    ux, uy = ux / d, uy / d
    local ex, ey = xm + R2 * ux, c2y + R2 * uy      -- the tangent point
    local ae = atan(ey - ys, ex - c1x)
    return { { c1x, ys, r1, pi, ae, true }, { xm, c2y, R2, atan(ey - c2y, ex - xm), pi / 2, true } }
  elseif kind == "ogee" then
    -- a pointed arch reversed above its inflection: the lower arcs rise to the angle
    -- the genome gives, then arcs the other way, tangent there, meet at the apex
    local R = w.excess * s
    local cx = xl + R
    local phi = pi - (pi / 2) * w.ogee                -- the inflection, from the lower center
    local ix, iy = cx + R * cos(phi), ys + R * sin(phi)
    local ux, uy = cos(phi), sin(phi)
    local dxi = xm - ix
    local rmin = dxi / (1 - abs(ux))
    local Ru = max(1.4 * rmin, R)
    local cux, cuy = ix + Ru * ux, iy + Ru * uy
    local dx = xm - cux
    local ay = cuy - sqrt(max(0, Ru * Ru - dx * dx))
    return { { cx, ys, R, pi, phi, true }, { cux, cuy, Ru, atan(iy - cuy, ix - cux), atan(ay - cuy, dx), false } }
  elseif kind == "depressed" then
    -- a headpiece's ogee: shoulders as the four-centered arch's, then reversed crowns
    local r1 = w.shoulder * s
    local h = w.rise * s
    local c1x = xl + r1
    -- the shoulders turn 80 degrees, or more (at most 90, where the crown starts level)
    -- until the apex lies above the tangent there: below it no reversed crown reaches it
    local ae, ex, ey, ux, uy, dx, dy, dot
    for turn = 80, 90 do
      ae = pi - math.rad(turn)
      ex, ey = c1x + r1 * cos(ae), ys + r1 * sin(ae)
      ux, uy = cos(ae), sin(ae)
      dx, dy = xm - ex, ys + h - ey
      dot = dx * ux + dy * uy
      if (dx * dx + dy * dy) <= 80 * s * dot then break end
    end
    -- the crown's radius at most forty spans (pgfmath's range in the TikZ library, which
    -- caps it the same); then its end where the circle meets the axis
    local Ru = min(40 * s, (dx * dx + dy * dy) / (2 * dot))
    local cux, cuy = ex + Ru * ux, ey + Ru * uy
    local ae2 = angle_at_x(cux, cuy, Ru, xm, true) or atan(ys + h - cuy, xm - cux)
    return { { c1x, ys, r1, pi, ae, true }, { cux, cuy, Ru, atan(ey - cuy, ex - cux), ae2, false } }
  end
  -- two-centered: drop, equilateral, lancet
  local R = w.excess * s
  local cx = xl + R
  local a1 = atan(sqrt(max(0, R * R - (s / 2 - R) ^ 2)), s / 2 - R)
  return { { cx, ys, R, pi, a1, true } }
end

-- ---------------------------------------------------------------- regions
-- A region is a list of constraints; a point's signed distance to the region is the
-- least of its signed distances to each (positive inside). A constraint is a circle
-- with its inside or its outside, a half-plane, or an arch (a chain and its springing:
-- the inside under the arch, above the springing, or the outside of all that).
local function sd_circle(c, x, y)
  local d = sqrt((x - c.x) ^ 2 + (y - c.y) ^ 2)
  return c.outside and d - c.r or c.r - d
end
-- signed distance to the inside of an arch: within a piece's sector, to that piece;
-- outside every sector, to the nearest corner (the apex or a springing), outside
local function sd_arch(a, x, y)
  local best = huge
  local found = false
  if not a.full then
    a.full = {}
    for _, p in ipairs(a.chain) do a.full[#a.full + 1] = p end
    for _, p in ipairs(mirrored(a.chain, a.xm)) do a.full[#a.full + 1] = p end
  end
  for _, p in ipairs(a.full) do
    local dx, dy = x - p[1], y - p[2]
    local ang = atan(dy, dx)
    local lo, hi = min(p[4], p[5]), max(p[4], p[5])
    if ang < lo - 1e-9 then ang = ang + 2 * pi end
    local inside = ang >= lo - 1e-9 and ang <= hi + 1e-9
    if inside then
      local d = p[3] - sqrt(dx * dx + dy * dy)
      if not p[6] then d = -d end
      best = min(best, d)
      found = true
    end
  end
  if a.ys then best = min(best, y - a.ys) end
  if not found then
    local d = huge
    for _, p in ipairs(a.full) do
      local x0, y0, x1, y1 = ends(p)
      d = min(d, sqrt((x - x0) ^ 2 + (y - y0) ^ 2), sqrt((x - x1) ^ 2 + (y - y1) ^ 2))
    end
    best = min(best, -d)
  end
  return a.outside and -best or best
end
local function sd(region, x, y)
  local best = huge
  for _, c in ipairs(region) do
    local d
    if c.chain then d = sd_arch(c, x, y)
    elseif c.r then d = sd_circle(c, x, y)
    else d = c.nx * (x - c.x) + c.ny * (y - c.y) end        -- a half-plane: inside along the normal
    best = min(best, d)
  end
  return best
end
-- the largest circle inside a region, searched over the box: a coarse grid, then finer
-- ones around the best; a point `axis` (an x) pins the center to it
local function biggest(region, x0, y0, x1, y1, axis)
  local bx, by, br = nil, nil, -huge
  -- a later point replaces the best only by a margin above rounding, so that a head's
  -- two symmetric spots fall to the one scanned first in both engines
  local eps = (x1 - x0) * 1e-5
  local function try(x, y)
    local d = sd(region, x, y)
    if d > br + eps then bx, by, br = x, y, d end
  end
  -- 25 by 25, then three times 9 by 9 at a quarter of the step: under 900 distances, so
  -- that the TikZ library, which runs the same search in pgfmath, can afford it
  local n = 24
  if axis then
    for j = 0, n do try(axis, y0 + (y1 - y0) * j / n) end
  else
    for i = 0, n do for j = 0, n do try(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * j / n) end end
  end
  local sx, sy = (x1 - x0) / n, (y1 - y0) / n
  for _ = 1, 3 do
    local cx, cy = bx, by
    sx, sy = sx / 4, sy / 4
    for i = -4, 4 do
      for j = -4, 4 do
        if not axis or i == 0 then try(cx + i * sx, cy + j * sy) end
      end
    end
  end
  return bx, by, br
end

-- ---------------------------------------------------------------- paths
-- the chain and its mirror as one path from the left springing over the apex to the
-- right springing (appended to ink's path; `first` starts it with a moveto)
local function head_path(chain, xm, first)
  for i, p in ipairs(chain) do piece_to(p, first and i == 1) end
  for _, p in ipairs(mirrored(chain, xm)) do piece_to(p, false) end
end
-- the circle through three points: center and radius
local function circumcircle(ax, ay, bx, by, cx, cy)
  local d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
  if abs(d) < 1e-12 then return nil end
  local a2, b2, c2 = ax * ax + ay * ay, bx * bx + by * by, cx * cx + cy * cy
  local ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
  local uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
  return ux, uy, sqrt((ax - ux) ^ 2 + (ay - uy) ^ 2)
end
-- an arc from (ax, ay) through (bx, by) to (cx, cy) around the circle through them
local function arc_through(ax, ay, bx, by, cx, cy, first)
  local ux, uy, r = circumcircle(ax, ay, bx, by, cx, cy)
  if not ux then
    if first then ink.moveto(ax, ay) end
    ink.lineto(bx, by) ink.lineto(cx, cy)
    return
  end
  local a0, am, a1 = atan(ay - uy, ax - ux), atan(by - uy, bx - ux), atan(cy - uy, cx - ux)
  -- go the way that passes through the middle point
  local function fwd(a, b) local d = b - a while d < 0 do d = d + 2 * pi end return d end
  if fwd(a0, am) < fwd(a0, a1) then arcto(ux, uy, r, a0, a0 + fwd(a0, a1), first)
  else arcto(ux, uy, r, a0, a0 - fwd(a1, a0), first) end
end
-- a point on a chain at parameter v in 0..1 (by angle along the pieces), and the
-- inward normal there (toward the opening)
local function chain_point(chain, v)
  local total = 0
  for _, p in ipairs(chain) do total = total + abs(p[5] - p[4]) end
  local want = v * total
  for _, p in ipairs(chain) do
    local len = abs(p[5] - p[4])
    if want <= len + 1e-12 then
      local a = p[4] + (p[5] - p[4]) * (len > 0 and want / len or 0)
      local x, y = at(p, a)
      local nx, ny = -cos(a), -sin(a)
      if not p[6] then nx, ny = -nx, -ny end
      return x, y, nx, ny
    end
    want = want - len
  end
  local p = chain[#chain]
  local x, y = at(p, p[5])
  return x, y, -cos(p[5]), -sin(p[5])
end
-- the y of an arch (its left chain, mirrored about xm) at x, or nil outside it
local function chain_y(chain, xm, x)
  if x > xm then x = 2 * xm - x end
  for _, p in ipairs(chain) do
    local dx = x - p[1]
    if abs(dx) <= p[3] then
      local dy = sqrt(p[3] * p[3] - dx * dx)
      local y = p[6] and p[2] + dy or p[2] - dy
      local a = atan(y - p[2], dx)
      local lo, hi = min(p[4], p[5]), max(p[4], p[5])
      if a >= lo - 1e-9 and a <= hi + 1e-9 then return y end
    end
  end
  return nil
end
-- the head of an opening with cusps (Havemann and Fellner's foliation): each side of
-- the chain in k + 1 lobes with a cusp between them `depth` into the opening; a lobe
-- is a circle tangent to the arch, at its outer end for the first and last lobes (the
-- springing, the apex) and at its middle for the others, curling in to the cusps
local function cusped_head(chain, xm, cusps, depth, first)
  local k = floor(cusps / 2)
  local n = k + 1
  -- the circle tangent to the chain at parameter vt, through the point (qx, qy)
  local function lobe(ch, vt, qx, qy)
    local tx, ty, nx, ny = chain_point(ch, vt)
    local vx, vy = qx - tx, qy - ty          -- from the tangent point
    -- its center lies along the inward normal at the tangent point, at rho: |q - c| = rho;
    -- the radius at most fifty times the reach (pgfmath's range: the TikZ library caps it the same)
    local dot, dd = vx * nx + vy * ny, sqrt(vx * vx + vy * vy)
    if abs(dot) < dd / 100 then dot = dot < 0 and -dd / 100 or dd / 100 end
    local rho = (dd * dd) / (2 * dot)
    return tx + nx * rho, ty + ny * rho, abs(rho), tx, ty
  end
  local function short(a, b) local d = b - a while d > pi do d = d - 2 * pi end while d < -pi do d = d + 2 * pi end return d end
  local function side(ch, start)
    local x0, y0 = chain_point(ch, 0)
    local x1, y1 = chain_point(ch, 1 / n)
    local d = min(depth, 0.3 * sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2))   -- no deeper than the lobe is wide
    local q = {}
    for i = 0, n do
      local x, y, nx, ny = chain_point(ch, i / n)
      local dd = (i == 0 or i == n) and 0 or d
      q[i] = { x + nx * dd, y + ny * dd }
    end
    for i = 1, n do
      local qa, qb = q[i - 1], q[i]
      if n == 1 then
        -- one lobe a side: tangent at the springing, through the apex
        local cx, cy, r = lobe(ch, 0, qb[1], qb[2])
        local a0, a1 = atan(qa[2] - cy, qa[1] - cx), atan(qb[2] - cy, qb[1] - cx)
        arcto(cx, cy, r, a0, a0 + short(a0, a1), start and i == 1)
      elseif i == 1 then
        local cx, cy, r = lobe(ch, 0, qb[1], qb[2])
        local a0, a1 = atan(qa[2] - cy, qa[1] - cx), atan(qb[2] - cy, qb[1] - cx)
        arcto(cx, cy, r, a0, a0 + short(a0, a1), start and i == 1)
      elseif i == n then
        local cx, cy, r = lobe(ch, 1, qa[1], qa[2])
        local a0, a1 = atan(qa[2] - cy, qa[1] - cx), atan(qb[2] - cy, qb[1] - cx)
        arcto(cx, cy, r, a0, a0 + short(a0, a1), false)
      else
        local cx, cy, r, mx, my = lobe(ch, (i - 0.5) / n, qa[1], qa[2])
        local a0, am, a1 = atan(qa[2] - cy, qa[1] - cx), atan(my - cy, mx - cx), atan(qb[2] - cy, qb[1] - cx)
        local d1, d2 = short(a0, am), short(am, a1)
        arcto(cx, cy, r, a0, a0 + d1, false)
        arcto(cx, cy, r, a0 + d1, a0 + d1 + d2, false)
      end
    end
  end
  side(chain, first)
  side(mirrored(chain, xm), false)
end

-- ---------------------------------------------------------------- the wash
-- an opening: the current path, washed in the ink and outlined. The wash is darker
-- toward the top (sky through glass) and granulated a little; the line is the pen's
local W = {}                               -- the window being drawn: its tone, pen, rng, unit
local function wash(x0, y0, x1, y1)
  local t = W.tone
  ink.clip()
  ink.flood(tone(t + 0.3), x0 - 1, y0 - 1, x1 + 1, y1 + 1)
  local h = y1 - y0
  if h > 0 then
    -- darker toward the top, in six faint bands
    for k = 1, 6 do
      local yk = y0 + h * (0.25 + 0.12 * k)
      ink.poly({ { x0 - 1, yk }, { x1 + 1, yk }, { x1 + 1, y1 + 1 }, { x0 - 1, y1 + 1 } }, true)
      ink.fill(tone(t + 0.05), 0.14, true)
    end
  end
  if W.detail > 0 then
    -- blotches as the library's \flo@vblob draws them (one draw a line, as there)
    local rng = W.rng
    rng.native.use(rng.G)
    local n = max(2, floor((x1 - x0) * (y1 - y0) / (W.cell * W.cell) / 2))
    for _ = 1, min(n, 40) do
      local x, y = rng.range(x0, x1), rng.range(y0, y1)
      local r = W.cell * rng.range(0.5, 1.3)
      local ry = r * rng.range(0.5, 1)
      ink.smooth(rng.native.blob(x, y, r, ry, 0.4, 7), true)
      if rng.chance(0.6) then
        local tq = t + rng.sym(0.06)
        ink.fill(tone(tq), rng.range(0.08, 0.16), true)
      else
        local tq = t + 0.4 + rng.sym(0.06)
        ink.fill(tone(tq), rng.range(0.1, 0.2))
      end
    end
  end
  ink.unclip()
end
-- the outline of the current path
local function outline(heavy)
  ink.stroke(tone(0.08), W.pen * (heavy and 1.6 or 1), 0.9)
end
-- a path drawn twice: filled with the wash, then outlined. `build(first)` appends it
local function opening(build, x0, y0, x1, y1)
  build(true)
  ink.close()
  if rawget(_G, "florilegium_tracery_debug") then texio.write_nl(string.format("OPEN %d box %.3f %.3f %.3f %.3f", W.rng.G.save(), x0, y0, x1, y1)) end
  wash(x0, y0, x1, y1)
  build(true)
  ink.close()
  outline()
end
-- a bar through stone, drawn by its two edges: the path stroked wide in the pen's ink,
-- then as wide as the bar in paper, so bars that cross join cleanly
local function bars(build, halfwidth)
  build()
  ink.stroke(tone(0.08), 2 * halfwidth * W.bp + 2 * W.pen, 0.9)
  build()
  ink.stroke(ink.paper, 2 * halfwidth * W.bp)
end

-- ---------------------------------------------------------------- figures
-- a foiled circle: n lobes inside the circle (cx, cy, r), tangent to it and to each
-- other (foil radius r sin(a/2) / (1 + sin(a/2)), a = 360/n, after Havemann and
-- Fellner); a lobe stands on the top of the axis. Pointed foils: each lobe is two arcs
-- from circles whose centers are moved out along the lines to the tangent feet
local function foiled_path(cx, cy, r, n, pointed, first)
  local a = 2 * pi / n
  local s = sin(a / 2)
  local rf = r * s / (1 + s)
  local d = r - rf
  local phi0 = pi / 2
  local f = pointed and 1.15 or 1
  if pointed then
    -- the points reach past the circle: scale the foils so they just touch it
    local t0x, t0y = d * cos(a / 2) * cos(-a / 2), d * cos(a / 2) * sin(-a / 2)
    local c0x, c0y = t0x + f * (d - t0x), t0y + f * (0 - t0y)
    local hd = abs(c0y)
    local hh = sqrt(max(0, (f * rf) ^ 2 - hd * hd))
    local tip = c0x + hh
    local k = r / tip
    rf, d = rf * k, d * k
  end
  for k = 0, n - 1 do
    local th = phi0 + k * a
    local lx, ly = cx + d * cos(th), cy + d * sin(th)
    local t0x, t0y = cx + d * cos(a / 2) * cos(th - a / 2), cy + d * cos(a / 2) * sin(th - a / 2)
    local t1x, t1y = cx + d * cos(a / 2) * cos(th + a / 2), cy + d * cos(a / 2) * sin(th + a / 2)
    if not pointed then
      local b = pi / 2 + a / 2
      arcto(lx, ly, rf, th - b, th + b, first and k == 0)
    else
      -- two circles through the feet, tangent to the lobe's there, meeting on the lobe's axis
      local c0x, c0y = t0x + f * (lx - t0x), t0y + f * (ly - t0y)
      local c1x, c1y = t1x + f * (lx - t1x), t1y + f * (ly - t1y)
      local rr = f * rf
      -- their upper intersection lies on the ray through th
      local mx, my = (c0x + c1x) / 2, (c0y + c1y) / 2
      local hd = sqrt((c1x - c0x) ^ 2 + (c1y - c0y) ^ 2) / 2
      local hh = sqrt(max(0, rr * rr - hd * hd))
      local px, py = mx + hh * cos(th), my + hh * sin(th)
      local a0 = atan(t0y - c0y, t0x - c0x)
      local ap = atan(py - c0y, px - c0x)
      while ap < a0 do ap = ap + 2 * pi end
      arcto(c0x, c0y, rr, a0, ap, first and k == 0)
      local bp = atan(py - c1y, px - c1x)
      local b1 = atan(t1y - c1y, t1x - c1x)
      while b1 < bp do b1 = b1 + 2 * pi end
      arcto(c1x, c1y, rr, bp, b1, false)
    end
  end
end
-- a dagger standing on the axis: a round head below, a tail of two arcs tangent to it
-- meeting at the tip above (or below, pointing down); mouchette: the tail bent to one side
local function dagger_path(cx, cy, rh, tipx, tipy, bend, first)
  -- the tail's sides: circles through the tip, tangent to the head from outside
  local function side(sign)
    local Rt = rh * (4 + (bend or 0) * sign * 1.5)
    -- a circle of radius Rt through the tip and tangent to the head: its center is on
    -- both the circle of radius Rt about the tip and the one of radius Rt + rh about the head
    local dx, dy = tipx - cx, tipy - cy
    local D = sqrt(dx * dx + dy * dy)
    local r1, r2 = Rt + rh, Rt
    local aa = (r1 * r1 - r2 * r2 + D * D) / (2 * D)
    local hh = sqrt(max(0, r1 * r1 - aa * aa))
    local mx, my = cx + aa * dx / D, cy + aa * dy / D
    local ox, oy = -dy / D, dx / D
    local kx, ky = mx + sign * hh * ox, my + sign * hh * oy
    -- the tangent point on the head is on the line from the head's center to k
    return kx, ky, Rt, cx + rh * (kx - cx) / r1, cy + rh * (ky - cy) / r1
  end
  local k1x, k1y, R1, t1x, t1y = side(1)
  local k2x, k2y, R2, t2x, t2y = side(-1)
  -- from tangent point 1, round the head away from the tip, to tangent point 2
  local a1, a2 = atan(t1y - cy, t1x - cx), atan(t2y - cy, t2x - cx)
  local atip = atan(tipy - cy, tipx - cx)
  -- the head arc avoids the tip's direction
  local function fwd(a, b) local d = b - a while d < 0 do d = d + 2 * pi end return d end
  if fwd(a1, atip) < fwd(a1, a2) then arcto(cx, cy, rh, a1, a1 - fwd(a2, a1), first)
  else arcto(cx, cy, rh, a1, a1 + fwd(a1, a2), first) end
  -- up side 2 to the tip
  local b0, b1 = atan(t2y - k2y, t2x - k2x), atan(tipy - k2y, tipx - k2x)
  local function short(a, b) local d = b - a while d > pi do d = d - 2 * pi end while d < -pi do d = d + 2 * pi end return d end
  arcto(k2x, k2y, R2, b0, b0 + short(b0, b1), false)
  local c0, c1 = atan(tipy - k1y, tipx - k1x), atan(t1y - k1y, t1x - k1x)
  arcto(k1x, k1y, R1, c0, c0 + short(c0, c1), false)
end
-- a spherical triangle (three arcs bowed out, each struck from the opposite corner),
-- scaled to sit in the circle (cx, cy, r), a corner up
local function triangle_path(cx, cy, r, first)
  local R = r / 1.12                          -- the corners' circle: the bowed sides reach a little past it
  local p = {}
  for k = 0, 2 do
    local th = pi / 2 + k * 2 * pi / 3
    p[k + 1] = { cx + R * cos(th), cy + R * sin(th) }
  end
  local side = R * sqrt(3)
  for k = 1, 3 do
    local a, b = p[k], p[k % 3 + 1]
    local o = p[(k + 1) % 3 + 1]              -- the opposite corner is the center
    local a0, a1 = atan(a[2] - o[2], a[1] - o[1]), atan(b[2] - o[2], b[1] - o[1])
    while a1 < a0 do a1 = a1 + 2 * pi end
    if a1 - a0 > pi then a1 = a1 - 2 * pi end
    arcto(o[1], o[2], side, a0, a1, first and k == 1)
  end
end

-- ---------------------------------------------------------------- the window
-- the construction of a window over [xl, xr] with the sill at y0 and the springing at
-- ys; openings drawn, and the bars that run through stone; `b` the bar's half-width,
-- `B` the main arch's. Returns what it placed (for the accent)
-- a head arch over [x0, x1] in the window's manner, flattened step by step (equilateral,
-- drop, round, segmental) until it fits under `limit(x)`, the arch above it
local FLATTER = { { excess = 1, arch = "equilateral" }, { excess = 0.75, arch = "drop" }, { excess = 0.5, arch = "round" },
  { excess = 0.55, arch = "segmental" } }
local function sub_arch(w, x0, x1, ys, limit)
  local xm = (x0 + x1) / 2
  local function fits(chain)
    if not limit then return true end
    for i = 0, 8 do
      local x, y = chain_point(chain, i / 8)
      for _, xx in ipairs({ x, 2 * xm - x }) do
        local ymax = limit(xx)
        if ymax and y > ymax then return false end
      end
    end
    return true
  end
  local first = w
  if w.arch == "none" or w.arch == "fourcentered" or w.arch == "segmental" then first = FLATTER[1] end
  local chain = half_arch(first, x0, x1, ys)
  if fits(chain) then return chain, first.arch == "segmental" end
  for _, f in ipairs(FLATTER) do
    chain = half_arch(f, x0, x1, ys)
    if fits(chain) then return chain, f.arch == "segmental" end
  end
  return chain, true
end
-- one light: its jambs, its own small arch head (cusped), above a sill
local function light(w, x0, x1, y0, ys, b, cusps, depth, limit, bl, br, off, head, rows)
  bl, br, off = bl or b, br or b, off or b
  local xm = (x0 + x1) / 2
  -- transoms (rows > 1): the rows below the top one are plain openings, the head's
  -- row stands on the last transom
  if rows and rows > 1 then
    for k = 0, rows - 2 do
      local by0 = y0 + (ys - y0) * k / rows + (k > 0 and b or 0)
      local by1 = y0 + (ys - y0) * (k + 1) / rows - b
      opening(function() ink.poly({ { x0 + bl, by0 }, { x1 - br, by0 }, { x1 - br, by1 }, { x0 + bl, by1 } }, true) end,
        x0 + bl, by0, x1 - br, by1)
    end
    y0 = y0 + (ys - y0) * (rows - 1) / rows + b
  end
  local chain, flat
  if head then chain, flat = head, false else chain, flat = sub_arch(w, x0, x1, ys, limit) end
  chain = offset(chain, off, x0 + bl, xm, ys)
  if flat then cusps = 0 end                     -- no cusps on a segmental head
  local _, ay = apex(chain, xm)
  local lx0, ly0 = at(chain[1], chain[1][4])
  opening(function(first)
    ink.moveto(x0 + bl, y0)
    ink.lineto(lx0, ly0)
    if cusps > 0 then cusped_head(chain, xm, cusps, depth, false)
    else head_path(chain, xm, false) end
    ink.lineto(x1 - br, y0)
  end, x0 + bl, y0, x1 - br, ay)
  return chain
end
-- a circle's figure in the head: foiled, an oculus, a triangle, a dagger, two
-- mouchettes, a soufflet; (cx, cy, r) is the construction circle, the opening is b in
local function figure(w, kind, cx, cy, r, b, up)
  local ro = r - b
  if ro <= 0 then return end
  local foils = w.foils
  if W.ladder >= 2 and foils > 4 then foils = 4 end
  if kind == "foiled" and foils >= 3 then
    opening(function(first) foiled_path(cx, cy, ro, foils, w.foilshape == "pointed", first) end, cx - ro, cy - ro, cx + ro, cy + ro)
  elseif kind == "soufflet" then
    -- a quatrefoil pointed above and below: drawn as a pointed quatrefoil
    opening(function(first) foiled_path(cx, cy, ro, 4, true, first) end, cx - ro, cy - ro, cx + ro, cy + ro)
  elseif kind == "triangle" then
    opening(function(first) triangle_path(cx, cy, ro, first) end, cx - ro, cy - ro, cx + ro, cy + ro)
    if foils == 3 and W.ladder < 2 then
      local ri = ro * 0.62
      opening(function(first) foiled_path(cx, cy - 0.03 * ro, ri, 3, false, first) end, cx - ri, cy - ri, cx + ri, cy + ri)
    end
  elseif kind == "dagger" then
    local rh = ro * 0.55
    local hy = cy - (ro - rh)
    local tipy = up and up or cy + ro
    opening(function(first) dagger_path(cx, hy, rh, cx, tipy, 0, first) end, cx - rh, hy - rh, cx + rh, tipy)
  elseif kind == "mouchettes" then
    local rh = ro * 0.42
    for side = -1, 1, 2 do
      local hx, hy = cx + side * (ro - rh) * 0.9, cy - (ro - rh) * 0.35
      local tipx, tipy = cx + side * 0.12 * ro, up and up or cy + ro
      opening(function(first) dagger_path(hx, hy, rh, tipx, tipy, side * 0.8, first) end, min(hx, tipx) - rh, hy - rh, max(hx, tipx) + rh, tipy)
    end
  else                                                              -- an oculus
    opening(function(first) ink.circle(cx, cy, ro) end, cx - ro, cy - ro, cx + ro, cy + ro)
  end
end
-- foliage carved in the stone where a figure would go: a sprig of flora's leaflets
-- rising from the foot of the circle (cx, cy, r), one up and one leaning out each side
local function foliage(cx, cy, r)
  local rng = W.rng
  local native = rng.native
  native.use(rng.G)
  native.fresh() native.pen.lift, native.pen.accent = 0, false
  ink.push() ink.translate(cx, cy - 0.85 * r)
  for side = -1, 1, 2 do
    local a = rng.range(30, 45)
    ink.push() ink.rotate(side * a) ink.scale(1.15 * r) native.leaflet({ u = 1.15 * r * W.unit }) ink.pop()
  end
  local a = rng.sym(6)
  ink.push() ink.rotate(a) ink.scale(1.5 * r) native.leaflet({ u = 1.5 * r * W.unit }) ink.pop()
  ink.pop()
end
-- the group of lights [x0, x1] holding n lights under a sub-arch (lvl > 0) or the main
-- arch (lvl 0): the lights, the sub-arches as bars, the figures found in what is left
local function group(w, x0, x1, n, y0, ys, b, lvl, region, placed, B)
  local lw = (x1 - x0) / n
  local cusps = W.ladder >= 1 and 0 or w.cusps
  local xm = (x0 + x1) / 2
  local split = w.split
  local function limit(x)
    local y = chain_y(region.chain, region.xm or xm, x)
    return y and y - 2 * b
  end
  if n == 1 or lvl >= w.depth or w.branch ~= "subarch" then
    -- the lights, each with its own head; the outer ones against the main arch's bar;
    -- one light alone under an arch has that arch for its head
    -- a screen's heads spring below the main arch's springing and rise into its head
    local screen = lvl == 0 and w.branch == "screen" and n > 1
    local flowing = lvl == 0 and w.branch == "flowing" and n > 1
    local ysl = screen and ys - 0.7 * lw or ys
    -- flowing tracery springs from ogee heads
    local wl = flowing and setmetatable({ arch = "ogee", excess = max(w.excess, 0.85), ogee = 0.5 }, { __index = w }) or w
    local rows = (w.transoms or 0) + 1
    local heads = {}
    for i = 0, n - 1 do
      local bl = (lvl == 0 and i == 0) and B or b
      local br = (lvl == 0 and i == n - 1) and B or b
      local off = (lvl == 0 and n == 1) and B or b
      local head = n == 1 and region.chain or nil
      heads[i + 1] = light(wl, x0 + i * lw, x0 + (i + 1) * lw, y0, ysl, b, cusps, w.cuspdepth * lw, n == 1 and nil or limit, bl, br, off, head, rows)
    end
    local reg = { region }
    for i, c in ipairs(heads) do reg[#reg + 1] = { chain = c, ys = ysl, xm = x0 + (i - 0.5) * lw, outside = true } end
    local top = select(2, apex(region.chain, xm))
    -- a screen: a small figure, or the spandrels' trefoil or foliage, in the stone
    -- between each two heads, under the arch
    if screen and (w.figure ~= "none" or w.spandrel ~= "blank") and W.ladder < 3 then
      for i = 1, n - 1 do
        local cx, cy, r = biggest(reg, x0 + (i - 0.5) * lw, ys, x0 + (i + 0.5) * lw, top)
        if r and r > 2.5 * b then
          if w.figure ~= "none" then figure(w, w.figure, cx, cy, r, b)
          elseif w.spandrel == "foliage" then foliage(cx, cy, r)
          else figure({ foils = 3, foilshape = "round" }, "foiled", cx, cy, r, b) end
          placed[#placed + 1] = { cx, cy, r }
          reg[#reg + 1] = { x = cx, y = cy, r = r, outside = true }
        end
      end
    end
    -- flowing tracery: a pair of mouchettes curling up to the apex, then a soufflet,
    -- more mouchettes, a dagger and pointed quatrefoils in what room is left
    if flowing and W.ladder < 2 then
      local wf = setmetatable({ foils = 4, foilshape = "pointed" }, { __index = w })
      for j, kind in ipairs({ "mouchettes", "soufflet", "mouchettes", "dagger", "foiled", "foiled" }) do
        local cx, cy, r = biggest(reg, x0, ys, x1, top, j == 1 and xm or nil)
        if not r or r < 3 * b then break end
        figure(wf, kind, cx, cy, r, b, j == 1 and top - b or nil)
        placed[#placed + 1] = { cx, cy, r }
        reg[#reg + 1] = { x = cx, y = cy, r = r, outside = true }
      end
    end
    return
  end
  -- sub-groups
  local parts = {}
  if split == "binary" then
    if n % 2 == 0 then parts = { { x0, xm, n / 2 }, { xm, x1, n / 2 } }
    else
      local k = (n - 1) / 2
      parts = { { x0, x0 + k * lw, k }, { x0 + k * lw, x0 + (k + 1) * lw, 1 }, { x0 + (k + 1) * lw, x1, k } }
    end
  elseif split == "center" then
    local k = (n - 1) / 2
    if k == 0 then parts = { { x0, x1, 1 } }
    else parts = { { x0, x0 + k * lw, k }, { x0 + k * lw, x0 + (k + 1) * lw, 1 }, { x0 + (k + 1) * lw, x1, k } } end
  else
    for i = 0, n - 1 do parts[#parts + 1] = { x0 + i * lw, x0 + (i + 1) * lw, 1 } end
  end
  local ys1 = ys - w.setdown * (x1 - x0)
  local subs = {}
  for _, part in ipairs(parts) do
    local px0, px1, pn = part[1], part[2], part[3]
    local pxm = (px0 + px1) / 2
    local chain = sub_arch(w, px0, px1, ys1, limit)
    local inner = { chain = chain, ys = ys1, xm = pxm }
    -- the sub-arch as a bar through the stone, its jambs down to the sill, under the lights
    bars(function()
      ink.moveto(px0, y0 + b)
      local sx, sy = at(chain[1], chain[1][4])
      ink.lineto(sx, sy)
      head_path(chain, pxm, false)
      ink.lineto(px1, y0 + b)
    end, b)
    group(w, px0, px1, pn, y0, ys1, b, lvl + 1, inner, placed, B)
    subs[#subs + 1] = { chain = chain, ys = ys1, x0 = px0, x1 = px1, xm = pxm, n = pn }
  end
  -- the figure in the head above this group's sub-arches, inside `region`
  local reg = { region }
  for _, sarch in ipairs(subs) do reg[#reg + 1] = { chain = sarch.chain, ys = sarch.ys, xm = sarch.xm, outside = true } end
  if w.figure ~= "none" and (lvl == 0 or W.ladder == 0) then
    local top = select(2, apex(region.chain, xm))
    local cx, cy, r = biggest(reg, x0, ys1, x1, top, xm)
    if r and r > 2.5 * b then
      local kind = w.figure
      if W.ladder >= 3 then kind = w.figure == "foiled" and "foiled" or "oculus" end
      figure(w, kind, cx, cy, r, b, (kind == "dagger" or kind == "mouchettes") and top - b or nil)
      placed[#placed + 1] = { cx, cy, r }
      reg[#reg + 1] = { x = cx, y = cy, r = r, outside = true }
    end
  end
  -- the spandrels each side: trefoils, daggers or foliage where there is room (lvl 0 only)
  if lvl == 0 and w.spandrel ~= "blank" and W.ladder < 2 and #subs > 1 then
    local top = select(2, apex(region.chain, xm))
    for side = -1, 1, 2 do
      local rx0, rx1 = side < 0 and x0 or xm, side < 0 and xm or x1
      local sreg = { table.unpack(reg) }
      sreg[#sreg + 1] = { x = xm, y = 0, nx = side, ny = 0 }
      local cx, cy, r = biggest(sreg, rx0, ys1, rx1, top)
      if r and r > 3 * b then
        if w.spandrel == "trefoil" then figure({ foils = 3, foilshape = "round" }, "foiled", cx, cy, r, b)
        elseif w.spandrel == "foliage" then foliage(cx, cy, r)
        else figure(w, "dagger", cx, cy, r, b, cy + r + 0.5 * r) end
      end
    end
  end
  return subs
end

-- reticulated tracery: the lights' ogee heads repeated up the head in rows, each row
-- staggered by half a light and springing where the row below reaches its apexes, so
-- that the heads of one row bound the meshes of the next from below; clipped to the head
local function reticulation(x0, x1, n, ys, b, top)
  local lw = (x1 - x0) / n
  local wo = { arch = "ogee", excess = 0.85, ogee = 0.5 }
  local _, h = apex(half_arch(wo, 0, lw, 0), lw / 2)
  local k = 0
  while ys + k * h < top and k < 12 do
    local shift = (k % 2) * lw / 2
    for i = -1, n do
      local cx0 = x0 + i * lw + shift
      if cx0 + lw > x0 and cx0 < x1 then
        bars(function()
          local ch = half_arch(wo, cx0, cx0 + lw, ys + k * h)
          local sx, sy = at(ch[1], ch[1][4])
          ink.moveto(sx, sy)
          head_path(ch, cx0 + lw / 2, false)
        end, b)
      end
    end
    k = k + 1
  end
end
-- Perpendicular panels: every light has a cusped four-centered head reaching the
-- springing, and the mullions run on through the head, which is cut into a row of
-- panels with heads of their own fitted under the arch; the stone is left where the
-- arch leaves a panel too little room
local function panels(w, xl, xr, n, y0, ys, b, B, region)
  local lw = (xr - xl) / n
  local xm = region.xm
  local cusps = W.ladder >= 1 and 0 or w.cusps
  local depth = w.cuspdepth * lw
  local function limit(x)
    local y = chain_y(region.chain, xm, x)
    return y and y - 2 * b
  end
  local rows = (w.transoms or 0) + 1
  local wp = setmetatable({ arch = "fourcentered", rise = w.rise > 0 and w.rise or 0.3, shoulder = w.shoulder > 0 and w.shoulder or 0.18 },
    { __index = w })
  local _, rise = apex(half_arch(wp, 0, lw, 0), lw / 2)
  local ysl = ys - 2 * b - rise
  for i = 0, n - 1 do
    local px0, px1 = xl + i * lw, xl + (i + 1) * lw
    local bl, br = i == 0 and B or b, i == n - 1 and B or b
    light(w, px0, px1, y0, ysl, b, cusps, depth, nil, bl, br, b, half_arch(wp, px0, px1, ysl), rows)
    local lo = min(limit(px0 + bl) or 0, limit(px1 - br) or 0)
    if lo - ys > 0.3 * lw then
      local ysp = max(ys + 0.1 * lw, lo - 0.45 * lw)
      light(w, px0, px1, ys, ysp, b, cusps, depth, limit, bl, br, b)
    end
  end
end
-- the net of Y and intersecting tracery: from each mullion's top two arcs of the main
-- arch's radius, their centers shifted by one light either way, clipped to the head
local function net(w, x0, x1, n, ys, b, R)
  local lw = (x1 - x0) / n
  local xm = (x0 + x1) / 2
  local forks = {}
  if w.branch == "Y" then
    if n % 2 == 0 then forks = { xm } else forks = { xm - lw / 2, xm + lw / 2 } end
  else
    for i = 1, n - 1 do forks[#forks + 1] = x0 + i * lw end
  end
  for _, fx in ipairs(forks) do
    -- rising to the right: center at fx + R, the arc from angle pi upward; and to the left
    bars(function()
      local a1 = angle_at_x(fx + R, ys, R, x1) or pi / 2
      a1 = max(a1, pi / 2)
      arcto(fx + R, ys, R, pi, a1, true)
    end, b)
    bars(function()
      local a1 = angle_at_x(fx - R, ys, R, x0) or pi / 2
      a1 = min(a1, pi / 2)
      arcto(fx - R, ys, R, 0, a1, true)
    end, b)
  end
end

-- the main window: lights and head under the main arch, orders and hood outside
-- ---------------------------------------------------------------- the vine
-- A headpiece's vine twines up a jamb, the strip of stone from x0 to x1 between the
-- sill y0 and the springing ys: a helix seen from the side, its passes behind the
-- stone drawn first (the stone is painted over them), those in front after the
-- jamb's lines, so that it wraps. `side` is -1 for the left jamb, 1 for the right.
-- Returns the foot of the vine, where the margin's branch arrives, and draws
-- flora's leaflets at its turns and a tendril at its tip.
-- the strip of stone painted over the vine's back passes covers an area of the page,
-- so it is the page's white (ink.paper, a hair warmer, would show as a box)
local WHITE = { 1, 1, 1 }
local function vine_passes(x0, x1, y0, ys, side, front)
  local flora = require("florilegium-flora")
  local cm = 1 / W.unit
  -- the loops reach the roll's two edges, a hair past them so the turns read as curves
  local half = (x1 - x0) / 2
  local xc, ao, ai = (x0 + x1) / 2, half + 0.012 * cm, half + 0.012 * cm
  local pitch = 0.5 * cm
  local foot = y0 + 0.08 * cm
  -- the vine starts where its first loop meets the roll's outer edge, in front, so the
  -- margin's branch hands over at the stone; the helix is measured from there
  local th0 = acos(half / ao)
  local turns = max(1, floor((ys - foot - 0.3 * cm) / pitch))
  local total = turns * 2 * pi + pi / 2                 -- ends in front, past the last pass
  local function along(th)
    local c = cos(th)
    return xc + side * (c > 0 and ao or ai) * c, foot + pitch * (th - th0) / (2 * pi)
  end
  -- as wide as the margin's branch arrives (branch_to tapers to 0.45 of 0.05 cm), so
  -- the vine reads as that branch continuing up the jamb; a little thinner at the tip
  local w0, w1 = 0.022 * cm, 0.015 * cm
  local th = th0
  local k = 0
  while th < total - 1e-9 do
    local th1 = min(total, (floor(th / pi + 1e-9) + 1) * pi)   -- passes end where a crossing does
    local isfront = k % 2 == 0
    if isfront == front then
      local pts = {}
      local n = 12
      for i = 0, n do local x, y = along(th + (th1 - th) * i / n) pts[#pts + 1] = { x, y } end
      local u0, u1 = th / total, th1 / total
      flora.stem(pts, w0 + (w1 - w0) * u0, w0 + (w1 - w0) * u1, tone(0.07), 0.95)
      -- a leaflet at the outer turn of each pass in front
      if isfront and k > 0 then
        local lx, ly = along(th)
        local ang = -side * 40 + W.rng.sym(12)           -- up and away from the jamb
        ink.push() ink.translate(lx, ly) ink.rotate(ang)
        if W.leaf then W.leaf(W.rng.fork(), 0.4 * cm)      -- the page's plant's own leaf
        else ink.scale(0.32 * cm) flora.leaflet(W.rng.fork()) end
        ink.pop()
      end
      if th1 >= total - 1e-9 then
        local tx, ty = along(total)
        ink.push() ink.translate(tx, ty) ink.rotate(side * 70)    -- along the vine's last turn
        flora.tendril(W.rng.fork(), 0.12 * cm) ink.pop()
      end
    end
    th, k = th1, k + 1
  end
  local fx, fy = along(th0)
  return fx, fy
end

-- the band of stone between two offsets of the main arch, round the head and down both
-- jambs to the sill (o1 outside o2, both negative outward), as one closed path
local function band(main, o1, o2, xl, xm, y0, ys)
  local A, C = offset(main, o1, xl + o1, xm, ys), offset(main, o2, xl + o2, xm, ys)
  local ax, ay = at(A[1], A[1][4])
  local cx, cy = at(C[1], C[1][4])
  ink.moveto(ax, y0) ink.lineto(ax, ay)
  head_path(A, xm, false)
  ink.lineto(2 * xm - ax, y0) ink.lineto(2 * xm - cx, y0) ink.lineto(2 * xm - cx, cy)
  for _, p in ipairs(reversed(mirrored(C, xm))) do piece_to(p, false) end
  for _, p in ipairs(reversed(C)) do piece_to(p, false) end
  ink.lineto(cx, y0)
  ink.close()
end
-- the moldings painted as stone: a roll from the outermost line (o1) in to o2, washed
-- pale and shaded darker toward both edges, so that it stands off the page as a shaft
local function roll(main, o1, o2, xl, xm, y0, ys)
  local t = W.tone
  band(main, o1, o2, xl, xm, y0, ys) ink.fill(tone(t + 0.62), 0.7)
  local d = (o2 - o1) * 0.3
  band(main, o1, o1 + d, xl, xm, y0, ys) ink.fill(tone(t + 0.3), 0.22, true)
  band(main, o2 - d, o2, xl, xm, y0, ys) ink.fill(tone(t + 0.3), 0.14, true)
end

-- a pier as the same roll, a rectangle shaded toward both edges
local function pier(x0, x1, y0, y1)
  local t = W.tone
  local d = (x1 - x0) * 0.3
  ink.poly({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }, true) ink.fill(tone(t + 0.62), 0.7)
  ink.poly({ { x0, y0 }, { x0 + d, y0 }, { x0 + d, y1 }, { x0, y1 } }, true) ink.fill(tone(t + 0.3), 0.22, true)
  ink.poly({ { x1 - d, y0 }, { x1, y0 }, { x1, y1 }, { x1 - d, y1 } }, true) ink.fill(tone(t + 0.3), 0.14, true)
end

local function window(w, xl, xr, y0, ys, b, B)
  local s = xr - xl
  local xm = (xl + xr) / 2
  local main = half_arch(w, xl, xr, ys, w.kind == "headpiece" and w.arch == "ogee" and "depressed" or nil)
  local inner = offset(main, B, xl + B, xm, ys)
  local _, ay = apex(inner, xm)
  local region = { chain = inner, ys = ys, xm = xm }
  local placed = {}
  local n = max(1, w.lights)
  local lw = s / n
  if w.branch == "Y" or w.branch == "intersecting" or w.branch == "reticulated" then
    -- the head as one opening, the lights below it as rectangles, the bars over them
    local lx0, ly0 = at(inner[1], inner[1][4])
    opening(function(first)
      ink.moveto(xl + B, ys)
      ink.lineto(lx0, ly0)
      head_path(inner, xm, false)
      ink.lineto(xr - B, ys)
    end, xl + B, ys, xr - B, ay)
    -- the lights: rectangles up to the springing (transoms split them)
    local rows = (w.transoms or 0) + 1
    for i = 0, n - 1 do
      local lx, rx = xl + i * lw + b, xl + (i + 1) * lw - b
      if i == 0 then lx = xl + B end
      if i == n - 1 then rx = xr - B end
      for k = 0, rows - 1 do
        local by0 = y0 + (ys - y0) * k / rows + (k > 0 and b or 0)
        local by1 = y0 + (ys - y0) * (k + 1) / rows - (k < rows - 1 and b or 0) + (k == rows - 1 and b or 0)
        opening(function(first) ink.poly({ { lx, by0 }, { rx, by0 }, { rx, by1 }, { lx, by1 } }, true) end, lx, by0, rx, by1)
      end
    end
    -- the mullions through the head, within it
    local R = (w.excess > 0 and w.excess or 1) * s
    ink.moveto(xl + B, ys)
    ink.lineto(lx0, ly0)
    head_path(inner, xm, false)
    ink.lineto(xr - B, ys)
    ink.close()
    ink.clip()
    if w.branch == "reticulated" then reticulation(xl, xr, n, ys, b, ay)
    else net(w, xl, xr, n, ys, b, R) end
    -- the springing: a bar across under the net
    bars(function() ink.moveto(xl, ys) ink.lineto(xr, ys) end, b)
    ink.unclip()
    -- the head's edge again over the bars' ends
    ink.moveto(lx0, ly0)
    head_path(inner, xm, false)
    outline()
  elseif w.branch == "panel" then
    panels(w, xl, xr, n, y0, ys, b, B, region)
  else
    group(w, xl, xr, n, y0, ys, b, 0, region, placed, B)
  end
  -- orders: rings outside the main arch, and the hood mold over them
  local orders = W.ladder >= 2 and 1 or w.orders
  local step = 0.8 * B
  local hood = w.hood ~= "none" and W.ladder < 2
  -- a headpiece's vine: the jamb it twines is painted as stone over its far passes
  local fx, fy
  if W.vine and w.kind == "headpiece" then
    local side = W.vine
    -- the strip is the roll of moldings, not the blank stone up to the first light
    local xo = xl - (B + orders * step + (hood and 0.6 * B or 0))
    local x0, x1 = xo - W.pen / W.bp, xl + 0.5 * B      -- the roll, as painted below
    if side > 0 then x0, x1 = 2 * xm - x1, 2 * xm - x0 end
    fx, fy = vine_passes(x0, x1, y0, ys, side, false)
    local m = 0.04 / W.unit                        -- over the passes' ends past the strip
    ink.poly({ { x0 - m, y0 }, { x1 + m, y0 }, { x1 + m, ys }, { x0 - m, ys } }, true)
    ink.fill(WHITE)                                -- the page's own white, not ink's cream paper
    W.vinestrip = { x0, x1 }
  end
  -- the bundle of moldings as one shaded roll, from the outermost line to half the
  -- frame's width inside the main arch (what the vine twines)
  roll(main, -(B + orders * step + (hood and 0.6 * B or 0)), 0.5 * B, xl, xm, y0, ys)
  for k = 1, orders do
    local off = -(B + k * step)
    local ch = offset(main, off, xl + off, xm, ys)
    local x, y = at(ch[1], ch[1][4])
    ink.moveto(x, y)
    head_path(ch, xm, false)
    ink.stroke(tone(0.12), W.pen * (k == orders and 1.3 or 0.8), 0.85)
    -- the jambs down to the sill
    ink.moveto(x, y) ink.lineto(x, y0)
    ink.moveto(2 * xm - x, y) ink.lineto(2 * xm - x, y0)
    ink.stroke(tone(0.12), W.pen * (k == orders and 1.3 or 0.8), 0.85)
  end
  if hood then
    local hx, hy
    local off = -(B + orders * step + 0.6 * B)
    local ch = offset(main, off, xl + off, xm, ys)
    hx, hy = at(ch[1], ch[1][4])
    ink.moveto(hx, hy)
    head_path(ch, xm, false)
    ink.stroke(tone(0.1), W.pen * 1.6, 0.9)
    if w.hood == "stops" then
      local q = 0.9 * B
      for _, x in ipairs({ hx, 2 * xm - hx }) do
        ink.poly({ { x - q, hy - q }, { x + q, hy - q }, { x + q, hy + q }, { x - q, hy + q } }, true)
        if w.accent == "stops" then ink.fill(ink.accent(-0.1), 0.9) else ink.fill(tone(0.3), 0.8) end
        ink.poly({ { x - q, hy - q }, { x + q, hy - q }, { x + q, hy + q }, { x - q, hy + q } }, true)
        outline()
      end
    end
  end
  -- the sill, over the bars' feet, as wide as the moldings
  local xo = xl - (B + orders * step + (hood and 0.6 * B or 0))
  ink.moveto(xo, y0) ink.lineto(2 * xm - xo, y0)
  ink.stroke(tone(0.1), W.pen * 2, 0.9)
  -- the copper boss at the main figure's center
  if w.accent == "center" and placed[1] then
    local p = placed[1]
    local r = max(0.06 * p[3], 1.2 * b)
    ink.circle(p[1], p[2], r)
    ink.fill(ink.accent(-0.05), 0.95)
  end
  local chtop = offset(main, -(B + orders * step + (hood and 0.6 * B or 0)), xl, xm, ys)
  local _, ty = apex(chtop, xm)
  -- the vine's passes in front of the jamb, over its lines
  if W.vinestrip then
    vine_passes(W.vinestrip[1], W.vinestrip[2], y0, ys, W.vine, true)
    W.vinestrip = nil
  end
  return ty, fx, fy
end

-- a rose: spokes between an eye and the rim, each spoke's light with a round head; a
-- second ring halves them; the eye a foiled circle
local function rose(w, cx, cy, R, b)
  local n = w.spokes
  local ro = R - 1.5 * b
  local re = w.oculus * R
  local rings = W.ladder >= 2 and 1 or w.rings
  local rmid = rings > 1 and (re + 0.55 * (ro - re)) or nil
  local a = 2 * pi / n
  local function sector(r0, r1, k, head)
    local th0, th1 = k * a + pi / 2, (k + 1) * a + pi / 2
    -- the gap for the spoke's bar, as an angle at each radius
    local g0, g1 = b / r0, b / r1
    local p0x, p0y = cx + r0 * cos(th0 + g0), cy + r0 * sin(th0 + g0)
    local p1x, p1y = cx + r0 * cos(th1 - g0), cy + r0 * sin(th1 - g0)
    local q0x, q0y = cx + r1 * cos(th0 + g1), cy + r1 * sin(th0 + g1)
    local q1x, q1y = cx + r1 * cos(th1 - g1), cy + r1 * sin(th1 - g1)
    opening(function(first)
      ink.moveto(p0x, p0y)
      ink.lineto(q0x, q0y)
      if head then
        local thm = (th0 + th1) / 2
        local mx, my = cx + r1 * cos(thm), cy + r1 * sin(thm)
        arc_through(q0x, q0y, mx, my, q1x, q1y, false)
      else
        arcto(cx, cy, r1, th0 + g1, th1 - g1, false)
      end
      ink.lineto(p1x, p1y)
      arcto(cx, cy, r0, th1 - g0, th0 + g0, false)
    end, cx - r1, cy - r1, cx + r1, cy + r1)
  end
  for k = 0, n - 1 do
    if rmid then
      sector(re + b, rmid - b, k, false)
      sector(rmid + b, ro, k, true)
    else
      sector(re + b, ro, k, true)
    end
  end
  -- the eye
  local foils = min(8, max(3, floor(n / 2)))
  if W.ladder >= 2 then foils = min(foils, 4) end
  local rei = re - b
  if rei > 2 * b then
    opening(function(first) foiled_path(cx, cy, rei, foils, false, first) end, cx - rei, cy - rei, cx + rei, cy + rei)
  else
    opening(function(first) ink.circle(cx, cy, max(rei, b)) end, cx - re, cy - re, cx + re, cy + re)
  end
  -- the rim and its orders
  local orders = W.ladder >= 2 and 1 or w.orders
  for k = 0, orders do
    ink.circle(cx, cy, R + k * 1.2 * b)
    ink.stroke(tone(0.1), W.pen * (k == 0 and 1.4 or 0.9), 0.9)
  end
  if w.accent == "center" then
    ink.circle(cx, cy, max(0.25 * rei, b))
    ink.fill(ink.accent(-0.05), 0.95)
  end
end
-- a foil alone: a foiled circle with its rings
local function foil(w, cx, cy, R, b)
  local ro = R - 1.5 * b
  local n = w.foils
  if W.ladder >= 2 and n > 4 then n = 4 end
  opening(function(first) foiled_path(cx, cy, ro, n, w.foilshape == "pointed", first) end, cx - ro, cy - ro, cx + ro, cy + ro)
  local orders = W.ladder >= 2 and 1 or w.orders
  for k = 0, orders - 1 do
    ink.circle(cx, cy, R + k * 1.2 * b)
    ink.stroke(tone(0.1), W.pen * (k == 0 and 1.4 or 0.9), 0.9)
  end
  if w.accent == "center" then
    ink.circle(cx, cy, max(0.1 * ro, b))
    ink.fill(ink.accent(-0.05), 0.95)
  end
end
-- an arcade: n bays side by side, each a window of one light, under a straight molding
local function arcade(w, xl, xr, y0, b, B)
  local n = max(1, w.lights)
  local bw = (xr - xl) / n
  local ys = y0 + w.jamb * bw
  local cusps = W.ladder >= 1 and 0 or w.cusps
  local top = 0
  for i = 0, n - 1 do
    local x0, x1 = xl + i * bw, xl + (i + 1) * bw
    local ch = light(w, x0, x1, y0, ys, b, cusps, w.cuspdepth * bw)
    local _, ay = apex(ch, (x0 + x1) / 2)
    top = max(top, ay)
    -- the bay's arch as a bar: outer edge over the stone
    local outer = offset(half_arch(w, x0, x1, ys), -b, x0 - b, (x0 + x1) / 2)
    local ox, oy = at(outer[1], outer[1][4])
    ink.moveto(ox, oy)
    head_path(outer, (x0 + x1) / 2, false)
    ink.stroke(tone(0.12), W.pen, 0.85)
  end
  -- the vine up the outer pier, behind it first
  local fx, fy
  if W.vine then
    local x0, x1 = xl - B, xl + b
    if W.vine > 0 then x0, x1 = xr - b, xr + B end
    fx, fy = vine_passes(x0, x1, y0, ys, W.vine, false)
    ink.poly({ { x0, y0 }, { x1, y0 }, { x1, ys }, { x0, ys } }, true)
    ink.fill(WHITE)
    W.vinestrip = { x0, x1 }
  end
  -- the molding along the top and the piers' feet
  local y1 = top + 2.5 * B
  -- the outer piers as shaded stone, up to the molding
  pier(xl - B, xl + b, y0, y1 - 1.2 * B)
  pier(xr - b, xr + B, y0, y1 - 1.2 * B)
  ink.moveto(xl - B, y1) ink.lineto(xr + B, y1)
  ink.stroke(tone(0.1), W.pen * 1.6, 0.9)
  ink.moveto(xl - B, y1 - 1.2 * B) ink.lineto(xr + B, y1 - 1.2 * B)
  ink.stroke(tone(0.12), W.pen * 0.8, 0.85)
  ink.moveto(xl - B, y0) ink.lineto(xr + B, y0)
  ink.stroke(tone(0.1), W.pen * 1.3, 0.9)
  -- spandrel trefoils between the bays
  if w.spandrel == "trefoil" and W.ladder < 2 then
    for i = 1, n - 1 do
      local x = xl + i * bw
      local region = { { chain = half_arch(w, x - bw, x, ys), ys = ys, xm = x - bw / 2, outside = true },
        { chain = half_arch(w, x, x + bw, ys), ys = ys, xm = x + bw / 2, outside = true },
        { x = 0, y = y1 - 1.2 * B - b, nx = 0, ny = -1 } }
      local cx, cy, r = biggest(region, x - bw / 2, ys, x + bw / 2, y1, x)
      if r and r > 3 * b then figure({ foils = 3, foilshape = "round" }, "foiled", cx, cy, r, b) end
    end
  end
  if W.vinestrip then
    vine_passes(W.vinestrip[1], W.vinestrip[2], y0, ys, W.vine, true)
    W.vinestrip = nil
  end
  return y1, fx, fy
end

-- ---------------------------------------------------------------- the initial's frame
-- \florilegiuminitialframe{arch} (florilegium-initial.lua): the tile's opening as a cusped
-- arch over [m, S - m] from the base m, its apex at S - m, from a headpiece `w` sampled
-- for the tile (a flat arch). Returns a function that appends the opening's outline
-- (for the glaze, the clip and the line), one that says whether a point lies in the
-- opening (under the arch, the cusps' reach left out), and the springing's height
function M.arch_frame(w, S, m)
  local x0, x1, y0 = m, S - m, m
  local xm = (x0 + x1) / 2
  -- a headpiece's ogee is the depressed one, as window() draws it
  local kind = w.kind == "headpiece" and w.arch == "ogee" and "depressed" or nil
  local _, rise = apex(half_arch(w, x0, x1, 0, kind), xm)
  local ys = S - m - rise
  local main = half_arch(w, x0, x1, ys, kind)
  local cusps = w.cusps
  local depth = w.cuspdepth * (x1 - x0) * 0.5
  local lx, ly = at(main[1], main[1][4])
  local function path()
    ink.moveto(x0, y0) ink.lineto(lx, ly)
    if cusps > 0 then cusped_head(main, xm, cusps, depth, false) else head_path(main, xm, false) end
    ink.lineto(x1, y0) ink.close()
  end
  local function inside(x, y)
    if x < x0 or x > x1 or y < y0 then return false end
    if y <= ys then return true end
    if x > xm then x = 2 * xm - x end
    -- the piece of the arch over x: within its circle for a convex piece, outside otherwise
    for _, p in ipairs(main) do
      local ax, _, bx = ends(p)
      if x >= min(ax, bx) - 1e-9 and x <= max(ax, bx) + 1e-9 then
        local d = sqrt((x - p[1]) ^ 2 + (y - p[2]) ^ 2)
        local under = p[6] and d <= p[3] or (not p[6] and d >= p[3])
        return under and y < S - m - (cusps > 0 and depth or 0)
      end
    end
    return false
  end
  return path, inside, ys
end

-- ---------------------------------------------------------------- entry
-- the drawing's random draws come from pgf's generator (florilegium-pgfmath.lua), seeded
-- as the TikZ library seeds a pic's drawing (\flo@drawseed), and every draw is one of the
-- library's (\flo@range, \flo@sym, \flo@chance), so that both engines wash the same
-- blotches; fork() seeds an ink.rng for flora's parts of the margin's vine, which no pic draws
local function pgfdraws(seed)
  if seed < 1 or seed > 2147483646 then seed = (seed - 1) % 2147483646 + 1 end   -- an ornament's large number
  local G = ink.pgfrng(seed)
  G.step() G.step()
  local native = require("florilegium-native")
  return {
    G = G, native = native,
    range = function(a, b) return a + (b - a) * G.rnd() end,
    sym = function(a) return a * G.rand() end,
    chance = function(p) return G.rnd() * 65536 < floor(p * 65536 + 0.5) end,
    u = G.rnd,
    fork = function() return ink.rng(G.random(1, 2147483646)) end,
  }
end
-- Draw the window `w` (M.tsample's table) with its base at the origin, `width` wide in
-- the local unit (the outermost molding included), `seed` the drawing's (pgf's generator).
-- Returns the drawing's height. The level of detail follows the width of one light
-- on the page: below 8 mm no cusps (ladder 1), below 5 mm plain figures and one order
-- (2), below 3 mm the arch and its main figure alone (3).
-- `vine` (a headpiece's): -1 for a vine up the left jamb, 1 the right, nil none;
-- `leaf(rng, L)`, if given, draws a leaf L units long along +y on the vine instead of
-- flora's leaflet (the margin hands over the nearest plant's).
-- Returns the height and, with a vine, the foot of the vine (local units)
function M.draw(w, seed, width, vine, leaf)
  local unit = ink.unit()                           -- cm per local unit
  W.rng = pgfdraws(seed)
  W.unit = unit
  W.vine = vine
  W.leaf = leaf
  W.tone = w.tone
  W.bp = unit * 72 / 2.54                           -- bp per local unit
  W.pen = max(0.3, min(0.6, 0.016 * width * W.bp))  -- the pen's line, in bp
  W.cell = 0.13 / unit                              -- the wash's blotches, 1.3 mm
  local kind = w.kind
  if kind == "rose" or kind == "foil" then
    local R = width / 2
    local b = max(w.bar, 0.015) * width * 0.6
    local mm = width * unit * 10
    W.ladder = mm < 6 and 3 or mm < 10 and 2 or mm < 16 and 1 or 0
    W.detail = W.ladder < 2 and 1 or 0
    if kind == "rose" then rose(w, 0, R, R - b, b) else foil(w, 0, R, R - b, b) end
    return width
  end
  local n = max(1, w.lights)
  -- the span: the width less the orders and the hood outside the main arch
  local orders = w.orders
  local B = w.border
  local outside = (B + orders * 0.8 * B + (w.hood ~= "none" and 0.6 * B or 0) + 0.9 * B) * min(1, 3 / n)
  local s = width / (1 + 2 * outside)
  local b
  local lw = s / n
  local mm = lw * unit * 10
  W.ladder = mm < 3 and 3 or mm < 5 and 2 or mm < 8 and 1 or 0
  W.detail = W.ladder < 2 and 1 or 0
  -- the bars follow the lights where there are many: a headpiece's are no thicker
  -- than a three-light window's
  local module = min(s, 3 * lw)
  b, B = w.bar * module, w.border * module
  local xl, xr = -s / 2, s / 2
  if kind == "arcade" then return arcade(w, xl, xr, 0, b, B) end
  local ys = w.jamb * s
  if kind == "headpiece" then ys = max(ys, 3 * B) end
  return window(w, xl, xr, 0, ys, b, B)
end

return M
