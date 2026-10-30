# florilegium — handoff notes

Procedurally generated Delft-blue floral page margins for LuaLaTeX. All geometry is
computed in Lua and written as raw PDF path operators; TeX does no arithmetic. Two
documents share one package: an **authored** composition (hand-placed stems, leaves and
branch targets, parameters sampled) and a **grown** one (layout computed by a greedy
space-filling loop). Same primitives, same motif table. No images, no assets.

## Files

| file | what |
|---|---|
| `florilegium.sty` | thin TeX layer: options `authored` (default) / `grown`, colors `ink` and `accent`, `\florilegiumdraw`, `\florilegiumtextend`, the shipout hook. LuaLaTeX only. |
| `florilegium.lua` | glue: page geometry from TeX dimens, colors, page seed, the TikZ transform (`\pgf@pt@aa..bb`, `\pgf@pt@x/y`), primitive dispatch, the header. |
| `ink.lua` | drawing core: mulberry32 rng, 1-D gradient noise/fbm, OKLCH tone ramp, affine transform stack, path building (`smooth` = Catmull-Rom as Béziers, `taper`, `ribbon`, `blade`, `blob`), fill/stroke/clip with ExtGState opacity + multiply, numbered layers, `flush()` into one `pdf_literal` node. |
| `flora.lua` | the primitives: `petal flower lily blossom floret bud bell leaf leaflet stem cyme sprig umbel tendril sparkle rosette hedera ghost`, plus `branch_path`. |
| `grow.lua` | grown composition: regions, grid, stems, leaves at nodes, branch loop, filler, footer tail. Also exports the **motif table** (`M.motifs`) and layer numbers used by `authored.lua`. |
| `authored.lua` | authored composition: the hand-placed "score" (STEMS, LEAVES, BRANCHES, GHOSTS, ACCENTS, FOOT) for A4 with a 68 mm left margin. |
| `florilegium.tex` / `florilegium-grow.tex` | demo documents (authored / grown). Body text = `text-methods.tex` (+ `text-growth.tex` for grown) + `text-sharing.tex`; it describes the code, so **update it when the method changes**. |
| `gallery.tex`, `tools/gallery.py` | one short page per seed → `gallery/seeds.png` + `seeds.gif`. |
| `tools/Dockerfile`, `tools/in-docker` | TeX Live 2023 image; `make RUN=tools/in-docker` when there's no local TeX. |

## Build

```sh
docker build -t florilegium-tex tools     # once, if there is no local TeX
make RUN=tools/in-docker                  # both PDFs, one pass each (~4 s and ~6 s)
make seed-7 RUN=tools/in-docker           # one page for seed 7 -> build/seed-7.pdf
make gallery RUN=tools/in-docker SEEDS="1 2 3 4 5 6"   # ~12 s for six seeds
make preview                              # gallery/preview-*.png from the root PDFs
```

Fixed seed: `lualatex "\def\florilegiumseed{7}\input{florilegium-grow.tex}"`. Any
positive integer works.

Look at output with `pdftoppm -png -r 100 file.pdf page` and read the PNG; for fine detail
use `-r 300` with `-x -y -W -H` crops. Always look before declaring a change good. For a
quick sheet of every primitive, `scratch/` (git-ignored) is the place for test documents.

Bytes per primitive: `tools/in-docker texlua tools/bytes.lua` (stubs out TeX). A flower
is ~70 KB of path operators, a page ~3 MB uncompressed, ~0.7 MB in the PDF.

## Conventions and traps

- **US spelling everywhere** (color, center, gray, meter) — code, comments, docs.
- **Raw literals bypass TikZ transforms.** A primitive called inside a TikZ scope must
  read pgf's matrix itself (`florilegium.lua: sync_transform`). Inside the margin picture
  the transform is just cm→bp from the page's lower-left corner.
- **Lua truncates multiple returns** in the middle of a table constructor:
  `{x0, y0, f(t), x1}` keeps only the first value of `f(t)`. Assign to locals first.
