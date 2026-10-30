-- grow.lua -- the grown composition of florilegium (LuaLaTeX only).
--
-- A plant, not a packing. Everything grows from one root in the bottom-left
-- corner of the page:
--   1. stems: two or three long stems sway up the margin column (their x is a
--      smooth noise of their height, so they cross now and then); the first
--      ends in the largest flower at the top. A footer stem runs from the root
--      along the bottom of the page. On the last page, extra stems wave into
--      the space under the text.
--   2. leaves are hung at the nodes of the stems, alternating sides.
--   3. a greedy loop in the spirit of Wong, Zongker & Salesin, "Computer-
--      Generated Floral Ornament" (SIGGRAPH 1998): take the largest free disc
--      within reach of a stem, choose a motif that fits it, and grow a branch
--      to it from the nearest stem point. The branch leaves its parent along
--      the parent's direction and arrives along the motif's axis, so every
--      flower can be traced back to the root. Branches become stems for later
--      branches. Repeat until only small holes are left.
--   4. small holes get florets, buds and leaflets on short stalks; a few
--      copper accents go along the outer edge; pale ghost flowers sit behind.
-- Proxies (discs) may overlap a little, so leaves tuck under flowers.
-- Everything is deterministic for a given seed.

local ink = require("ink")
local flora = require("flora")
local M = {}

local sqrt, cos, sin, atan, pi, floor, max, min, abs = math.sqrt, math.cos, math.sin, math.atan, math.pi, math.floor, math.max, math.min, math.abs
local rad = pi / 180
local tone = ink.tone
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function lerp(a, b, t) return a + (b - a) * t end
local function smoothstep(a, b, x) local t = math.min(1, math.max(0, (x - a) / (b - a))) return t * t * (3 - 2 * t) end
local function norm(x, y) local L = sqrt(x * x + y * y) if L < 1e-9 then return 0, 1 end return x / L, y / L end
local function deg(x, y) return atan(y, x) / rad end

-- layers, back to front
local L_GHOST, L_STEM, L_LEAF, L_AIRY, L_BLOOM, L_ACCENT = 1, 2, 3, 4, 5, 6

local GRID     = 0.2    -- candidate spacing (cm)
local REACH    = 3.0    -- a motif must be within this distance of a stem
local SMALLEST = 0.36   -- the branch loop stops below this free radius
local FILLMIN  = 0.17   -- the filler stops below this

