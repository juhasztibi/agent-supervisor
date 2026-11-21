#!/usr/bin/env python3
"""Turn a terminal capture with colours (tmux capture-pane -e) into an SVG that looks like a terminal window.

Usage: ansi2svg.py <capture file> <output.svg> [title]
"""
import html
import re
import sys

BG, FG = "#1e1e2e", "#cdd6f4"
BASE16 = ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
          "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"]
CW, LH, FS, PAD, BAR = 8.4, 19, 14, 18, 34   # cell width, line height, font size, padding, title bar


def xterm256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        steps = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (steps[n // 36], steps[(n // 6) % 6], steps[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


def parse(line):
    """Yields (text, style) runs; style = (fg, bg, bold, dim)."""
    fg, bg, bold, dim = None, None, False, False
    pos = 0
    for m in re.finditer(r"\x1b\[([0-9;]*)m", line):
        if m.start() > pos:
            yield line[pos:m.start()], (fg, bg, bold, dim)
        codes = [int(c) if c else 0 for c in m.group(1).split(";")]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                fg, bg, bold, dim = None, None, False, False
            elif c == 1:
                bold = True
            elif c == 2:
                dim = True
            elif c == 22:
                bold = dim = False
            elif c == 39:
                fg = None
            elif c == 49:
                bg = None
            elif 30 <= c <= 37:
                fg = BASE16[c - 30]
            elif 90 <= c <= 97:
                fg = BASE16[c - 90 + 8]
            elif 40 <= c <= 47:
                bg = BASE16[c - 40]
            elif c in (38, 48) and i + 2 < len(codes) and codes[i + 1] == 5:
                col = xterm256(codes[i + 2])
                fg, bg = (col, bg) if c == 38 else (fg, col)
                i += 2
            elif c in (38, 48) and i + 4 < len(codes) and codes[i + 1] == 2:
                col = "#%02x%02x%02x" % tuple(codes[i + 2:i + 5])
                fg, bg = (col, bg) if c == 38 else (fg, col)
                i += 4
            i += 1
        pos = m.end()
    if pos < len(line):
        yield line[pos:], (fg, bg, bold, dim)


def main():
    src, out = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else "ai-agents"
    lines = open(src, encoding="utf-8").read().rstrip("\n").split("\n")
    while lines and not re.sub(r"\x1b\[[0-9;]*m", "", lines[-1]).strip():
        lines.pop()
    cols = max(len(re.sub(r"\x1b\[[0-9;]*m", "", l)) for l in lines)
    w, h = int(cols * CW + 2 * PAD), int(len(lines) * LH + 2 * PAD + BAR)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
         f'<rect width="{w}" height="{h}" rx="10" fill="{BG}"/>',
         '<circle cx="20" cy="17" r="6" fill="#f38ba8"/><circle cx="40" cy="17" r="6" fill="#f9e2af"/>'
         '<circle cx="60" cy="17" r="6" fill="#a6e3a1"/>',
         f'<text x="{w / 2}" y="22" fill="#7f849c" font-family="Menlo, Consolas, monospace" font-size="12" '
         f'text-anchor="middle">{html.escape(title)}</text>',
         f'<g font-family="Menlo, \'SF Mono\', Consolas, \'DejaVu Sans Mono\', monospace" font-size="{FS}">']
    for row, line in enumerate(lines):
        x, y = PAD, BAR + PAD + row * LH
        for text, (fg, bg, bold, dim) in parse(line):
            n = len(text)
            if bg:
                o.append(f'<rect x="{x:.1f}" y="{y - 4}" width="{n * CW:.1f}" height="{LH}" fill="{bg}"/>')
            attrs = f'fill="{fg or FG}"' + (' font-weight="bold"' if bold else "") + (' opacity="0.55"' if dim else "")
            for seg in re.finditer(r"\S+(?: \S+)*", text):   # each word group at its own column: exact alignment
                k = len(seg.group())
                o.append(f'<text x="{x + seg.start() * CW:.1f}" y="{y + FS - 1}" {attrs} textLength="{k * CW:.1f}" '
                         f'lengthAdjust="spacingAndGlyphs" xml:space="preserve">{html.escape(seg.group())}</text>')
            x += n * CW
    o.append("</g></svg>")
    open(out, "w", encoding="utf-8").write("\n".join(o))


if __name__ == "__main__":
    main()
