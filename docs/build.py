#!/usr/bin/env python3
"""Build the HTML twins of the docs pages from their markdown.

docs/{quickstart,concepts,clients,api}.md are what agents read at /docs; the .html files
of the same names are the same text for browsers, generated here so that the two never
drift. Each HTML page gets the docs sidebar (both pages and their sections) and a search
index of every section of both, embedded so search works without a server round trip.
`{{placeholders}}` pass through untouched: the server fills them in both representations.

    docs/build.py            write the HTML files
    docs/build.py --check    exit 1 if they are not what this script would write (CI)

Covers only the markdown these pages use: headings, paragraphs, lists (nested by two
spaces), tables, indented code blocks, `code`, **bold**, *italic*, [links](url).
Python standard library only.
"""
import html, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# In sidebar order: (file name, path under /docs, description).
PAGES = [
    ("quickstart", "", "Get two agents talking in a parlor room, with nothing but prompts."),
    ("concepts", "concepts", "Rooms, messages, tokens, waiting, lifetime, aliases and trust."),
    ("clients", "clients", "Agent prompt and HTTP, the MCP connector, the CLI and skills, and when to use each."),
    ("api", "api", "Every parlor endpoint: parameters, responses and errors."),
    ("self-hosting", "self-hosting", "Run your own parlor server: build, deploy, configure, and take rooms down."),
    ("privacy", "privacy", "What parlor.sh keeps, for how long, and how to have it removed."),
]


def url(path):
    return "{{base}}/docs" + ("/" + path if path else "")

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · parlor.sh</title>
<meta name="description" content="{description}">
<link rel="alternate" type="text/markdown" href="{url}">
<meta name="color-scheme" content="light dark">
<style>{{{{style}}}}</style>
{{{{theme}}}}
</head>
<body class="docs">
{{{{header}}}}
<div class="docs-layout">
<aside class="sidebar">
<div class="search" role="search">
<input id="q" type="search" placeholder="Search the docs" aria-label="Search the docs" autocomplete="off" spellcheck="false">
<ol id="results" hidden aria-live="polite"></ol>
</div>
<details class="toc" open>
<summary>Contents</summary>
<nav aria-label="Docs">
{toc}
</nav>
</details>
</aside>
<main class="doc" id="content">
{body}
</main>
</div>
{{{{footer}}}}
<script type="application/json" id="index">{index}</script>
<script>
// Docs search: every section of both pages, matched on all the words typed. "/" focuses it.
(function () {{
  var q = document.getElementById("q"), out = document.getElementById("results");
  var index = JSON.parse(document.getElementById("index").textContent);
  var toc = document.querySelector(".toc");
  if (matchMedia("(max-width: 58rem)").matches) toc.open = false;
  function snippet(text, word) {{
    var i = text.toLowerCase().indexOf(word);
    if (i < 0) return text.slice(0, 110);
    var s = Math.max(0, i - 40);
    return (s ? "…" : "") + text.slice(s, s + 120) + "…";
  }}
  function show() {{
    var words = q.value.toLowerCase().split(/\\s+/).filter(Boolean);
    out.textContent = "";
    if (!words.length) {{ out.hidden = true; return; }}
    var hits = index.map(function (e) {{
      var t = e.title.toLowerCase(), b = e.text.toLowerCase(), score = 0;
      for (var i = 0; i < words.length; i++) {{
        if (t.indexOf(words[i]) >= 0) score += 3; else if (b.indexOf(words[i]) >= 0) score += 1; else return null;
      }}
      return {{ e: e, score: score }};
    }}).filter(Boolean).sort(function (a, b) {{ return b.score - a.score; }}).slice(0, 8);
    out.hidden = false;
    if (!hits.length) {{
      var li = document.createElement("li"); li.className = "none"; li.textContent = "Nothing matches.";
      out.appendChild(li); return;
    }}
    hits.forEach(function (h, n) {{
      var li = document.createElement("li"), a = document.createElement("a");
      a.href = h.e.url; if (n === 0) a.className = "first";
      var w = document.createElement("span"); w.className = "where"; w.textContent = h.e.page;
      var t = document.createElement("span"); t.textContent = h.e.title;
      var s = document.createElement("span"); s.className = "snip"; s.textContent = snippet(h.e.text, words[0]);
      a.appendChild(w); a.appendChild(t); a.appendChild(s); li.appendChild(a); out.appendChild(li);
    }});
  }}
  // Copy buttons on code and prompts; without a clipboard there are none, and the text still selects.
  if (navigator.clipboard) document.querySelectorAll("main.doc pre").forEach(function (pre) {{
    var text = pre.textContent, b = document.createElement("button");
    pre.classList.add("prompt");
    b.type = "button"; b.className = "copy"; b.textContent = "copy"; b.setAttribute("aria-label", "Copy");
    b.addEventListener("click", function () {{
      navigator.clipboard.writeText(text).then(function () {{
        b.textContent = "copied"; setTimeout(function () {{ b.textContent = "copy"; }}, 1500);
      }});
    }});
    pre.appendChild(b);
  }});
  q.addEventListener("input", show);
  q.addEventListener("keydown", function (ev) {{
    if (ev.key === "Enter") {{ var a = out.querySelector("a"); if (a) location.href = a.href; }}
    if (ev.key === "Escape") {{ q.value = ""; show(); }}
  }});
  document.addEventListener("keydown", function (ev) {{
    if (ev.key === "/" && document.activeElement !== q && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) {{
      ev.preventDefault(); q.focus();
    }}
  }});
}})();
</script>
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


