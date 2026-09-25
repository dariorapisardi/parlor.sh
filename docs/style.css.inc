:root { --bg:#fbfaf7; --fg:#131210; --dim:#4d4a43; --line:#b4b0a3; --accent:#7a3210; --box:#f2efe8; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#161513; --fg:#f3f0e9; --dim:#bbb7ac; --line:#59564e; --accent:#f0a170; --box:#1f1e1b; } }
:root[data-theme="dark"] { --bg:#161513; --fg:#f3f0e9; --dim:#bbb7ac; --line:#59564e; --accent:#f0a170; --box:#1f1e1b; }
#theme { position:absolute; top:1rem; right:1rem; background:none; border:0; padding:.3rem; cursor:pointer; color:var(--dim); font:inherit; font-size:.8rem; }
#theme:hover, #theme:focus-visible { color:var(--fg); }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }
main { max-width:78ch; margin:0 auto; padding:2.5rem 1rem 4rem; }
h1 { font-size:1.35rem; margin:0 0 .25rem; } h1 a { color:inherit; text-decoration:none; }
.lead { font-size:1.2rem; font-weight:700; margin:1.4rem 0 .4rem; }
ol { margin:.6rem 0; padding-left:1.6rem; } li { margin:.3rem 0; }
h2 { font-size:1rem; margin:2.2rem 0 .6rem; color:var(--accent); font-weight:600; text-transform:uppercase; letter-spacing:.06em; }
p { margin:.6rem 0; } a { color:var(--accent); } .dim { color:var(--dim); }
main { overflow-wrap:anywhere; } /* a long URL, command or topic must wrap, not scroll the page sideways */
pre, .box { background:var(--box); border:1px solid var(--line); border-radius:6px; padding:.8rem 1rem; overflow-x:auto; word-break:break-word; margin:.6rem 0; }
pre { white-space:pre-wrap; }
pre.prompt { position:relative; padding-right:4.5rem; }
.copy { position:absolute; top:.5rem; right:.5rem; background:var(--bg); border:1px solid var(--line); border-radius:4px; color:var(--dim); font:inherit; font-size:.75rem; padding:.1rem .45rem; cursor:pointer; }
.copy:hover, .copy:focus-visible { color:var(--fg); }
.note { border-left:3px solid var(--accent); padding:.1rem 0 .1rem .9rem; margin:1.2rem 0; }
.msg { padding:.45rem 0; border-top:1px solid var(--line); } .msg:first-child { border-top:0; }
.msg .who { color:var(--accent); font-weight:600; } .msg .meta { color:var(--dim); font-size:.85em; }
.msg.system { color:var(--dim); font-size:.9em; } .msg .body { white-space:pre-wrap; word-break:break-word; }
details { margin-top:2rem; } summary { cursor:pointer; color:var(--dim); }
footer { margin-top:3rem; color:var(--dim); font-size:.85em; border-top:1px solid var(--line); padding-top:1rem; }
h1 .mark { width:1.25em; height:1.25em; vertical-align:-.28em; margin-right:.34em; }
@media print { h1 .mark circle:last-of-type { fill:#000; } }
