#!/bin/sh
# CI's tikz jobs: the TikZ library's pure-TikZ side, one family of drawings a job, in
# latex-action's TeX Live (which runs this file as its "compiler"; the workflow names the
# family in TIKZCHECK_FAMILY). Locally, from the repository's root, with pdflatex, lualatex
# and pdftoppm on the path:
#   sh tools/tikzcheck-ci.sh [plants|fern|visitors|tracery|shells]
# With no family it checks all of them in one run, as CI did until each family got a job of
# its own (in one job the runner took over 40 minutes, and every new family made it longer).
# For a family, both at once, so that the cores stay busy while its longest page finishes:
# 1. Its pages of specimen-tikz.tex under pdfLaTeX, each page a run of its own
#    (tools/specimen-page.tex), the first at full priority and the rest niced. A page fails on
#    any TeX error (main memory included: extra_mem_top as specimen-tikz.tex asks), and on the
#    library's warning that pgf's number scanner has changed, since its string-pool patch is
#    then not applied and a long pure-TikZ run under pdfLaTeX fills the pool (pgf 3.1.12 did,
#    board #5114). A leak that would fill the pool only over all the pages in one run does
#    not show here.
# 2. tools/tikzcheck.lua draw <family>, niced: the family's pics drawn in pure TikZ and by the
#    Lua engine and compared, each build in as many runs at once as there are cores.
# A new page of specimen-tikz.tex needs a family below (and a new family a job in
# .github/workflows/build.yml), or every job fails.
# Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
set -eu
family=${1:-${TIKZCHECK_FAMILY:-}}
# the sheet's pages by family (specimen-tikz.tex's header says what each page shows)
sheet=10
case "$family" in
  plants) first=1 last=6 mode=plants ;;
  fern) first=7 last=7 mode=fern ;;
  visitors) first=8 last=8 mode=visitors ;;
  tracery) first=9 last=9 mode=tracery ;;
  shells) first=10 last=10 mode=shells ;;
  "") first=1 last=$sheet mode=quick ;;
  *) echo "FAIL  no family $family: plants, fern, visitors, tracery or shells, or none for all"; exit 2 ;;
esac
pages=$(( $(grep -c '^\\newpage' specimen-tikz.tex) + 1 ))
if [ "$pages" -ne "$sheet" ]; then
  echo "FAIL  specimen-tikz.tex has $pages pages and tools/tikzcheck-ci.sh gives $sheet a family"
  exit 1
fi
export extra_mem_top=20000000
out=build/specimen
rm -rf "$out"
mkdir -p "$out"
t0=$(date +%s)
pids=""
p=$first
while [ "$p" -le "$last" ]; do
  if [ "$p" -eq "$first" ]; then nice=""; else nice="nice -n 5"; fi
  $nice pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$out" -jobname="page-$p" \
    "\\def\\specimenpage{$p}\\input{tools/specimen-page.tex}" >/dev/null 2>&1 &
  pids="$pids $!"
  p=$((p + 1))
done
nice -n 5 texlua tools/tikzcheck.lua draw "$mode" > build/tikzcheck-draw.out 2>&1 &
drawpid=$!
status=0
p=$first
for pid in $pids; do
  log="$out/page-$p.log"
  if ! wait "$pid"; then
    echo "FAIL  page $p of specimen-tikz.tex under pdfLaTeX ($log):"
    grep -A12 '^!' "$log" | head -24
    status=1
  elif grep -q "number scanner is not in a form" "$log"; then
    echo "FAIL  page $p of specimen-tikz.tex: the TikZ library could not patch pgf's number scanner"
    status=1
  else
    echo "ok    page $p of specimen-tikz.tex under pdfLaTeX by $(( $(date +%s) - t0 )) s, $(grep -o '[0-9]* words of memory out of [0-9]*' "$log" | head -1)"
  fi
  p=$((p + 1))
done
echo "      pages $first to $last in $(( $(date +%s) - t0 )) s"
wait "$drawpid" || status=1
cat build/tikzcheck-draw.out
echo "      all in $(( $(date +%s) - t0 )) s"
exit "$status"
