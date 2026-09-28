#!/usr/bin/env python3
"""Build the HTML twins of the reference pages from their markdown.

docs/protocol.md and docs/clients.md are what agents read; docs/protocol.html and
docs/clients.html are the same text for browsers, generated here so that the two never
drift. `{{placeholders}}` pass through untouched: the server fills them in both.

    docs/build.py            write the HTML files
    docs/build.py --check    exit 1 if they are not what this script would write (CI)

Covers only the markdown these pages use: headings, paragraphs, lists (nested by two
spaces), tables, indented code blocks, `code`, **bold**, *italic*, [links](url).
Python standard library only.
"""
import html, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PAGES = {
    "protocol": "The parlor interface: every operation, its arguments, results and errors",
    "clients": "Ways to use parlor: HTTP, the CLI, the MCP connector, the skill, and when to use each",
}

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · parlor.sh</title>
<meta name="description" content="{description}">
<link rel="alternate" type="text/markdown" href="{{{{base}}}}/{name}">
<meta name="color-scheme" content="light dark">
<style>{{{{style}}}}</style>
{{{{theme}}}}
</head>
<body>
<button id="theme" type="button" aria-label="Switch between light and dark theme" hidden></button>
<main class="doc">
<p class="crumb"><a href="{{{{base}}}}/">parlor.sh</a> · <a href="{{{{base}}}}/protocol">protocol</a> · <a href="{{{{base}}}}/clients">clients</a></p>
{body}
<footer>
This page is generated from its markdown, which is what an agent gets at the same URL. ·
<a href="https://github.com/dariorapisardi/parlor.sh">source &amp; self-hosting</a> · MIT
</footer>
</main>
</body>
</html>
"""


def inline(text):
    """Escape, then apply code spans (protected), links, bold and italic."""
    spans = []

    def keep(m):
        spans.append("<code>" + html.escape(m.group(1), quote=False) + "</code>")
        return "\x00%d\x00" % (len(spans) - 1)

    text = re.sub(r"`([^`]+)`", keep, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: '<a href="%s">%s</a>' % (m.group(2).replace('"', "&quot;"), m.group(1)), text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub("\x00(\\d+)\x00", lambda m: spans[int(m.group(1))], text)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"`", "", text.lower())).strip("-")


def blocks(lines):
    """Render a list of lines (already dedented to this level) as HTML blocks."""
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
        elif line.startswith("    "):
            code = []
            while i < len(lines) and (lines[i].startswith("    ") or not lines[i].strip()):
                code.append(lines[i][4:])
                i += 1
            while code and not code[-1].strip():
                code.pop()
            out.append("<pre>" + html.escape("\n".join(code), quote=False) + "</pre>")
        elif m := re.match(r"(#{1,3}) (.*)", line):
            level, text = len(m.group(1)), m.group(2)
            ident = "" if level == 1 else ' id="%s"' % slug(text)
            out.append("<h%d%s>%s</h%d>" % (level, ident, inline(text), level))
            i += 1
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([cell.strip() for cell in lines[i].strip().strip("|").split("|")])
                i += 1
            head, body = rows[0], [r for r in rows[1:] if not all(re.fullmatch(r":?-+:?", c) for c in r)]
            t = ["<table>", "<thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in head) + "</tr></thead>", "<tbody>"]
            t += ["<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>" for r in body]
            out.append("\n".join(t + ["</tbody>", "</table>"]))
        elif line.startswith("- "):
            items = []
            while i < len(lines) and (lines[i].startswith("- ") or lines[i].startswith("  ") or not lines[i].strip()):
                if not lines[i].strip() and not (i + 1 < len(lines) and (lines[i + 1].startswith("  ") or lines[i + 1].startswith("- "))):
                    break
                if lines[i].startswith("- "):
                    items.append([lines[i][2:]])
                else:
                    items[-1].append(lines[i][2:])
                i += 1
            out.append("<ul>\n" + "\n".join("<li>%s</li>" % item_html(it) for it in items) + "\n</ul>")
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"(#{1,3} |- |\||    )", lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append("<p>%s</p>" % inline(" ".join(para)))
    return "\n".join(out)


def item_html(lines):
    """A list item: its first paragraph inline, anything after it (sublists, code) as blocks."""
    first = []
    while lines and lines[0].strip() and not re.match(r"(- |    )", lines[0]):
        first.append(lines.pop(0).strip())
    rest = blocks(lines)
    return inline(" ".join(first)) + ("\n" + rest if rest else "")


def build(name):
    md = (HERE / (name + ".md")).read_text()
    title = re.match(r"# (.*)", md).group(1)
    return TEMPLATE.format(title=html.escape(title), description=html.escape(PAGES[name]), name=name, body=blocks(md.split("\n")))


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for name in PAGES:
        target, text = HERE / (name + ".html"), build(name)
        if check:
            if not target.exists() or target.read_text() != text:
                stale.append(target.name)
        else:
            target.write_text(text)
    if stale:
        sys.exit("out of date (run docs/build.py): " + ", ".join(stale))


if __name__ == "__main__":
    main()
