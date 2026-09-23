#!/usr/bin/env python3
"""Rectangular lockup stickers for parlor.sh: the mark, then "parlor.sh" with ".sh" dimmed.

Geometry follows brand/BRAND.md and the site's h1: the mark is 1.25 em tall, sits 0.34 em
before the text, and its dots take the fixed brand colours of each theme. Output is SVG,
rendered to PDF (vector, font embedded) and PNG by rsvg-convert. Nothing here runs on the site.

usage: make.py preview            # font comparison, light and dark
       make.py sheet FONT PAPER   # printable sheet with cut marks; PAPER is letter or a4
       make.py nopad FONT PAPER   # the same, zero padding: the cut is the edge of the ink
"""
import subprocess, sys, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
# Colours: the site's current tokens (docs/style.css.inc), so the sticker matches the page.
THEMES = {
    'light': dict(bg='#fbfaf7', fg='#131210', dim='#4d4a43', accent='#7a3210'),
    'dark':  dict(bg='#161513', fg='#f3f0e9', dim='#bbb7ac', accent='#f0a170'),
}
FONTS = {
    'jetbrains': ('JetBrainsMono Nerd Font', '/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf'),
    'adwaita':   ('Adwaita Mono', '/usr/share/fonts/Adwaita/AdwaitaMono-Bold.ttf'),
    'liberation':('Liberation Mono', '/usr/share/fonts/liberation/LiberationMono-Bold.ttf'),
}

def advance(fontfile):
    """Advance width of one glyph, in em (monospace: every glyph is the same)."""
    w = lambda s: int(subprocess.check_output(['magick', '-font', fontfile, '-pointsize', '1000', f'label:{s}', '-format', '%w', 'info:']))
    return (w('0' * 20) - w('0' * 10)) / 10 / 1000

def mark(x, y, size, t):
    """The mark (32-unit canvas) scaled to `size`, top-left at x, y."""
    k = size / 32
    return (f'<g transform="translate({x:.3f} {y:.3f}) scale({k:.5f})">'
            f'<path d="M8.5 6.5H5.5V25.5H8.5M23.5 6.5H26.5V25.5H23.5" fill="none" stroke="{t["fg"]}" stroke-width="2"/>'
            f'<circle cx="11.5" cy="16" r="3" fill="{t["fg"]}"/><circle cx="20.5" cy="16" r="3" fill="{t["accent"]}"/></g>')

def lockup(x, y, em, font, t):
    """Mark + text at font size `em`, top-left at x, y. Returns (svg, width, height)."""
    family, fontfile = FONTS[font]
    m = 1.25 * em                       # site: .mark { width:1.25em }
    gap = 0.34 * em                     # site: margin-right:.34em
    tw = advance(fontfile) * em * len('parlor.sh')
    # site: the mark sits at vertical-align:-.28em, so the baseline is .28em above its bottom
    baseline = y + m - 0.28 * em
    svg = mark(x, y, m, t) + (
        f'<text x="{x + m + gap:.3f}" y="{baseline:.3f}" font-family="{family}" font-weight="700" '
        f'font-size="{em:.3f}" fill="{t["fg"]}">parlor<tspan fill="{t["dim"]}">.sh</tspan></text>')
    return svg, m + gap + tw, m

def ink_box(font):
    """The lockup's inked area at em = 100, in the lockup's own coordinates: (x, y, w, h).
    Measured from a high-resolution render, since glyph edges depend on the font."""
    em, dpi = 100, 600
    body, lw, lh = lockup(0, 0, em, font, THEMES['light'])
    probe = os.path.join(HERE, '.ink-probe.svg')
    open(probe, 'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{lw * 1.2:.1f}pt" height="{lh * 1.4:.1f}pt" '
                           f'viewBox="{-lw * 0.1:.2f} {-lh * 0.2:.2f} {lw * 1.2:.2f} {lh * 1.4:.2f}">{body}</svg>')
    png = probe[:-4] + '.png'
    subprocess.check_call(['rsvg-convert', '-d', str(dpi), '-p', str(dpi), '-o', png, probe])
    w, h, x, y = map(int, re.match(r'(\d+)x(\d+)\+(\d+)\+(\d+)', subprocess.check_output(
        ['magick', png, '-alpha', 'extract', '-threshold', '1%', '-format', '%@', 'info:']).decode()).groups())
    os.remove(probe); os.remove(png)
    k = 72 / dpi                                   # px -> pt, which is the SVG's user unit here
    return (x * k - lw * 0.1, y * k - lh * 0.2, w * k, h * k)