- **Line widths are absolute bp** (we transform points in Lua, not with `cm`). Anything
  that should scale with a motif is a filled shape (`taper`, `ribbon`); `flora.stem`
  switches to a stroke below ~0.7 bp.
- **Opacity/blend** need ExtGState resources: `ink.lua: gs()` registers `/floaNN` and
  `/flomNN` (multiply) through `\pgfutil@addpdfresource@extgs` once per document.
- **Size budget.** Output, not time, is the constraint. Coordinates are printed `%.1f` bp;
  a path used for fill and clip is emitted once (`clip()` then `flood()`); streaks are
  `taper` (2 Béziers); florets below 0.7 mm are a 10-point polygon. Measure before adding
  per-petal detail.
- **Level of detail**: primitives check `ink.unit()` (cm per local unit) and
  `ink.get_lift()` (ghost) and skip specks/veins when small or pale.
- **Determinism**: every primitive takes an rng; layout code draws from `layout` and
  hands primitives `rng.fork()`, so a change inside a primitive does not move the layout.
- **Text end, one pass**: `\florilegiumtextend` records `\pagetotal+\pagedepth` and the
  page number; the shipout hook of that same page reads them, in the same run.
- This container's TeX Live lacks luaotfload's font database for system fonts; the
  documents pin Computer Modern. Harmless to remove on a full install.

## How the growth works (grow.lua)

1. Regions: margin column, a footer band along the bottom (to ~45% of the text width),
   and on the last page the rectangle under the text.
2. Stems: three from a root near the bottom-left corner; x(y) = c + A·fbm(y/λ + φ), blended
   into the root over 4 cm. Tops at the page top (hero flower), 60–72% (lily), 36–48%
   (flower). A spiral scroll at the root; a footer stem to the right. On the last page,
   Bézier arcs from a main stem into the spill, each ending in a flower.
3. Ghosts (1–2 pale flowers, layer 1) get a weak proxy so the growth leaves them some room.
4. Leaves at nodes of every "leafy" stem (alternating, 35–60°, smaller toward the top; the
   footer gets leaflets that thin out), only where `free` allows.
5. Grid (2 mm), `free` = largest disc that fits (proxies count at κ=0.85 of their radius;
   stems are chains of small discs) and `sdist` = distance to the nearest stem point.
   Updates only visit lattice cells near the new disc.
6. Branch loop: cell with the largest `free·U(0.85,1.15)` within REACH (3 cm) of a stem;
   pick a motif by weight `w/(1+count/cap)` (hard caps only for flower, lily, umbel,
   bells); scale so r(s) ≈ 0.95·free; axis = away from the nearest stem point + `upright`
   lean; `flora.branch_path` from that stem point; the branch's points become stem points.
   Stop below SMALLEST (3.6 mm).
7. Filler: holes ≥ 1.7 mm within 7.5 mm of a stem get a leaflet pair, a bud or a floret
   cluster (capped); far holes get at most 6 copper accents; no dust.
8. Footer tail: copper hairline + sparkle. Layers: 1 ghost, 2 stems, 3 leaves, 4 airy,
   5 blooms, 6 accents; a safety clip a little outside the regions.

To add a motif: write the primitive in `flora.lua` (origin at its base or center, axis
+y, takes `rng`), then add a row to `motifs` in `grow.lua` with `r(s)` (proxy radius),
`off(s)` (center back to the origin along the axis), `upright`, `layer`, `w`, `max`,
optionally `hard`/`hang`, and `draw(rng, s)`. `authored.lua` can then place it by name.

## Ideas not done

- Proxies of 2–3 discs for long motifs (leaves, cymes) instead of one disc.
- Read free space on every page (floats, display equations), not just the last.
- Leaf tips that curl over and show a paler underside, as in the reference image.
- A mirrored right-margin variant for two-sided documents.
- Form XObjects for repeated sub-shapes (florets) to cut the PDF size further.
- A density/airiness option (SMALLEST, FILLMIN, caps) exposed in the `.sty`.