def plain(text):
    """Markdown inline text as plain text, for the search index and the contents."""
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return re.sub(r"[`*]", "", text)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", plain(text).lower()).strip("-")


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
            if level == 1:
                out.append("<h1>%s</h1>" % inline(text))
            else:
                ident = slug(text)
                out.append('<h%d id="%s">%s<a class="anchor" href="#%s" aria-label="Link to this section">#</a></h%d>' % (level, ident, inline(text), ident, level))
            i += 1
        elif line.startswith("> ") or line == ">":
            quote = []
            while i < len(lines) and (lines[i].startswith("> ") or lines[i] == ">"):
                quote.append(lines[i][2:])
                i += 1
            out.append('<div class="note">%s</div>' % blocks(quote))
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([cell.strip() for cell in lines[i].strip().strip("|").split("|")])
                i += 1
            head, body = rows[0], [r for r in rows[1:] if not all(re.fullmatch(r":?-+:?", c) for c in r)]
            t = ['<div class="table"><table>', "<thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in head) + "</tr></thead>", "<tbody>"]
            t += ["<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>" for r in body]
            out.append("\n".join(t + ["</tbody>", "</table></div>"]))
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
        elif re.match(r"\d+\. ", line):
            items = []
            while i < len(lines) and (re.match(r"\d+\. ", lines[i]) or lines[i].startswith("   ")):
                if m := re.match(r"\d+\. (.*)", lines[i]):
                    items.append([m.group(1)])
                else:
                    items[-1].append(lines[i][3:])
                i += 1
            out.append("<ol>\n" + "\n".join("<li>%s</li>" % item_html(it) for it in items) + "\n</ol>")
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"(#{1,3} |- |\||    |> |\d+\. )", lines[i]):
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


def sections(md):
    """(level, title, text) for every h2 and h3, text being the section's plain words."""
    out, current = [], None
    for line in md.split("\n"):
        if m := re.match(r"(#{2,3}) (.*)", line):
            current = [len(m.group(1)), m.group(2), []]
            out.append(current)
        elif current is not None and line.strip():
            current[2].append(plain(line.strip().lstrip("-| ")))
    return [(lvl, title, " ".join(words)) for lvl, title, words in out]


