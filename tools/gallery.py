#!/usr/bin/env python3
"""Render the seed gallery: build gallery.tex once per seed with LuaLaTeX, rasterize
each page, and write gallery/seeds.png (contact sheet) and gallery/seeds.gif (one frame
per seed).

    python3 tools/gallery.py --seeds 1 2 3 4 5 6 [--dpi 50] [--jobs 2] [--run tools/in-docker]
"""
import argparse, os, shlex, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def build(seed, dpi, run):
    job = f"build/seed-{seed}"
    cmd = shlex.split(run) + ["lualatex", "-interaction=nonstopmode", "-halt-on-error", f"-jobname={job}",
           rf"\def\florilegiumseed{{{seed}}}\input{{gallery.tex}}"]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout[-3000:])
        raise SystemExit(f"seed {seed}: lualatex failed")
    png = os.path.join(ROOT, "build", f"seed-{seed}")
    subprocess.run(["pdftoppm", "-png", "-r", str(dpi), "-singlefile", f"{job}.pdf", png], cwd=ROOT, check=True)
    return seed, png + ".png"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", nargs="+", type=int, default=[1, 2, 3, 4, 5, 6])
    ap.add_argument("--dpi", type=int, default=50)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--run", default="", help="command prefix for lualatex, e.g. tools/in-docker")
    a = ap.parse_args()
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "gallery"), exist_ok=True)
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        results = sorted(ex.map(lambda s: build(s, a.dpi, a.run), a.seeds))
    frames = []
    for seed, path in results:
        im = Image.open(path).convert("RGB")
        d = ImageDraw.Draw(im)
        try:
            font = ImageFont.truetype("DejaVuSans.ttf", max(12, im.width // 30))
        except OSError:
            font = ImageFont.load_default()
        d.text((im.width - 10, im.height - 10), f"seed {seed}", fill=(36, 86, 196), font=font, anchor="rd")
        frames.append(im)
    # contact sheet: 3 columns
    cols = min(3, len(frames)); rows = (len(frames) + cols - 1) // cols
    w, h = frames[0].size
    sheet = Image.new("RGB", (cols * w + (cols + 1) * 8, rows * h + (rows + 1) * 8), (235, 235, 240))
    for i, im in enumerate(frames):
        sheet.paste(im, (8 + (i % cols) * (w + 8), 8 + (i // cols) * (h + 8)))
    sheet.save(os.path.join(ROOT, "gallery", "seeds.png"))
    frames[0].save(os.path.join(ROOT, "gallery", "seeds.gif"), save_all=True, append_images=frames[1:],
                   duration=900, loop=0, optimize=False)
    print("wrote gallery/seeds.png and gallery/seeds.gif for seeds", [s for s, _ in results])

if __name__ == "__main__":
    main()
