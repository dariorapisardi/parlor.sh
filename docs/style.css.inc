:root { --bg:#fbfaf7; --fg:#131210; --dim:#4d4a43; --line:#cfcbbf; --rule:#b4b0a3; --accent:#7a3210; --box:#f2efe8; --hi:#f6e3d6;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans","Helvetica Neue",Arial,sans-serif; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#161513; --fg:#f3f0e9; --dim:#bbb7ac; --line:#3d3b36; --rule:#59564e; --accent:#f0a170; --box:#1f1e1b; --hi:#3a2a20; } }
:root[data-theme="dark"] { --bg:#161513; --fg:#f3f0e9; --dim:#bbb7ac; --line:#3d3b36; --rule:#59564e; --accent:#f0a170; --box:#1f1e1b; --hi:#3a2a20; }
* { box-sizing:border-box; }
html { scroll-padding-top:1rem; }
body { margin:0; background:var(--bg); color:var(--fg); font:17px/1.6 var(--sans); -webkit-text-size-adjust:100%; }
a { color:var(--accent); text-underline-offset:.15em; }
a:focus-visible, button:focus-visible, input:focus-visible, summary:focus-visible { outline:2px solid var(--accent); outline-offset:2px; border-radius:3px; }
.skip { position:absolute; left:-999px; } .skip:focus { left:1rem; top:.6rem; background:var(--bg); padding:.3rem .6rem; z-index:2; }
.dim { color:var(--dim); }

/* One header on every page: home, docs, source, and the theme switch. */
header.site { display:flex; align-items:center; justify-content:space-between; gap:1rem; max-width:74rem; margin:0 auto; padding:.9rem 1.25rem; border-bottom:1px solid var(--line); font-family:var(--mono); }
.brand { color:var(--fg); text-decoration:none; font-weight:700; font-size:1.1rem; white-space:nowrap; }
.mark { width:1.25em; height:1.25em; vertical-align:-.28em; margin-right:.34em; }
header.site nav { display:flex; align-items:center; gap:1.4rem; font-size:.9rem; }
header.site nav a { color:var(--dim); text-decoration:none; }
header.site nav a:hover, body.docs header.site .nav-docs { color:var(--fg); }
body.docs header.site .nav-docs { text-decoration:underline; text-decoration-color:var(--accent); text-underline-offset:.4em; }
#theme { background:none; border:0; padding:.2rem; cursor:pointer; color:var(--dim); font:inherit; font-size:.85rem; }
#theme:hover { color:var(--fg); }

main { display:block; max-width:44rem; margin:0 auto; padding:2.5rem 1.25rem 3rem; overflow-wrap:break-word; }
h1, h2, h3 { font-family:var(--mono); line-height:1.25; }
h1 { font-size:1.75rem; margin:0 0 .8rem; letter-spacing:-.01em; }
h2 { font-size:1.2rem; margin:2.6rem 0 .7rem; color:var(--accent); }
h3 { font-size:1.02rem; margin:2rem 0 .5rem; }
p { margin:.7rem 0; } ul, ol { margin:.7rem 0; padding-left:1.3rem; } li { margin:.35rem 0; }
code { font-family:var(--mono); font-size:.86em; background:var(--box); border-radius:3px; padding:.05em .3em; overflow-wrap:anywhere; }
pre, .box { background:var(--box); border:1px solid var(--line); border-radius:6px; padding:.8rem 1rem; margin:.8rem 0; overflow-x:auto; }
pre { font:.84rem/1.55 var(--mono); white-space:pre-wrap; overflow-wrap:anywhere; }
.lead { font-family:var(--mono); font-size:1.75rem; font-weight:700; line-height:1.25; margin:0 0 1rem; letter-spacing:-.01em; }
.note { border-left:3px solid var(--accent); padding:.1rem 0 .1rem 1rem; margin:1.2rem 0; }
details { margin-top:2.2rem; } summary { cursor:pointer; color:var(--dim); }

/* Prompts to paste into an agent, with a copy button. */
pre.prompt { position:relative; padding-right:4.5rem; font-size:.9rem; }
.copy { position:absolute; top:.5rem; right:.5rem; background:var(--bg); border:1px solid var(--rule); border-radius:4px; color:var(--dim); font:.75rem var(--mono); padding:.15rem .5rem; cursor:pointer; }
.copy:hover { color:var(--fg); }
.fill { color:var(--accent); font-weight:600; border:1px dashed var(--accent); border-radius:4px; padding:0 .3rem; white-space:nowrap; }
.next { display:flex; flex-wrap:wrap; gap:.6rem 1.6rem; margin:1.6rem 0; font-family:var(--mono); font-size:.92rem; }

/* Room transcripts. */
.msg { padding:.5rem 0; border-top:1px solid var(--line); font-size:.95rem; } .msg:first-child { border-top:0; }
.msg .who { color:var(--accent); font-weight:600; font-family:var(--mono); font-size:.9em; } .msg .meta { color:var(--dim); font-size:.8em; font-family:var(--mono); }
.msg.system { color:var(--dim); font-size:.88em; } .msg .body { white-space:pre-wrap; overflow-wrap:anywhere; }

/* Tables: full width, readable cells; wide ones scroll inside their own box. */
.table { overflow-x:auto; margin:1rem 0; }
table { width:100%; border-collapse:collapse; font-size:.93rem; line-height:1.5; }
th, td { text-align:left; vertical-align:top; padding:.5rem .7rem .5rem 0; border-bottom:1px solid var(--line); }
th { font-weight:600; color:var(--dim); border-bottom-color:var(--rule); }
td code, th code { overflow-wrap:normal; white-space:nowrap; }

/* Docs: contents and search on the left, one readable column on the right. */
.docs-layout { display:grid; grid-template-columns:15.5rem minmax(0,1fr); gap:3rem; max-width:74rem; margin:0 auto; padding:0 1.25rem; }
.docs-layout main { margin:0; padding:2.5rem 0 3rem; max-width:42rem; }
.sidebar { position:sticky; top:0; align-self:start; max-height:100vh; overflow-y:auto; padding:2.2rem 0 2rem; font-size:.9rem; }
.search input { width:100%; font:inherit; font-size:.92rem; color:var(--fg); background:var(--box); border:1px solid var(--rule); border-radius:6px; padding:.45rem .6rem; }
.search input::placeholder { color:var(--dim); }
#results { list-style:none; padding:0; margin:.6rem 0 0; }
#results li { margin:0; } #results a { display:block; padding:.45rem .5rem; border-radius:5px; color:var(--fg); text-decoration:none; }
#results a:hover, #results a:focus-visible, #results a.first { background:var(--hi); }
#results .where { display:block; color:var(--dim); font-size:.8rem; }
#results .snip { display:block; color:var(--dim); font-size:.82rem; margin-top:.1rem; }
#results .none { color:var(--dim); padding:.4rem .5rem; }
.toc { margin-top:1.3rem; } .toc summary { display:none; }
.toc .group { color:var(--dim); font-size:.8rem; margin:1.2rem 0 .3rem; }
.toc ul { list-style:none; padding:0; margin:0; } .toc li { margin:0; }
.toc a { display:block; padding:.22rem 0; color:var(--dim); text-decoration:none; line-height:1.35; }
.toc a:hover { color:var(--fg); }
.toc .page { color:var(--fg); font-weight:600; }
.toc .page[aria-current] { color:var(--accent); }
.toc ul ul { padding-left:.8rem; border-left:1px solid var(--line); margin:.15rem 0 .4rem; }
.toc ul ul ul a { font-family:var(--mono); font-size:.84rem; }
.doc h2, .doc h3 { scroll-margin-top:1rem; }
.anchor { margin-left:.4rem; color:var(--rule); text-decoration:none; font-weight:400; opacity:0; }
h2:hover .anchor, h3:hover .anchor, .anchor:focus-visible { opacity:1; }

@media (max-width: 58rem) {
  .docs-layout { display:block; }
  .sidebar { position:static; max-height:none; padding:1.4rem 0 0; }
  .toc { border:1px solid var(--line); border-radius:6px; padding:.2rem .8rem; }
  .toc summary { display:list-item; padding:.4rem 0; }
  .docs-layout main { padding-top:1.5rem; }
}
@media (max-width: 30rem) { body { font-size:16px; } header.site nav { gap:1rem; } h1, .lead { font-size:1.45rem; } }
footer.site { max-width:74rem; margin:2rem auto 0; padding:1.4rem 1.25rem 2.5rem; border-top:1px solid var(--line); color:var(--dim); font-size:.88rem; }
footer.site p { margin:.3rem 0; max-width:44rem; }
@media print { header.site nav, .sidebar, .copy, .anchor { display:none; } .mark circle:last-of-type { fill:#000; } }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior:auto; } }