def sticker(x, y, em, font, t, pad):
    """One sticker: background rectangle, lockup centred. Returns (svg, w, h)."""
    probe, lw, lh = lockup(0, 0, em, font, t)
    w, h = lw + 2 * pad, lh + 2 * pad
    body, _, _ = lockup(x + pad, y + pad, em, font, t)
    return body, w, h

def render(svg_path, fmt, out):
    subprocess.check_call(['rsvg-convert', '-f', fmt, '-o', out] + (['-d', '300', '-p', '300'] if fmt == 'png' else []) + [svg_path])

def preview():
    em, pad = 40, 26
    rows, y, parts, width = [], 20, [], 0
    for font in FONTS:
        x = 20
        for name, t in THEMES.items():
            body, w, h = sticker(x, y, em, font, t, pad)
            parts.append(f'<rect x="{x}" y="{y}" width="{w:.2f}" height="{h:.2f}" rx="6" fill="{t["bg"]}" stroke="#999" stroke-width="0.5"/>' + body)
            x += w + 30
        parts.append(f'<text x="{x}" y="{y + h / 2 + 6:.1f}" font-family="sans-serif" font-size="16" fill="#555">{font}</text>')
        width = max(width, x + 140); y += h + 30
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{y:.0f}" viewBox="0 0 {width:.0f} {y:.0f}"><rect width="100%" height="100%" fill="#ffffff"/>' + ''.join(parts) + '</svg>'
    p = os.path.join(HERE, 'preview-fonts.svg'); open(p, 'w').write(svg)
    render(p, 'png', os.path.join(HERE, 'preview-fonts.png'))
    print(os.path.join(HERE, 'preview-fonts.png'))

PAPERS = {'letter': (612, 792), 'a4': (595.28, 841.89)}   # points
PT = 72                                                    # points per inch

def fit(font, w, h):
    """Font size and padding so the lockup sits centred in a w x h (points) sticker."""
    a = advance(FONTS[font][1]) * len('parlor.sh')
    em = (w - h) / (1.25 + 0.34 + a - 1.25)      # width - height removes the padding: em*(0.34 + a)
    pad = (h - 1.25 * em) / 2
    return em, pad

