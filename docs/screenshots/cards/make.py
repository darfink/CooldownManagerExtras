# Builds the labelled screenshot cards in docs/screenshots from raw screenshots.
#   python3 make.py [card names...]
# Each card in cards.json names a source screenshot ("src": the part of the macOS file name after "Screenshot "),
# the rectangles of interface to keep (the game world around them is cut away), and the
# labels. Needs Pillow and Google Chrome (renders the labels). Sources are read from
# $CME_SHOTS (default ~/Pictures/Screenshots).
import json, subprocess, sys, os, tempfile
from PIL import Image, ImageDraw
SHOTS = os.environ.get("CME_SHOTS", os.path.expanduser("~/Pictures/Screenshots"))
SS = os.path.join(SHOTS, "Screenshot %s.png")
CARDS = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(CARDS) + "/"
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
HERE = tempfile.mkdtemp(prefix="cme-cards-")

def cut(spec):
    im = Image.open(SS % spec["src"]).convert("RGBA")
    if "pre" in spec:
        im = im.crop(spec["pre"])
    mask = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(mask)
    for r in spec["keep"]:
        if len(r) == 5:  # [x0, y0, x1, y1, "e"]: an ellipse (round portraits)
            d.ellipse(r[:4], fill=255)
        else:
            d.rectangle(r, fill=255)
    if "fade" in spec:  # fade out toward the bottom: (y_start, y_end)
        y0, y1 = spec["fade"]
        px = mask.load()
        for y in range(y0, im.size[1]):
            f = max(0.0, 1 - (y - y0) / (y1 - y0))
            for x in range(im.size[0]):
                if px[x, y]:
                    px[x, y] = int(px[x, y] * f)
    d = ImageDraw.Draw(mask)
    for r in spec.get("solid", []):  # menus and tooltips: never faded
        d.rectangle(r, fill=255)
    im.putalpha(mask)
    bbox = mask.getbbox()
    im = im.crop(bbox)
    path = os.path.join(HERE, spec["name"] + "_cut.png")
    im.save(path)
    return path, bbox, im.size

def card(spec):
    path, (bx, by, _, _), (w, h) = cut(spec)
    s = spec.get("scale", 1)
    W, H = spec["size"]
    ix, iy = spec["at"]
    def P(x, y):  # source-image coords -> card coords
        return ix + (x - bx) * s, iy + (y - by) * s
    lines, labels = [], []
    for L in spec["labels"]:
        tx, ty = P(*L["to"])
        if "n" in L:  # numbered marker on the shot, legend entry with the same number
            lines.append(f'<circle class="badge" cx="{tx}" cy="{ty}" r="19"/><text x="{tx}" y="{ty + 7}">{L["n"]}</text>')
            lx, ly = L["at"]
            sub = f"<small>{L['sub']}</small>" if L.get("sub") else ""
            labels.append(f'<div class="label legend" style="left:{lx}px;top:{ly}px"><b>{L["n"]}</b>{L["text"]}{sub}</div>')
            continue
        fx, fy = L["from"]
        lines.append(f'<line x1="{fx}" y1="{fy}" x2="{tx}" y2="{ty}"/><circle cx="{tx}" cy="{ty}" r="5"/>')
        lx, ly = L["at"]
        align = L.get("align", "left")
        style = f"left:{lx}px;top:{ly}px" if align == "left" else f"right:{W - lx}px;top:{ly}px;text-align:right"
        sub = f"<small>{L['sub']}</small>" if L.get("sub") else ""
        labels.append(f'<div class="label" style="{style}">{L["text"]}{sub}</div>')
    html = f'''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;background:transparent}}
.card{{position:relative;width:{W}px;height:{H}px;font-family:"Avenir Next","Futura",sans-serif;
 background:radial-gradient(ellipse at 50% 45%,#262b33 0%,#15181d 60%,#0c0e11 100%);border-radius:18px;overflow:hidden}}
.shot{{position:absolute;left:{ix}px;top:{iy}px;width:{w * s}px;filter:drop-shadow(0 10px 30px rgba(0,0,0,.7))}}
.label{{position:absolute;color:#ffd24a;font-weight:700;font-size:30px;line-height:1.1;letter-spacing:.3px;
 text-shadow:0 2px 0 #000,0 0 12px rgba(0,0,0,.9)}}
.label small{{display:block;color:#c9d1dc;font-weight:500;font-size:19px;margin-top:4px}}
svg{{position:absolute;left:0;top:0}}
svg line{{stroke:#ffd24a;stroke-width:2.5;stroke-linecap:round}} svg circle{{fill:#ffd24a}}
svg circle.badge{{stroke:#000;stroke-width:3}}
svg text{{font:700 21px "Avenir Next",sans-serif;fill:#111;text-anchor:middle}}
.legend{{padding-left:52px}}
.legend b{{position:absolute;left:0;top:-1px;width:36px;height:36px;border-radius:50%;background:#ffd24a;color:#111;
 font-size:21px;line-height:36px;text-align:center;text-shadow:none;border:3px solid #000;box-sizing:content-box}}
</style></head><body><div class="card">
<img class="shot" src="{os.path.basename(path)}">
<svg width="{W}" height="{H}">{"".join(lines)}</svg>
{"".join(labels)}
</div></body></html>'''
    hp = os.path.join(HERE, spec["name"] + ".html")
    open(hp, "w").write(html)
    out = OUT + spec["name"] + ".png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--default-background-color=00000000", "--user-data-dir=" + os.path.join(HERE, ".chrome"), "--no-first-run", f"--window-size={W},{H}", f"--screenshot={out}", "file://" + hp],
                   stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL, timeout=90)
    print(out)

specs = json.load(open(os.path.join(CARDS, "cards.json")))
only = sys.argv[1:]
for spec in specs:
    if not only or spec["name"] in only:
        card(spec)