-- ---------------------------------------------------------------- motifs
-- r(s): proxy radius; off(s): distance from the disc center back to the
-- primitive's origin, along the motif's axis; upright: the axis leans upward
-- (sprays reach for the light); draw(rng, s): the primitive in a frame whose
-- +y is the axis.
local motifs = {
  { name = "flower",  w = 3,   smin = 0.75, smax = 1.3, max = 3, hard = true, layer = L_BLOOM,
    r = function(s) return 1.0 * s end, off = function(s) return 0 end,
    draw = function(rng, s) flora.flower(rng, s) end },
  { name = "lily",    w = 2,   smin = 0.8,  smax = 1.25, max = 2, hard = true, layer = L_BLOOM, upright = 0.4,
    r = function(s) return 0.9 * s end, off = function(s) return 0.15 * s end,
    draw = function(rng, s) flora.lily(rng, s) end },
  { name = "blossoms", w = 3,  smin = 0.55, smax = 0.85, max = 5, layer = L_BLOOM, upright = 0.5,
    r = function(s) return s end, off = function(s) return 0.6 * s end,
    draw = function(rng, s)
      local n = rng.int(2, 4)
      for k = 1, n do
        local a = (k - (n + 1) / 2) * 38 + rng.sym(10)
        local d = s * rng.range(0.45, 0.8) * (k == 1 and 1 or rng.range(0.85, 1.1))
        local x, y = d * sin(a * rad), d * cos(a * rad)
        ink.moveto(0, 0) ink.curveto(0, d * 0.4, x * 0.6, y * 0.7, x, y) ink.stroke(tone(0.1), 0.35)
        ink.push() ink.translate(x, y) flora.blossom(rng, s * rng.range(0.38, 0.5)) ink.pop()
      end
      if rng.chance(0.6) then ink.push() ink.rotate(rng.sym(50)) ink.scale(0.5 * s) flora.bud(rng, 1) ink.pop() end
    end },
  { name = "cyme",    w = 3,   smin = 1.0,  smax = 2.4, max = 6, layer = L_AIRY, upright = 0.6,
    r = function(s) return 0.45 * s end, off = function(s) return 0.5 * s end,
    draw = function(rng, s) flora.cyme(rng, s) end },
  { name = "sprig",   w = 2,   smin = 1.2,  smax = 2.8, max = 4, layer = L_AIRY, upright = 0.8,
    r = function(s) return 0.42 * s end, off = function(s) return 0.5 * s end,
    draw = function(rng, s) flora.sprig(rng, s) end },
  { name = "umbel",   w = 1.5, smin = 0.8,  smax = 1.5, max = 3, hard = true, layer = L_AIRY, upright = 1.0,
    r = function(s) return 0.75 * s end, off = function(s) return 0.6 * s end,
    draw = function(rng, s) flora.umbel(rng, s) end },
  { name = "leaf",    w = 2,   smin = 0.9,  smax = 2.0, max = 8, layer = L_LEAF, upright = 0.2,
    r = function(s) return 0.32 * s end, off = function(s) return 0.5 * s end,
    draw = function(rng, s) ink.scale(s) flora.leaf(rng, { w = rng.range(0.22, 0.3), depth = rng.chance(0.6) and rng.range(0.4, 0.8) or 0 }) end },
  { name = "bud",     w = 1,   smin = 0.45, smax = 0.75, max = 5, layer = L_BLOOM, upright = 0.5,
    r = function(s) return 0.45 * s end, off = function(s) return 0.5 * s end,
    draw = function(rng, s) flora.bud(rng, s) end },
  { name = "bells",   w = 0.7, smin = 0.6,  smax = 0.95, max = 1, hard = true, layer = L_BLOOM, hang = true,
    r = function(s) return 0.62 * s end, off = function(s) return 0 end,
    draw = function(rng, s)
      flora.bell(rng, s)
      ink.moveto(0, 0) ink.curveto(0.15 * s, 0.25 * s, 0.4 * s, 0.25 * s, 0.5 * s, 0.1 * s) ink.stroke(tone(0.1), 0.35)
      ink.push() ink.translate(0.5 * s, 0.1 * s) flora.bell(rng, 0.75 * s) ink.pop()
    end },
  { name = "tendril", w = 0.6, smin = 0.3,  smax = 0.5, max = 4, layer = L_AIRY,
    r = function(s) return 1.0 * s end, off = function(s) return 1.0 * s end,
    draw = function(rng, s) ink.rotate(90) flora.tendril(rng, s) end },
}

M.motifs = {}
for _, m in ipairs(motifs) do M.motifs[m.name] = m end
M.layers = { ghost = L_GHOST, stem = L_STEM, leaf = L_LEAF, airy = L_AIRY, bloom = L_BLOOM, accent = L_ACCENT }

-- ---------------------------------------------------------------- region
-- rects = { {x0,y0,x1,y1}, ... }, a union; shared edges count as open
local function inside(r, x, y) return x > r[1] and x < r[3] and y > r[2] and y < r[4] end
local function border(rects, x, y)
  local best = -1
  for _, r in ipairs(rects) do
    if inside(r, x, y) then
      local d = math.huge
      local edges = { { x - r[1], r[1] - 0.05, y }, { r[3] - x, r[3] + 0.05, y }, { y - r[2], x, r[2] - 0.05 }, { r[4] - y, x, r[4] + 0.05 } }
      for _, e in ipairs(edges) do
        local open = false
        for _, o in ipairs(rects) do if o ~= r and inside(o, e[2], e[3]) then open = true end end
        if not open and e[1] < d then d = e[1] end
      end
      if d > best then best = d end
    end
  end
  return best
end

