# SPDX-License-Identifier: MIT
"""Draws Pesto's brand art: the app icons, the empty-state pictures and the jar.

    python3 design/source/brand-art.py <output dir>            SVGs and 1024 px PNGs, one folder
    python3 design/source/brand-art.py --catalog               Sources/Resources/Assets.xcassets

PNGs are rendered with qlmanage (it honours the drop shadows, but paints on white) and then masked to the icon's
rounded rectangle by mask-icon.swift. Needs macOS and Xcode."""
import json
import os
import subprocess
import sys
import tempfile

C = dict(basil="#2F7A49", basilL="#6DBE85", tint="#529D6E", garlic="#FAF7EE", parm="#F6EFD9", pine="#EBD9B4",
         gold="#C9A227", mortar="#2B2F2A", near="#1F2320", shade="#1F5A36", lift="#3E9160")
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
MONO = "ui-monospace, 'SF Mono', Menlo, monospace"

def page(title, w, h, body, helmet=""):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
{helmet}
</style>
</helmet>
<div style="width: {w}px; height: {h}px; box-sizing: border-box; position: relative; overflow: hidden; font-family: {FONT}; color: {C['mortar']}; background: {C['garlic']}">
{body}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
"""

PATH_P = "M324,272 H446 A108,108 0 0 1 446,488 H412 V592 H324 Z M412,342 H446 A38,38 0 0 1 446,418 H412 Z"
LEAF = "M340,524 A190,190 0 0 1 524,340 A190,190 0 0 1 340,524 Z"
RR = lambda x, y, s, r: (f"M{x+r},{y} H{x+s-r} A{r},{r} 0 0 1 {x+s},{y+r} V{y+s-r} A{r},{r} 0 0 1 {x+s-r},{y+s} "
                         f"H{x+r} A{r},{r} 0 0 1 {x},{y+s-r} V{y+r} A{r},{r} 0 0 1 {x+r},{y} Z")

def icon(pid, g1, g2, front, mid, back, mark, kind="P", mark2=None, extra="", glass=True, ring=None, mono=False, hl=0.55):
    o, card, step, rad = 162, 540, 80, 150
    p = pid
    markpath = PATH_P if kind == "P" else LEAF
    markattr = 'fill-rule="evenodd"' if kind == "P" else ""
    vein = ""
    if kind == "leaf":
        vein = f'<path d="M352,512 L512,352" stroke="{front}" stroke-width="16" stroke-linecap="round" fill="none"/>'
    ringsvg = f'<rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="{ring}" stroke-width="6"/>' if ring else ""
    bgfill = f"url(#{p}g)" if g2 else g1
    return f"""<svg viewBox="0 0 1024 1024" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Pesto icon">
