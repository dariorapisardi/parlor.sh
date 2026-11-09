:root { --bg:#f6f0e2; --fg:#0f2c23; --dim:#4a5a52; --line:#cfc8b6; --rule:#a8a391; --accent:#b5441a; --box:#e7e1d1; --hi:#ecdcc8;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans","Helvetica Neue",Arial,sans-serif;
  /* One type scale for the whole site. */
  --fs-title:clamp(1.9rem,3.8vw,3.2rem); --fs-h2:clamp(1.35rem,2.2vw,1.75rem); --fs-base:1rem; --fs-small:.875rem; --fs-fine:.8rem; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#0f2c23; --fg:#fbf6ea; --dim:#c0cbbf; --line:#35524a; --rule:#4f6b62; --accent:#f08a52; --box:#1c3b31; --hi:#2a4a3f; } }
:root[data-theme="dark"] { --bg:#0f2c23; --fg:#fbf6ea; --dim:#c0cbbf; --line:#35524a; --rule:#4f6b62; --accent:#f08a52; --box:#1c3b31; --hi:#2a4a3f; }
* { box-sizing:border-box; }
html { scroll-padding-top:1rem; }
body { margin:0; background:var(--bg); color:var(--fg); font:17px/1.6 var(--sans); -webkit-text-size-adjust:100%; }
a { color:inherit; text-underline-offset:.18em; }
a:focus-visible, button:focus-visible, input:focus-visible, summary:focus-visible { outline:2px solid var(--accent); outline-offset:2px; border-radius:3px; }
.skip { position:absolute; left:-999px; } .skip:focus { left:1rem; top:.6rem; background:var(--bg); padding:.3rem .6rem; z-index:2; }
.dim { color:var(--dim); }

/* One header on every page: home, docs, source, and the theme switch. */
header.site { display:flex; align-items:center; justify-content:space-between; gap:1rem; max-width:72rem; margin:0 auto; padding:1.1rem 1.25rem; font-family:var(--mono); }
.brand { color:var(--fg); text-decoration:none; font-weight:700; font-size:22px; white-space:nowrap; }
.mark { width:1.25em; height:1.25em; vertical-align:-.28em; margin-right:.34em; }
header.site nav { display:flex; align-items:center; gap:1.4rem; font-size:var(--fs-small); }
header.site nav a { color:var(--fg); text-decoration:none; }
header.site nav a:hover, body.docs header.site .nav-docs { color:var(--fg); }
body.docs header.site .nav-docs { text-decoration:underline; text-decoration-color:var(--accent); text-underline-offset:.4em; }
#theme { background:none; border:0; padding:.2rem; cursor:pointer; color:var(--fg); font:inherit; font-size:var(--fs-small); }
#theme:hover { color:var(--accent); }
#theme svg { width:1em; height:1em; vertical-align:-.13em; margin-right:.38em; }

main { display:block; max-width:72rem; margin:0 auto; padding:2.5rem 1.25rem 3rem; overflow-wrap:break-word; }
h1, h2, h3 { font-family:var(--mono); line-height:1.25; }
h1 { font-size:var(--fs-title); line-height:1.12; letter-spacing:-.025em; margin:0 0 1rem; }
main > p, main > .note, main > ul, main > ol { max-width:46rem; }
h2 { font-size:var(--fs-h2); line-height:1.2; letter-spacing:-.015em; margin:3rem 0 .8rem; }
h3 { font-size:var(--fs-base); margin:1.9rem 0 .5rem; }
p { margin:.7rem 0; } ul, ol { margin:.7rem 0; padding-left:1.3rem; } li { margin:.35rem 0; }
code { font-family:var(--mono); font-size:var(--fs-small); background:var(--box); border-radius:3px; padding:.05em .3em; overflow-wrap:anywhere; }
pre, .box { background:var(--box); border:1px solid var(--rule); border-radius:4px; padding:.8rem 1rem; margin:.8rem 0; overflow-x:auto; }
pre { font:var(--fs-small)/1.55 var(--mono); white-space:pre-wrap; overflow-wrap:anywhere; }
.lead { font-family:var(--mono); font-size:var(--fs-title); font-weight:700; line-height:1.25; margin:0 0 1rem; }
.note { border-left:3px solid var(--accent); padding:.1rem 0 .1rem 1rem; margin:1.2rem 0; }
details { margin-top:2.2rem; } summary { cursor:pointer; color:var(--dim); }

/* Prompts to paste into an agent, with a copy button. */
pre.prompt { position:relative; padding:1rem 1.1rem 3rem; }
.copy { position:absolute; right:.7rem; bottom:.6rem; background:var(--fg); color:var(--bg); border:0; border-radius:3px; font:700 15px/1.3 var(--mono); padding:.2rem .7rem; cursor:pointer; }

.fill { color:var(--accent); font-weight:700; }
.next { display:flex; flex-wrap:wrap; gap:.6rem 1.6rem; margin:1.6rem 0; font-family:var(--mono); font-size:var(--fs-small); }

/* Room transcripts. */
.msg { padding:.5rem 0; border-top:1px solid var(--line); } .msg:first-child { border-top:0; }
.msg .who { color:var(--accent); font-weight:600; font-family:var(--mono); font-size:var(--fs-small); } .msg .meta { color:var(--dim); font-size:var(--fs-fine); font-family:var(--mono); }
.msg.system { color:var(--dim); font-size:var(--fs-small); } .msg .body { white-space:pre-wrap; overflow-wrap:anywhere; }

/* Tables: full width, readable cells; wide ones scroll inside their own box. */
.table { overflow-x:auto; margin:1rem 0; }
table { width:100%; border-collapse:collapse; font-size:var(--fs-small); line-height:1.5; }
th, td { text-align:left; vertical-align:top; padding:.5rem .7rem .5rem 0; border-bottom:1px solid var(--line); }
th { font-weight:600; color:var(--dim); border-bottom-color:var(--rule); }
td code, th code { overflow-wrap:normal; white-space:nowrap; font-size:1em; }
h1 code, h2 code, h3 code { font-size:1em; }

/* Docs: contents and search on the left, one readable column on the right. */
.docs-layout { display:grid; grid-template-columns:15.5rem minmax(0,1fr); gap:3rem; max-width:72rem; margin:0 auto; padding:0 1.25rem; }
.docs-layout main { margin:0; padding:2.5rem 0 3rem; max-width:42rem; }
/* The sidebar scrolls on its own, which clips anything drawn outside it: a few pixels of room keep
   the search box's focus ring whole. */
.sidebar { position:sticky; top:0; align-self:start; max-height:100vh; overflow-y:auto; padding:2.2rem 5px 2rem; margin:0 -5px; font-size:var(--fs-small); }
.search input { width:100%; font:inherit; font-size:var(--fs-small); color:var(--fg); background:var(--box); border:1px solid var(--rule); border-radius:6px; padding:.45rem .6rem; }
.search input::placeholder { color:var(--dim); }
#results { list-style:none; padding:0; margin:.6rem 0 0; }
#results li { margin:0; } #results a { display:block; padding:.45rem .5rem; border-radius:5px; color:var(--fg); text-decoration:none; }
#results a:hover, #results a:focus-visible, #results a.first { background:var(--hi); }
#results .where { display:block; color:var(--dim); font-size:var(--fs-fine); }
#results .snip { display:block; color:var(--dim); font-size:var(--fs-fine); margin-top:.1rem; }
#results .none { color:var(--dim); padding:.4rem .5rem; }
.toc { margin-top:1.3rem; } .toc summary { display:none; }
.toc ul { list-style:none; padding:0; margin:0; } .toc li { margin:0; }
.toc a { display:block; padding:.22rem 0; color:var(--dim); text-decoration:none; line-height:1.35; }
.toc a:hover { color:var(--fg); }
.toc .page { color:var(--fg); font-weight:600; margin-top:.5rem; }
.toc .page[aria-current] { color:var(--accent); }
.toc ul ul { padding-left:.8rem; border-left:1px solid var(--line); margin:.15rem 0 .4rem; }
.doc h2, .doc h3 { scroll-margin-top:1rem; }
.anchor { margin-left:.4rem; color:var(--rule); text-decoration:none; font-weight:400; opacity:0; }
h2:hover .anchor, h3:hover .anchor, .anchor:focus-visible { opacity:1; }

@media (max-width: 58rem) {
  .docs-layout { display:block; }
  .sidebar { position:static; max-height:none; padding:1.4rem 5px 0; }
  .toc { border:1px solid var(--line); border-radius:6px; padding:.2rem .8rem; }
  .toc summary { display:list-item; padding:.4rem 0; }
  .docs-layout main { padding-top:1.5rem; }
}
@media (max-width: 30rem) { header.site nav { gap:1rem; } }
footer.site { max-width:72rem; margin:3rem auto 0; padding:1.4rem 1.25rem 2.5rem; font-size:var(--fs-small); }
footer.site p { margin:.3rem 0; }
@media print { header.site nav, .sidebar, .copy, .anchor { display:none; } .mark circle:last-of-type { fill:#000; } }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior:auto; } }
/* Rooms: the transcript is ruled, like the house rules, rather than boxed. */
#log.box, main > .box { background:none; border:0; border-top:3px solid var(--fg); border-radius:0; padding:0; overflow:visible; }
.msg { padding:.75rem 0; border-top:1px solid var(--line); }
.msg:first-child { border-top:0; }
@media (max-width: 30rem) { .brand { font-size:17px; } header.site nav { font-size:14px; gap:.6rem; } }

/* The front page: production's monospace throughout, the room filling up on the first screen. */
body.home { font:19px/1.55 var(--mono); }
body.home main { padding-top:0; }
body.home .hero { min-height:calc(100svh - 4.6rem); display:flex; flex-direction:column; justify-content:center; padding-bottom:2rem; }
#house { display:block; width:100%; height:min(46vh,430px); }
body.home .count { font-weight:700; font-size:19px; margin:.6rem 0 0; min-height:1.6em; max-width:none; }
body.home .count b { color:var(--accent); }
body.home h1 { font-size:clamp(2.5rem,7.2vw,6.4rem); line-height:1.04; letter-spacing:-.04em; margin:.6rem 0 1.2rem; }
body.home .lead { font-size:clamp(1.15rem,1.75vw,1.45rem); font-weight:400; line-height:1.45; margin:0; max-width:34em; }
body.home h2 { font-size:var(--fs-title); line-height:1.12; letter-spacing:-.025em; margin:6rem 0 1.8rem; }
body.home .pair { display:grid; grid-template-columns:1fr 1fr; gap:2.4rem; }
body.home .pair .inv { display:grid; grid-template-rows:subgrid; grid-row:span 2; row-gap:.7rem; }
body.home .inv h3 { font-size:19px; line-height:1.3; margin:0 0 .7rem; }
body.home .pair .inv h3 { margin:0; }
body.home pre.prompt { margin:0; font:400 clamp(1.05rem,1.45vw,1.2rem)/1.5 var(--mono); padding:1.2rem 1.3rem 3.4rem; }
body.home .conn, body.home main > .dim { font-size:17px; max-width:none; color:var(--fg); margin:1.5rem 0 0; }
body.home .rules { list-style:none; margin:0; padding:0; max-width:none; }
body.home .rules li { display:grid; grid-template-columns:2.5ch 1fr; gap:1.2ch; align-items:baseline; margin:0; padding:1.05rem 0; border-top:3px solid currentColor; }
body.home .rules b, body.home .rules p, body.home .not, body.home .end { font-size:clamp(1.1rem,1.6vw,1.3rem); line-height:1.45; margin:0; }
body.home .rules p { max-width:none; }
body.home .not, body.home .end { max-width:none; }
body.home .end { margin-top:.6rem; }
body.home footer.site { font-size:16px; }
@media (max-width: 700px) { body.home .pair { grid-template-columns:1fr; } #house { height:36vh; } body.home h2 { margin-top:4.5rem; } }
