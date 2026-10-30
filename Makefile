LUALATEX = $(RUN) lualatex -interaction=nonstopmode -halt-on-error
SEEDS   ?= 1 2 3 4 5 6
# RUN=tools/in-docker builds inside the florilegium-tex image (see tools/Dockerfile)
RUN     ?=
LUA      = ink.lua flora.lua florilegium.lua

all: florilegium.pdf florilegium-grow.pdf

# authored composition (authored.lua), one pass, about a second a page
florilegium.pdf: florilegium.tex florilegium.sty authored.lua grow.lua $(LUA) text-methods.tex text-sharing.tex
	$(LUALATEX) florilegium.tex

# grown composition (grow.lua), one pass: the end of the text is measured with \pagetotal
florilegium-grow.pdf: florilegium-grow.tex florilegium.sty grow.lua $(LUA) text-methods.tex text-growth.tex text-sharing.tex
	$(LUALATEX) florilegium-grow.tex

# one of every primitive, drawn with \florilegiumdraw
specimen.pdf: specimen.tex florilegium.sty $(LUA)
	$(LUALATEX) specimen.tex

# one page for one seed:  make seed-7  ->  build/seed-7.pdf
seed-%: gallery.tex florilegium.sty grow.lua $(LUA)
	mkdir -p build
	$(LUALATEX) -jobname=build/seed-$* "\def\florilegiumseed{$*}\input{gallery.tex}"

# contact sheet + gif of several seeds (needs python3 + Pillow + pdftoppm)
gallery: gallery.tex florilegium.sty grow.lua $(LUA) tools/gallery.py
	python3 tools/gallery.py --seeds $(SEEDS) --run "$(RUN)"

preview: florilegium.pdf florilegium-grow.pdf
	mkdir -p gallery
	pdftoppm -png -r 60 -f 1 -l 1 -singlefile florilegium.pdf gallery/preview-authored
	pdftoppm -png -r 60 -f 1 -l 1 -singlefile florilegium-grow.pdf gallery/preview-grown

clean:
	rm -rf build *.aux *.log *.out *.synctex.gz

.PHONY: all gallery preview clean