<defs>
<linearGradient id="{p}g" x1="0.2" y1="0" x2="0.75" y2="1"><stop offset="0" stop-color="{g1}"/><stop offset="1" stop-color="{g2 or g1}"/></linearGradient>
<linearGradient id="{p}h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="{hl}"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/></linearGradient>
<filter id="{p}s" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="20" stdDeviation="22" flood-color="#000" flood-opacity="0.35"/></filter>
<filter id="{p}b" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.28"/></filter>
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="{bgfill}"/>
{ringsvg}
{extra}
<g transform="translate(100 100) scale(0.8046)">
<path d="{RR(o+2*step, o+2*step, card, rad)}" fill="{back[0]}" fill-opacity="{back[1]}"/>
<path d="{RR(o+step, o+step, card, rad)}" fill="{mid[0]}" fill-opacity="{mid[1]}" filter="url(#{p}b)"/>
<path d="{RR(o, o, card, rad)}" fill="{front}" filter="url(#{p}s)"/>
<path d="{RR(o, o, card, rad)}" fill="url(#{p}h)"/>
<path d="{markpath}" fill="{mark}" {markattr}/>
{vein}
</g>
</svg>"""

GLOW = ('<defs><radialGradient id="{p}glow" cx="0.78" cy="0.12" r="0.7"><stop offset="0" stop-color="#C9A227" stop-opacity="{o}"/>'
        '<stop offset="1" stop-color="#C9A227" stop-opacity="0"/></radialGradient></defs>'
        '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#{p}glow)"/>')
VEIN = ('<g fill="none" stroke="#8C8676" stroke-linecap="round">'
        '<path d="M140,270 C300,310 380,200 520,330 S760,430 890,330" stroke-width="3" opacity="0.22"/>'
        '<path d="M520,330 C565,400 540,465 605,525" stroke-width="2" opacity="0.18"/>'
        '<path d="M215,885 C330,760 425,825 560,700 S800,640 905,560" stroke-width="2.5" opacity="0.2"/></g>')
CHARCOAL = dict(g1="#3A3F37", g2=C['near'], front=C['garlic'], mid=(C['garlic'], 0.5), back=(C['garlic'], 0.28))

# One rule for every icon: the ground carries the theme, the cards stay garlic glass, the P is the theme's light accent.
# Variant "A" is charcoal Parmesan and marble Mortar; "B" is cream Parmesan and charcoal Mortar (ADR 0013).
VARIANT = "A"
ICONS = {
    "Basil": lambda p: dict(g1=C['lift'], g2=C['shade'], front=C['garlic'], mid=(C['parm'], 0.6), back=(C['parm'], 0.32), mark=C['basil']),
    "Parmesan": lambda p: (dict(CHARCOAL, mark="#7A5F00", extra=GLOW.format(p=p, o=0.65)) if VARIANT == "A" else
                           dict(g1="#FBF5E0", g2="#E6D7A3", front="#FFFFFF", mid=("#C9A227", 0.32), back=("#C9A227", 0.18), mark="#7A5F00",
                                ring="#D9CFAE", hl=0.0, extra=GLOW.format(p=p, o=0.55))),
    "PineNut": lambda p: dict(g1=C['pine'], g2="#D2BA86", front=C['garlic'], mid=("#8A4F16", 0.30), back=("#8A4F16", 0.16), mark="#8A4F16", ring="#CDBB8E", hl=0.0),
    "Mortar": lambda p: (dict(g1="#F4F1E8", g2="#D8D3C4", front="#FFFFFF", mid=("#3F5446", 0.24), back=("#3F5446", 0.12), mark="#3F5446",
                              ring="#C9C4B4", hl=0.0, extra=VEIN) if VARIANT == "A" else dict(CHARCOAL, mark="#3F5446")),
}


def pine(x, y, r, c=C['pine']):
    return f'<ellipse cx="{x}" cy="{y}" rx="13" ry="6" transform="rotate({r} {x} {y})" fill="{c}" stroke="#C9B27E" stroke-width="1.5"/>'
def leaf(cx, cy, size, rot, fill, vein="#2F7A49"):
    s = size
    return (f'<g transform="translate({cx} {cy}) rotate({rot})"><path d="M0,0 A{s},{s} 0 0 1 {s*0.9},{-s*0.9} A{s},{s} 0 0 1 0,0 Z" fill="{fill}"/>'
            f'<path d="M4,-4 L{s*0.82},{-s*0.82}" stroke="{vein}" stroke-width="3" stroke-linecap="round" opacity="0.6"/></g>')
card_svg = lambda x, y, rot, fills: (f'<g transform="rotate({rot} {x+70} {y+90})"><rect x="{x}" y="{y}" width="140" height="180" rx="14" fill="{C["garlic"]}" stroke="#D9CFAE" stroke-width="2"/>'
    f'<rect x="{x+18}" y="{y+22}" width="70" height="8" rx="4" fill="{fills}" opacity="0.9"/><rect x="{x+18}" y="{y+44}" width="100" height="6" rx="3" fill="{C["mortar"]}" opacity="0.16"/>'
    f'<rect x="{x+18}" y="{y+60}" width="88" height="6" rx="3" fill="{C["mortar"]}" opacity="0.16"/><rect x="{x+18}" y="{y+76}" width="96" height="6" rx="3" fill="{C["mortar"]}" opacity="0.16"/></g>')
jar = f"""<svg viewBox="0 0 1200 630" width="1200" height="630" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="A jar of pesto on a shelf with clipboard cards">
<defs>
<radialGradient id="jg1" cx="0.5" cy="0.45" r="0.6"><stop offset="0" stop-color="{C['tint']}" stop-opacity="0.22"/><stop offset="1" stop-color="{C['tint']}" stop-opacity="0"/></radialGradient>
<radialGradient id="jg2" cx="0.9" cy="0.05" r="0.5"><stop offset="0" stop-color="{C['gold']}" stop-opacity="0.22"/><stop offset="1" stop-color="{C['gold']}" stop-opacity="0"/></radialGradient>
<linearGradient id="jp" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{C['lift']}"/><stop offset="1" stop-color="{C['basil']}"/></linearGradient>
<clipPath id="jc"><path d="{RR(470, 210, 260, 56).replace('V', 'V')}"/></clipPath>
<clipPath id="jbody"><rect x="470" y="210" width="260" height="260" rx="56"/></clipPath>
</defs>
<rect width="1200" height="630" fill="{C['parm']}"/>
<rect width="1200" height="630" fill="url(#jg1)"/><rect width="1200" height="630" fill="url(#jg2)"/>
{card_svg(150, 270, -7, C['basil'])}{card_svg(270, 250, 3, C['gold'])}
<rect x="90" y="470" width="1020" height="16" rx="8" fill="#DCC9A0"/><rect x="90" y="486" width="1020" height="6" rx="3" fill="{C['mortar']}" opacity="0.1"/>
<rect x="500" y="170" width="200" height="46" rx="10" fill="{C['garlic']}" fill-opacity="0.75" stroke="#D9CFAE" stroke-width="3"/>
<rect x="470" y="210" width="260" height="260" rx="56" fill="{C['garlic']}" fill-opacity="0.6" stroke="#D9CFAE" stroke-width="3"/>
<g clip-path="url(#jbody)"><path d="M470,296 Q515,280 560,296 T650,296 T730,290 V470 H470 Z" fill="url(#jp)"/>
<path d="M470,296 Q515,280 560,296 T650,296 T730,290" fill="none" stroke="{C['tint']}" stroke-width="4" opacity="0.5"/></g>
<rect x="505" y="322" width="190" height="118" rx="16" fill="{C['garlic']}"/>
{leaf(538, 416, 46, 0, C['basil'])}{leaf(582, 400, 30, 8, C['tint'])}
<rect x="626" y="372" width="56" height="8" rx="4" fill="{C['mortar']}" opacity="0.6"/><rect x="626" y="390" width="40" height="6" rx="3" fill="{C['mortar']}" opacity="0.2"/>
<rect x="490" y="226" width="14" height="224" rx="7" fill="#fff" opacity="0.4"/>
<rect x="488" y="138" width="224" height="40" rx="12" fill="{C['gold']}"/><rect x="488" y="138" width="224" height="12" rx="6" fill="#fff" opacity="0.22"/>
{leaf(820, 470, 120, -35, C['basil'])}{leaf(830, 470, 100, -85, C['tint'])}{leaf(838, 468, 90, 10, C['lift'])}
<path d="M826,470 q-6,-30 6,-60" stroke="{C['basil']}" stroke-width="5" fill="none" stroke-linecap="round"/>
{pine(930, 462, 20)}{pine(965, 466, -12)}{pine(1000, 463, 35)}{pine(905, 468, 5)}{pine(780, 466, -25)}
</svg>"""

SV = lambda inner: f'<svg viewBox="0 0 360 240" width="360" height="240" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Illustration">{inner}</svg>'
cardshape = lambda x, y, w, h, fill=C['garlic'], stroke="#D9CFAE", dash="": f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{stroke}" stroke-width="2" {dash}/>'
shelf = '<rect x="40" y="184" width="280" height="10" rx="5" fill="#DCC9A0"/>'
a1 = SV(shelf + cardshape(120, 70, 120, 114, fill="none", stroke=C['basil'], dash='stroke-dasharray="7 7"') + leaf(176, 150, 40, 0, C['basil']) + pine(260, 180, 15) + pine(285, 181, -20))
a2 = SV(shelf + cardshape(70, 84, 100, 100) + cardshape(120, 70, 100, 114) + '<circle cx="232" cy="110" r="34" fill="none" stroke="'+C['basil']+'" stroke-width="9"/><path d="M257,135 L292,170" stroke="'+C['basil']+'" stroke-width="10" stroke-linecap="round"/>')
a3 = SV(shelf + cardshape(100, 56, 160, 128) + f'<rect x="150" y="96" width="20" height="48" rx="6" fill="{C["basil"]}"/><rect x="190" y="96" width="20" height="48" rx="6" fill="{C["basil"]}"/>')
a4 = SV(shelf + cardshape(100, 56, 160, 128) + f'<path d="M180,78 L222,94 V132 Q222,160 180,176 Q138,160 138,132 V94 Z" fill="{C["basil"]}"/>' + leaf(166, 150, 34, 0, C['garlic'], vein=C['basil']))
a5 = SV(shelf + cardshape(100, 56, 160, 128) + f'<path d="M180,86 L224,160 H136 Z" fill="{C["gold"]}" stroke="{C["gold"]}" stroke-width="8" stroke-linejoin="round"/><rect x="176" y="112" width="8" height="26" rx="4" fill="{C["mortar"]}"/><circle cx="180" cy="148" r="4.5" fill="{C["mortar"]}"/>')
a6 = SV(f'<rect x="40" y="184" width="280" height="10" rx="5" fill="#DCC9A0"/>' + cardshape(70, 100, 70, 84) + cardshape(86, 86, 70, 98)
        + f'<rect x="196" y="96" width="86" height="88" rx="22" fill="{C["garlic"]}" fill-opacity="0.7" stroke="#D9CFAE" stroke-width="2"/><path d="M196,150 Q216,140 239,150 T282,148 V162 Q282,184 260,184 H218 Q196,184 196,162 Z" fill="{C["basil"]}"/><rect x="190" y="82" width="98" height="16" rx="6" fill="{C["gold"]}"/>' + leaf(238, 172, 18, 0, C['garlic']))

STATES = {"NoClips": a1, "NoResults": a2, "Paused": a3, "Blocked": a4, "Unavailable": a5, "Welcome": a6}


def render_png(svg_path, size, out_png, transparent=False):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["qlmanage", "-t", "-s", str(size), "-o", tmp, svg_path], check=True, capture_output=True)
        rendered = os.path.join(tmp, os.path.basename(svg_path) + ".png")
        if transparent:
            mask = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mask-icon.swift")
            subprocess.run(["swift", mask, rendered, out_png], check=True, capture_output=True)
        else:
            os.replace(rendered, out_png)


def icon_svg(name):
    return icon("i" + name, **ICONS[name]("i" + name)).replace('width="100%" height="100%"', 'width="1024" height="1024"')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(text)


def imageset(root, name, filename, vector):
    props = {"preserves-vector-representation": True} if vector else {}
    contents = {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    if props:
        contents["properties"] = props
    write(os.path.join(root, name + ".imageset", "Contents.json"), json.dumps(contents, indent=2) + "\n")
    return os.path.join(root, name + ".imageset", filename)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--catalog":
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Sources", "Resources", "Assets.xcassets")
        for name in ICONS:
            with tempfile.TemporaryDirectory() as tmp:
                svg = os.path.join(tmp, "AppIcon" + name + ".svg")
                write(svg, icon_svg(name))
                render_png(svg, 1024, imageset(root, "AppIcon" + name, "AppIcon" + name + ".png", False), transparent=True)
        for name, art in STATES.items():
            write(imageset(root, "Illustration" + name, "Illustration" + name + ".svg", True), art)
    else:
        out = sys.argv[1]
        for name in ICONS:
            svg = os.path.join(out, "AppIcon" + name + ".svg")
            write(svg, icon_svg(name))
            render_png(svg, 1024, os.path.join(out, "AppIcon" + name + ".png"), transparent=True)
        for name, art in STATES.items():
            write(os.path.join(out, "Illustration" + name + ".svg"), art)
        write(os.path.join(out, "Jar.svg"), jar)


main()