def sheet(font, paper, which, sw=3 * PT, sh=1 * PT, bleed=PT / 16, gutter=0.375 * PT):
    """A page of stickers with crop marks. which: 'mixed' (left light, right dark), 'light', 'dark'."""
    W, H = PAPERS[paper]
    em, pad = fit(font, sw, sh)
    cols = 2
    rows = int((H - 1.5 * PT + gutter) // (sh + gutter))
    x0 = (W - (cols * sw + (cols - 1) * gutter)) / 2
    y0 = (H - (rows * sh + (rows - 1) * gutter)) / 2
    parts, marks = [], []
    mk = lambda x1, y1, x2, y2: marks.append(f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}"/>')
    for r in range(rows):
        for c in range(cols):
            theme = {'mixed': ('light', 'dark')[c], 'light': 'light', 'dark': 'dark'}[which]
            t = THEMES[theme]
            x, y = x0 + c * (sw + gutter), y0 + r * (sh + gutter)
            # background runs past the cut line by the bleed, so an off cut shows no paper
            parts.append(f'<rect x="{x - bleed:.2f}" y="{y - bleed:.2f}" width="{sw + 2 * bleed:.2f}" height="{sh + 2 * bleed:.2f}" fill="{t["bg"]}"/>')
            body, lw, lh = lockup(x + pad, y + pad, em, font, t)
            parts.append(body)
            # crop marks: short lines on the cut lines, starting outside the bleed
            o, L = bleed + 2, 9
            for cx in (x, x + sw):
                mk(cx, y - o - L, cx, y - o); mk(cx, y + sh + o, cx, y + sh + o + L)
            for cy in (y, y + sh):
                mk(x - o - L, cy, x - o, cy); mk(x + sw + o, cy, x + sw + o + L, cy)
    note_y = H - 0.45 * PT
    note = (f'<g font-family="sans-serif" font-size="7" fill="#777">'
            f'<text x="{x0:.2f}" y="{note_y:.2f}">parlor.sh stickers, {sw / PT:g} x {sh / PT:g} in. Print at 100% (actual size), no scaling. '
            f'Cut on the crop marks. The bar should measure 1 in:</text>'
            f'<rect x="{W - x0 - PT:.2f}" y="{note_y - 5:.2f}" width="{PT}" height="4" fill="#777"/></g>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W / PT:.4f}in" height="{H / PT:.4f}in" viewBox="0 0 {W} {H}">'
           + ''.join(parts) + '<g stroke="#000" stroke-width="0.4">' + ''.join(marks) + '</g>' + note + '</svg>')
    name = f'sheet-{paper}-{which}'
    open(os.path.join(HERE, name + '.svg'), 'w').write(svg)
    render(os.path.join(HERE, name + '.svg'), 'pdf', os.path.join(HERE, name + '.pdf'))
    return name, rows * cols, em, pad

def sheet_nopad(font, paper, which, sw=3 * PT, bleed=PT / 16, gutter=0.375 * PT):
    """Zero padding: the cut line is the edge of the ink. The lockup fills the sticker's width."""
    W, H = PAPERS[paper]
    ix, iy, iw, ih = ink_box(font)                 # at em = 100
    em = 100 * sw / iw
    k = em / 100
    sh = ih * k
    cols = 2
    rows = int((H - 1.5 * PT + gutter) // (sh + gutter))
    x0 = (W - (cols * sw + (cols - 1) * gutter)) / 2
    y0 = (H - (rows * sh + (rows - 1) * gutter)) / 2
    parts, marks = [], []
    mk = lambda a, b, c, d: marks.append(f'<line x1="{a:.2f}" y1="{b:.2f}" x2="{c:.2f}" y2="{d:.2f}"/>')
    for r in range(rows):
        for c in range(cols):
            t = THEMES[{'mixed': ('light', 'dark')[c], 'light': 'light', 'dark': 'dark'}[which]]
            x, y = x0 + c * (sw + gutter), y0 + r * (sh + gutter)
            parts.append(f'<rect x="{x - bleed:.2f}" y="{y - bleed:.2f}" width="{sw + 2 * bleed:.2f}" height="{sh + 2 * bleed:.2f}" fill="{t["bg"]}"/>')
            body, _, _ = lockup(x - ix * k, y - iy * k, em, font, t)
            parts.append(body)
            o, L = bleed + 2, 9
            for cx in (x, x + sw):
                mk(cx, y - o - L, cx, y - o); mk(cx, y + sh + o, cx, y + sh + o + L)
            for cy in (y, y + sh):
                mk(x - o - L, cy, x - o, cy); mk(x + sw + o, cy, x + sw + o + L, cy)
    ny = H - 0.45 * PT
    note = (f'<g font-family="sans-serif" font-size="7" fill="#777"><text x="{x0:.2f}" y="{ny:.2f}">parlor.sh stickers, zero padding, '
            f'{sw / PT:g} x {sh / PT:.2f} in. Print at 100% (actual size). Cut on the marks or just outside them. The bar should measure 1 in:</text>'
            f'<rect x="{W - x0 - PT:.2f}" y="{ny - 5:.2f}" width="{PT}" height="4" fill="#777"/></g>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W / PT:.4f}in" height="{H / PT:.4f}in" viewBox="0 0 {W} {H}">'
           + ''.join(parts) + '<g stroke="#000" stroke-width="0.4">' + ''.join(marks) + '</g>' + note + '</svg>')
    name = f'sheet-{paper}-nopad-{which}'
    open(os.path.join(HERE, name + '.svg'), 'w').write(svg)
    render(os.path.join(HERE, name + '.svg'), 'pdf', os.path.join(HERE, name + '.pdf'))
    return name, rows * cols, sh / PT

def single(font, theme, sw=3 * PT, sh=1 * PT):
    """One sticker on its own, for anything other than the home sheet."""
    em, pad = fit(font, sw, sh)
    t = THEMES[theme]
    body, _, _ = lockup(pad, pad, em, font, t)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{sw / PT:g}in" height="{sh / PT:g}in" viewBox="0 0 {sw} {sh}">'
           f'<rect width="{sw}" height="{sh}" fill="{t["bg"]}"/>' + body + '</svg>')
    p = os.path.join(HERE, f'sticker-{theme}.svg'); open(p, 'w').write(svg)
    render(p, 'png', p[:-4] + '.png')

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    if cmd == 'preview':
        preview()
    elif cmd == 'sheet':
        font, paper = sys.argv[2], sys.argv[3]
        for which in ('mixed', 'light', 'dark'):
            print(*sheet(font, paper, which))
        for theme in THEMES:
            single(font, theme)
    elif cmd == 'nopad':
        font, paper = sys.argv[2], sys.argv[3]
        for which in ('mixed', 'light', 'dark'):
            print(*sheet_nopad(font, paper, which))