-- ---------------------------------------------------------------- page
function M.page(g)
  local rng = ink.rng(g.seed * 7919 + 13)
  local layout = rng.fork()                 -- decisions; primitives get their own forks
  ink.set_transform({ ink.CM, 0, 0, ink.CM, 0, 0 })

  -- regions: margin column, footer band, and the space under the text on the last page
  local col = { 0.3, 0.45, g.colright, g.ph - 0.5 }
  local fx1 = g.textleft + (g.textright - g.textleft) * layout.range(0.42, 0.52)
  local foot = { g.colright - 0.01, 0.4, fx1, min(1.75, g.footy - 0.45) }
  local rects = { col, foot }
  local spill
  if g.spill == 1 and (g.spilly - 0.8) - (g.ybot + 0.6) > 2.5 then
    spill = { g.colright - 0.01, g.ybot + 0.6, g.textright - 0.2, g.spilly - 0.8 }
    rects[#rects + 1] = spill
  end

  -- grid on a global lattice, so a disc only has to visit nearby cells
  local gx, gy, free, sdist, lat = {}, {}, {}, {}, {}
  local function key(ix, iy) return ix * 100000 + iy end
  for _, r in ipairs(rects) do
    for ix = floor(r[1] / GRID), floor(r[3] / GRID) do
      for iy = floor(r[2] / GRID), floor(r[4] / GRID) do
        local x, y = (ix + 0.5) * GRID, (iy + 0.5) * GRID
        local k = key(ix, iy)
        if not lat[k] then
          local b = border(rects, x, y)
          if b > 0 then
            local i = #gx + 1
            gx[i], gy[i], free[i], sdist[i] = x, y, b, math.huge
            lat[k] = i
          end
        end
      end
    end
  end
  local maxfree = 0
  for i = 1, #free do if free[i] > maxfree then maxfree = free[i] end end
  local function each_near(x, y, R, fn)
    for ix = floor((x - R) / GRID), floor((x + R) / GRID) do
      for iy = floor((y - R) / GRID), floor((y + R) / GRID) do
        local i = lat[key(ix, iy)]
        if i then fn(i) end
      end
    end
  end
  -- a proxy disc: cells count it at k of its radius (k < 1 lets things overlap)
  local function disc(x, y, r, k)
    k = k or 0.85
    each_near(x, y, r * k + maxfree, function(i)
      local d = dist(gx[i], gy[i], x, y) - k * r
      if d < free[i] then free[i] = d end
    end)
  end
  local function free_at(x, y)
    local i = lat[key(floor(x / GRID), floor(y / GRID))]
    return i and free[i] or -1
  end

  -- stem points: {x, y, tx, ty, w}; a branch may start at any of them
  local spts = {}
  local function add_stem_points(pts, w0, w1, every)
    every = every or 1
    local n = #pts
    for i = 1, n, every do
      local a, b = pts[max(1, i - 1)], pts[min(n, i + 1)]
      local tx, ty = norm(b[1] - a[1], b[2] - a[2])
      local p = pts[i]
      spts[#spts + 1] = { p[1], p[2], tx, ty, lerp(w0, w1, (i - 1) / max(1, n - 1)) }
      each_near(p[1], p[2], REACH, function(j)
        local d = dist(gx[j], gy[j], p[1], p[2])
        if d < sdist[j] then sdist[j] = d end
      end)
    end
  end
  local function nearest_stem(x, y)
    local best, bp = math.huge, nil
    for _, p in ipairs(spts) do
      local d = dist(x, y, p[1], p[2])
      if d < best then best, bp = d, p end
    end
    return bp, best
  end
  local function stem(pts, w0, w1, proxy)
    ink.layer(L_STEM)
    flora.stem(pts, w0, w1)
    for i = 1, #pts, 2 do disc(pts[i][1], pts[i][2], proxy or 0.1, 1) end
  end
  -- draw a primitive at (x,y) with its +y axis at angle `a` (degrees from +x)
  local function place(layer, x, y, a, fn)
    ink.layer(layer)
    ink.push() ink.translate(x, y) ink.rotate(a - 90) fn() ink.pop()
  end

  -- ---------------------------------------------------------- 1. stems
  local root = { layout.range(1.0, 1.6), 0.75 }
  local cx = g.colright * 0.47
  local amp = g.colright * 0.2
  local mains = {}
  local tops = { g.ph - 2.6, g.ph * layout.range(0.6, 0.72), g.ph * layout.range(0.36, 0.48) }
  for k = 1, 3 do
    local f = ink.fbm1(layout, 2)
    local ph, lam = layout.range(0, 10), layout.range(6, 9)
    local x0 = root[1] + (k - 2) * 0.25
    local pts = {}
    local y = root[2]
    while y <= tops[k] do
      local x = cx + amp * f(y / lam + ph) + (k - 2) * 0.35
      x = lerp(x0, x, smoothstep(0, 4, y - root[2]))
      x = max(0.9, min(g.colright - 0.9, x))
      pts[#pts + 1] = { x, y }
      y = y + 0.25
    end
    mains[k] = pts
    local w0 = k == 1 and 0.085 or 0.065
    stem(pts, w0, 0.028)
    add_stem_points(pts, w0, 0.028)
  end
  -- the scroll: the root curls into a spiral at the corner
  do
    local pts = {}
    local turns = layout.range(1.2, 1.6)
    for i = 0, 40 do
      local t = i / 40
      local a = pi * 0.5 + t * turns * 2 * pi
      local r = 0.55 * (1 - 0.85 * t) ^ 1.3
      pts[#pts + 1] = { root[1] - 0.55 + r * cos(a) * -1, root[2] + 0.05 + r * sin(a) }
    end
    stem(pts, 0.06, 0.012)
  end
  -- the footer stem: from the root along the bottom, tapering out to a hairline
  local footpts = {}
  do
    local f = ink.fbm1(layout, 2)
    local ybase = (foot[2] + foot[4]) / 2 - 0.05
    local x = root[1]
    while x <= fx1 - 0.3 do
      local u = smoothstep(root[1], root[1] + 1.5, x)
      local y = lerp(root[2] + 0.1, ybase + 0.22 * f(x / 3.5), u)
      footpts[#footpts + 1] = { x, y }
      x = x + 0.2
    end
    stem(footpts, 0.065, 0.01, 0.06)
    add_stem_points(footpts, 0.065, 0.012)
  end
  -- on the last page, branches arch out of the main stems into the space under
  -- the text, each ending in a flower
  local leafy = { { pts = mains[1], big = true }, { pts = mains[2], big = true }, { pts = mains[3], big = true } }
  local arcs = {}
  if spill then
    local sh = spill[4] - spill[2]
    local nb = max(1, floor(sh / 7))
    for b = 1, nb do
      local y0 = spill[2] + sh * (b - 0.75) / nb
      local src = mains[layout.int(1, 3)]
      local best, bi = math.huge, 1
      for i, p in ipairs(src) do local d = abs(p[2] - y0) if d < best then best, bi = d, i end end
      local s0 = src[bi]
      local w = spill[3] - s0[1]
      local x3 = s0[1] + w * layout.range(0.7, 0.88)
      local y3 = min(spill[4] - 1.4, y0 + sh / nb * layout.range(0.35, 0.6))
      local pts = ink.sample(ink.bezier3(s0[1], s0[2], s0[1] + w * 0.25, s0[2] + layout.range(-0.4, 0.8),
        x3 - w * 0.3, y3 + layout.range(-1.2, -0.3), x3, y3), floor(w / 0.2))
      local f = ink.fbm1(layout, 2)
      for i, p in ipairs(pts) do local u = (i - 1) / (#pts - 1) p[2] = p[2] + 0.35 * f(p[1] / 3) * sin(pi * u) end
      stem(pts, 0.06, 0.025)
      add_stem_points(pts, 0.06, 0.025)
      leafy[#leafy + 1] = { pts = pts, big = true }
      arcs[#arcs + 1] = pts
    end
  end

  -- the header fleuron keeps its spot free
  disc(g.colright - 0.5, g.headrule + 0.1, 0.7, 1)

  -- ---------------------------------------------------------- 2. terminal flowers and ghosts
  local counts = {}
  for _, m in ipairs(motifs) do counts[m.name] = 0 end
  do
    local p, q = mains[1][#mains[1]], mains[1][#mains[1] - 2]
    local hx, hy = norm(p[1] - q[1], p[2] - q[2])
    local s = min(1.75, g.colright * 0.27)
    local fx, fy = p[1] + hx * 0.2, p[2] + hy * 0.2
    place(L_BLOOM, fx, fy, 90, function() flora.flower(rng.fork(), s) end)
    disc(fx, fy, 1.05 * s, 0.85)
    for k = 2, 3 do
      local pts = mains[k]
      local p2, q2 = pts[#pts], pts[#pts - 2]
      local ax, ay = norm(p2[1] - q2[1], p2[2] - q2[2])
      if k == 2 then
        local s2 = layout.range(1.0, 1.2)
        place(L_BLOOM, p2[1] + ax * 0.25 * s2, p2[2] + ay * 0.25 * s2, deg(ax, ay), function() flora.lily(rng.fork(), s2) end)
        disc(p2[1] + ax * 0.3 * s2, p2[2] + ay * 0.3 * s2, 0.95 * s2, 0.85)
        counts.lily = counts.lily + 1
      else
        local s3 = layout.range(0.85, 1.0)
        place(L_BLOOM, p2[1], p2[2], 90, function() flora.flower(rng.fork(), s3) end)
        disc(p2[1], p2[2], s3, 0.85)
        counts.flower = counts.flower + 1
      end
    end
  end
  for _, pts in ipairs(arcs) do
    local p = pts[#pts]
    local s = layout.range(1.0, 1.25)
    place(L_BLOOM, p[1], p[2], 90, function() flora.flower(rng.fork(), s) end)
    disc(p[1], p[2], s, 0.85)
    counts.flower = counts.flower + 1
  end
  -- ghosts: large pale flowers behind, given a little room so they show
  do
    local ng = layout.int(1, 2)
    for k = 1, ng do
      local gxp = g.colright * layout.range(0.35, 0.65)
      local gyp = g.ph * (k == 1 and layout.range(0.15, 0.3) or layout.range(0.45, 0.6))
      local s = layout.range(1.3, 1.6)
      place(L_GHOST, gxp, gyp, 90, function() flora.ghost(0.62, function() flora.flower(rng.fork(), s) end) end)
      disc(gxp, gyp, 0.8 * s, 0.6)
    end
  end

  -- ---------------------------------------------------------- 3. leaves at the nodes
  -- big stems get full leaves, alternating sides, smaller toward the top; the
  -- footer gets leaflets that thin out toward its end
  leafy[#leafy + 1] = { pts = footpts, big = false }
  for _, st in ipairs(leafy) do
    local pts = st.pts
    local s, acc, side = 0, layout.range(0.6, 1.3), layout.chance(0.5) and 1 or -1
    local total = 0
    for i = 2, #pts do total = total + dist(pts[i][1], pts[i][2], pts[i - 1][1], pts[i - 1][2]) end
    for i = 2, #pts - 4 do
      s = s + dist(pts[i][1], pts[i][2], pts[i - 1][1], pts[i - 1][2])
      if s >= acc then
        local u = s / total
        acc = acc + (st.big and layout.range(1.4, 2.2) or lerp(0.55, 1.4, u) * layout.range(0.8, 1.2))
        side = -side
        local tx, ty = norm(pts[i + 1][1] - pts[i - 1][1], pts[i + 1][2] - pts[i - 1][2])
        local a = deg(tx, ty) + side * layout.range(35, 60)
        local ux, uy = cos(a * rad), sin(a * rad)
        local Lf = st.big and lerp(2.4, 1.3, pts[i][2] / g.ph) * layout.range(0.85, 1.1) or lerp(0.95, 0.45, u) * layout.range(0.85, 1.1)
        local ok = false
        for _ = 1, 3 do
          local mx, my = pts[i][1] + ux * Lf * 0.55, pts[i][2] + uy * Lf * 0.55
          if free_at(mx, my) >= 0.24 * Lf then ok = true break end
          Lf = Lf * 0.75
        end
        if ok and Lf > (st.big and 0.7 or 0.3) then
          if st.big then
            local lobed = layout.chance(0.6)
            local bend = side * layout.range(0.05, 0.3)
            place(L_LEAF, pts[i][1], pts[i][2], a, function()
              ink.scale(Lf) flora.leaf(rng.fork(), { w = layout.range(0.22, 0.3), depth = lobed and layout.range(0.4, 0.8) or 0, bend = bend })
            end)
          else
            local bend = -side * layout.range(0.1, 0.3)
            place(L_LEAF, pts[i][1], pts[i][2], a, function() ink.scale(Lf) flora.leaflet(rng.fork(), { bend = bend }) end)
          end
          for _, f in ipairs({ 0.3, 0.55, 0.8 }) do disc(pts[i][1] + ux * Lf * f, pts[i][2] + uy * Lf * f, 0.24 * Lf, 0.85) end
        end
      end
    end
  end

  -- ---------------------------------------------------------- 4. branches to the largest holes
  local area = 0
  for _, r in ipairs(rects) do area = area + (r[3] - r[1]) * (r[4] - r[2]) end
  local af = max(1, area / 175)
  local caps = {}
  for _, m in ipairs(motifs) do caps[m.name] = floor(m.max * af + 0.5) end

  local function branch_to(S, bx, by, ax, ay, w0)
    local pts = flora.branch_path(layout, S[1], S[2], S[3], S[4], bx, by, ax, ay)
    local d = dist(S[1], S[2], bx, by)
    local w = min(S[5] * 0.7, w0)
    stem(pts, w, max(0.012, w * 0.45), 0.07)
    add_stem_points(pts, w, max(0.012, w * 0.45), 2)
    -- a leaflet or two on a longer branch
    if d > 1.0 then
      local nl = d > 2 and 2 or 1
      for j = 1, nl do
        local i = floor(#pts * (0.25 + 0.3 * j / nl))
        local p, q = pts[i], pts[i + 1]
        local a = deg(q[1] - p[1], q[2] - p[2]) + (j % 2 == 0 and 1 or -1) * layout.range(40, 60)
        local ls = layout.range(0.45, 0.75)
        place(L_LEAF, p[1], p[2], a, function() ink.scale(ls) flora.leaflet(rng.fork()) end)
        disc(p[1] + cos(a * rad) * ls * 0.5, p[2] + sin(a * rad) * ls * 0.5, 0.25 * ls, 0.7)
      end
    end
    return pts
  end

  for _ = 1, 400 do
    local best, bi = -1, nil
    for i = 1, #gx do
      if sdist[i] <= REACH then
        local v = free[i] * layout.range(0.85, 1.15)
        if v > best then best, bi = v, i end
      end
    end
    if not bi or free[bi] < SMALLEST then break end
    local f, px, py = free[bi], gx[bi], gy[bi]
    -- statement motifs have a hard cap; the others only lose weight as they repeat
    local elig, wts, wsum = {}, {}, 0
    for _, m in ipairs(motifs) do
      local ok = m.r(m.smin) <= f * 1.05 and (not m.hard or counts[m.name] < caps[m.name])
      if ok then
        local wt = m.w / (1 + counts[m.name] / max(1, caps[m.name]))
        elig[#elig + 1] = m wts[#elig] = wt wsum = wsum + wt
      end
    end
    if #elig == 0 then free[bi] = 0 else
      local pick, acc = elig[#elig], layout.u() * wsum
      for k, m in ipairs(elig) do acc = acc - wts[k] if acc <= 0 then pick = m break end end
      local s = pick.smax
      if pick.r(s) > f * 0.95 then
        local lo, hi = pick.smin, s
        for _ = 1, 20 do local mid = (lo + hi) / 2 if pick.r(mid) > f * 0.95 then hi = mid else lo = mid end end
        s = lo
      end
      local S, sd = nearest_stem(px, py)
      local dx, dy = norm(px - S[1], py - S[2])
      -- the motif's axis: away from the stem, leaning up for the upright kinds
      local ax, ay = norm(dx, dy + (pick.upright or 0))
      local ox, oy = px - ax * pick.off(s), py - ay * pick.off(s)
      if pick.hang then ox, oy = px - dx * 0.2 * s, py + 0.45 * s end
      if dist(ox, oy, S[1], S[2]) > 0.12 then
        branch_to(S, ox, oy, pick.hang and dx or ax, pick.hang and -0.3 or ay, 0.04)
      end
      local a = pick.hang and 90 or deg(ax, ay)
      local srng = rng.fork()
      place(pick.layer, ox, oy, a, function() pick.draw(srng, s) end)
      counts[pick.name] = counts[pick.name] + 1
      disc(px, py, pick.r(s), 0.85)
    end
  end

  -- ---------------------------------------------------------- 5. small holes
  -- only right next to a stem, and not too many: a pair of leaflets at a node,
  -- a bud, or a few florets. Far from any stem, a copper accent or nothing.
  local accents, fills = 0, 0
  local maxfill = floor(28 * af)
  for _ = 1, 600 do
    local best, bi = -1, nil
    for i = 1, #gx do
      local v = free[i] * layout.range(0.85, 1.15)
      if v > best then best, bi = v, i end
    end
    if not bi or free[bi] < FILLMIN then break end
    local f, px, py = free[bi], gx[bi], gy[bi]
    local S, sd = nearest_stem(px, py)
    if sd < 0.75 and fills < maxfill then
      fills = fills + 1
      local dx, dy = norm(px - S[1], py - S[2])
      local ax, ay = norm(dx, dy + 0.4)
      local kind = layout.u()
      if kind < 0.4 then
        -- two leaflets in a V at the stem point
        local base = deg(ax, ay)
        local ls = min(0.75, f * 1.6)
        for k = -1, 1, 2 do
          local a = base + k * layout.range(20, 35)
          place(L_LEAF, S[1], S[2], a, function() ink.scale(ls * layout.range(0.8, 1)) flora.leaflet(rng.fork(), { bend = -k * 0.15 }) end)
        end
      elseif kind < 0.65 then
        local ox, oy = px - ax * f * 0.5, py - ay * f * 0.5
        ink.layer(L_STEM)
        ink.moveto(S[1], S[2]) ink.curveto(S[1] + S[3] * 0.15, S[2] + S[4] * 0.15, ox - ax * 0.1, oy - ay * 0.1, ox, oy)
        ink.stroke(tone(0.1), 0.4)
        place(L_BLOOM, ox, oy, deg(ax, ay), function() flora.bud(rng.fork(), min(0.6, f * 1.7)) end)
      else
        -- a small cluster of florets on hairline stalks
        local n = layout.int(2, 4)
        for k = 1, n do
          local qx, qy = px + layout.sym(f * 0.5), py + layout.sym(f * 0.5)
          ink.layer(L_STEM)
          ink.moveto(S[1], S[2]) ink.curveto(S[1] + S[3] * 0.1, S[2] + S[4] * 0.1, (S[1] + qx) / 2, (S[2] + qy) / 2 + 0.05, qx, qy)
          ink.stroke(tone(0.12), 0.25, 0.9)
          place(L_BLOOM, qx, qy, 90, function() flora.floret(rng.fork(), min(0.11, f * 0.6) * layout.range(0.8, 1.1)) end)
        end
      end
    elseif sd >= 0.75 and accents < 6 and f > 0.22 and px < g.colright then
      accents = accents + 1
      if layout.chance(0.6) then
        place(L_ACCENT, px, py, 90, function() flora.sparkle(rng.fork(), 0.13) end)
      else
        place(L_ACCENT, px, py, 90, function() flora.rosette(rng.fork(), 0.12) end)
      end
    end
    disc(px, py, max(f, 0.3), 1)
  end

  -- ---------------------------------------------------------- 6. the footer's tail
  do
    local e = footpts[#footpts]
    local x2 = e[1] + layout.range(1.6, 2.2)
    ink.layer(L_ACCENT)
    ink.moveto(e[1], e[2]) ink.curveto(e[1] + 0.6, e[2] + 0.05, x2 - 0.6, e[2] - 0.05, x2, e[2])
    ink.stroke(ink.accent(0), 0.3, 0.8)
    place(L_ACCENT, x2 + 0.18, e[2], 90, function() flora.sparkle(rng.fork(), 0.12, { rays = false }) end)
    ink.circle(x2 + 0.45, e[2], 0.025) ink.fill(ink.accent(0))
  end

  -- assemble: a safety clip a little outside the regions, then the layers
  ink.layer(0)
  for _, r in ipairs(rects) do
    ink.poly({ { r[1] - 0.25, r[2] - 0.3 }, { r[3] + (r == col and 0.25 or 0.3), r[2] - 0.3 }, { r[3] + (r == col and 0.25 or 0.3), r[4] + 0.3 }, { r[1] - 0.25, r[4] + 0.3 } }, true)
  end
  ink.clip()
  ink.layer(99)
  ink.unclip()
  local bytes = ink.flush()
  if texio then
    local n = 0
    for _, v in pairs(counts) do n = n + v end
    texio.write_nl(string.format("florilegium: grew %d cells, %d motifs, %d stem points, %.0f KB", #gx, n, #spts, bytes / 1024))
  end
end

return M
