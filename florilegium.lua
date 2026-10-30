-- florilegium.lua -- the TeX-facing side of florilegium.sty: page geometry,
-- colors, seeds, the TikZ transform, and the dispatch of primitives.

local ink = require("ink")
local flora = require("flora")
local M = { ink = ink, flora = flora }

local SP_CM = 2.54 / (72.27 * 65536)          -- cm per scaled point
local function cm(name) return tex.dimen[name] * SP_CM end

-- the page layout, in cm from the lower-left corner of the paper
function M.geometry()
  local inch = 2.54
  local g = {
    pw = cm("paperwidth"), ph = cm("paperheight"),
    textleft = inch + cm("oddsidemargin"),
  }
  g.textright = g.textleft + cm("textwidth")
  g.ytop = g.ph - inch - cm("topmargin") - cm("headheight") - cm("headsep")
  g.ybot = g.ytop - cm("textheight")
  g.colright = g.textleft - 0.4
  g.headrule = g.ytop + cm("headsep") - 0.1
  g.footy = g.ybot - cm("footskip")
  return g
end

-- colors: `ink` sets the hue of the whole ramp, `accent` the copper
function M.colors(ir, ig, ib, ar, ag, ab)
  ink.set_ink(ir, ig, ib)
  ink.set_accent(ar, ag, ab)
end

-- one rng per page; primitives drawn from TeX fork it in call order
local page_rng = ink.rng(1)
function M.seed(page, fixed)
  local s = fixed and (fixed * 7919 + page * 131) or (page * 97 + 1030)
  page_rng = ink.rng(s)
  return s
end

-- the current pgf transformation (TikZ scopes) as an ink transform: local cm -> page bp
local function sync_transform()
  local C = ink.CM
  local bp = 72 / 72.27 / 65536
  ink.set_transform({
    tonumber(token.get_macro("pgf@pt@aa")) * C, tonumber(token.get_macro("pgf@pt@ab")) * C,
    tonumber(token.get_macro("pgf@pt@ba")) * C, tonumber(token.get_macro("pgf@pt@bb")) * C,
    tex.dimen["pgf@pt@x"] * bp, tex.dimen["pgf@pt@y"] * bp })
end

-- \florilegiumdraw{name}{s, opts}: one primitive at the origin of the current TikZ scope
local scaled = { leaf = true, leaflet = true, petal = true }
function M.draw(name, s, o)
  local fn = flora[name]
  if not fn then tex.error("florilegium: unknown primitive '" .. tostring(name) .. "'") return end
  sync_transform()
  local rng = page_rng.fork()
  if name == "ghost" then
    flora.ghost(o and o.lift, function() M.draw_inner(s, o, rng) end)
  elseif scaled[name] then
    ink.scale(s or 1) fn(rng, o)
  else
    fn(rng, s, o)
  end
  ink.flush()
end
-- \florilegiumdraw{ghost}{"flower", {s=1.4}} draws any primitive pale
function M.draw_inner(name, o, rng)
  o = o or {}
  local fn = flora[name]
  if scaled[name] then ink.scale(o.s or 1) fn(rng, o) else fn(rng, o.s or 1, o) end
end

-- the header: a copper ivy leaf whose stem becomes the head rule
function M.head(g)
  ink.set_transform({ ink.CM, 0, 0, ink.CM, 0, 0 })
  ink.push()
  ink.translate(g.colright - 0.55, g.headrule + 0.02)
  local x, y = flora.hedera(page_rng.fork(), 0.36)
  ink.pop()
  local e = g.textright
  ink.moveto(x, y) ink.curveto(x + 1.0, y, x + 1.5, g.headrule, x + 2.5, g.headrule) ink.lineto(e, g.headrule)
  ink.stroke(ink.accent(0), 0.4)
  ink.circle(e, g.headrule, 0.03) ink.fill(ink.accent(0))
  ink.flush()
end

-- the grown composition for this page
function M.grown(seed, spill, spilly)
  local g = M.geometry()
  g.seed, g.spill, g.spilly = seed, spill, spilly
  require("grow").page(g)
  M.head(g)
end

-- the authored composition for this page
function M.authored(seed)
  local g = M.geometry()
  g.seed = seed
  require("authored").page(g)
  M.head(g)
end

return M