def toc(current):
    """The docs pages; the current one expanded to its sections."""
    out = ["<ul>"]
    for name, path, _ in PAGES:
        md = (HERE / (name + ".md")).read_text()
        title = re.match(r"# (.*)", md).group(1)
        cur = ' aria-current="page"' if name == current else ""
        out.append('<li><a class="page" href="%s"%s>%s</a>' % (url(path), cur, html.escape(title)))
        if name == current:
            groups = []  # [(h2 title, [h3 titles])]
            for lvl, head, _ in sections(md):
                if lvl == 2 or not groups:
                    groups.append((head, []))
                else:
                    groups[-1][1].append(head)
            link = lambda h: '<a href="#%s">%s</a>' % (slug(h), html.escape(plain(h)))
            lis = []
            for head, subs in groups:
                inner = "<ul>%s</ul>" % "".join("<li>%s</li>" % link(h) for h in subs) if subs else ""
                lis.append("<li>%s%s</li>" % (link(head), inner))
            out.append("<ul>\n%s\n</ul>" % "\n".join(lis))
        out.append("</li>")
    out.append("</ul>")
    return "\n".join(out)


def index():
    entries = []
    for name, path, _ in PAGES:
        md = (HERE / (name + ".md")).read_text()
        title = re.match(r"# (.*)", md).group(1)
        for _, head, text in sections(md):
            entries.append({"page": title, "title": plain(head), "url": "%s#%s" % (url(path), slug(head)), "text": text})
    # Placeholders are filled by the server with text that may hold quotes or markup (the MCP
    # sentence carries a link), which would break the JSON: the index keeps only {{base}}.
    for e in entries:
        e["text"] = re.sub(r"\{\{(?!base\}\})\w+\}\}", "", e["text"])
    # </script> can never appear inside the JSON block.
    return json.dumps(entries, ensure_ascii=False).replace("</", "<\\/")


def build(name):
    md = (HERE / (name + ".md")).read_text()
    title = re.match(r"# (.*)", md).group(1)
    path, description = dict((n, (p, d)) for n, p, d in PAGES)[name]
    return TEMPLATE.format(title=html.escape(title), description=html.escape(description), url=url(path),
                           toc=toc(name), body=blocks(md.split("\n")), index=index())


# The README carries the same docs, filled with parlor.sh's values (the server fills its own).
README = HERE.parent / "README.md"
START, END = "<!-- docs: generated by docs/build.py from docs/*.md; edit those -->", "<!-- /docs -->"
README_VARS = {
    "base": "https://parlor.sh", "ttl": "30 days", "ttl_range": "1 hour to 30 days", "max_wait": "55",
    "max_body": "8192", "max_messages": "10000", "max_room_bytes": "1048576 bytes", "max_participants": "50",
    "rate_create": "20 per hour", "rate_post": "60 per minute",
    "mcp_connect": "Add `https://parlor.sh/mcp` to your chat as a custom connector. No sign-in needed.",
}


def gh_slug(text):
    """GitHub's heading anchor: lowercase, punctuation dropped, spaces to hyphens."""
    return re.sub(r"[^\w\- ]", "", plain(text).lower()).replace(" ", "-")


def readme_docs():
    """The docs pages as README sections: each page's title one level down, anchors GitHub's."""
    pages = [(name, (HERE / (name + ".md")).read_text()) for name, _, _ in PAGES]
    # Every heading of the generated block, in order, with GitHub's numbering of duplicates.
    seen, anchors = {}, {}
    for name, md in pages:
        for line in md.split("\n"):
            if m := re.match(r"(#{1,3}) (.*)", line):
                g = gh_slug(m.group(2))
                n = seen.get(g, 0)
                seen[g] = n + 1
                anchors.setdefault((name, slug(m.group(2))), g if n == 0 else "%s-%d" % (g, n))
    out = []
    for name, md in pages:
        md = re.sub(r"^(#{1,3}) ", lambda m: "#" + m.group(1) + " ", md, flags=re.M)
        md = re.sub(r"\]\(#([^)]+)\)", lambda m: "](#%s)" % anchors.get((name, m.group(1)), m.group(1)), md)
        md = re.sub(r"\{\{(\w+)\}\}", lambda m: README_VARS[m.group(1)], md)
        out.append(md.strip())
    return "\n\n".join(out)


def readme():
    text = README.read_text()
    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    return head + START + "\n\n" + readme_docs() + "\n\n" + END + tail


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    text = readme()
    if check:
        if README.read_text() != text:
            stale.append("README.md")
    else:
        README.write_text(text)
    for name, _, _ in PAGES:
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
