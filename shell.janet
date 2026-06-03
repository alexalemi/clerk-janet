# HTML shell + CSS shared by live and static modes.

(def shell-css
  ``
  html{background:#f8f8f8}
  body{font:15px/1.55 system-ui,-apple-system,Segoe UI,sans-serif;
       max-width:780px;margin:2.5em auto;padding:0 1.25em;
       color:#383838;background:#f8f8f8}
  a{color:#804040;text-decoration:none}
  a:hover{text-decoration:underline}
  .clerk-cell{border-left:3px solid #ddd;padding:.5em .8em;margin:1em 0}
  .clerk-cell[data-cell-kind=expr]{border-left-color:#3a7}
  .clerk-cell[data-cell-kind=define]{border-left-color:#37a}
  .clerk-cell[data-cell-kind=meta]{border-left-color:#bbb}
  .clerk-cell[data-status=error]{border-left-color:#c06050}
  pre.clerk-source{background:transparent;color:#383838;
                   padding:.2em 0;margin:0 0 .2em;overflow:auto;
                   font:13px/1.5 'JetBrains Mono','Fira Code','Inconsolata',
                                  'DejaVu Sans Mono',ui-monospace,monospace}
  pre.clerk-value{background:transparent;color:#383838;
                  padding:.1em 0 .1em 1em;margin:0;overflow:auto;
                  border-left:2px solid #d0c8b8;
                  font:13px/1.5 'JetBrains Mono','Fira Code','Inconsolata',
                                 'DejaVu Sans Mono',ui-monospace,monospace}
  pre.clerk-error{background:#fbe3e0;color:#6a1f1f;
                  padding:.5em .7em;margin:0;overflow:auto;
                  font:13px/1.5 'JetBrains Mono','Fira Code','Inconsolata',
                                 'DejaVu Sans Mono',ui-monospace,monospace;
                  border-radius:2px}
  pre.clerk-stdout{background:transparent;color:#5a5a5a;
                   padding:.1em 0 .1em 1em;margin:0;overflow:auto;
                   border-left:2px dashed #c8c0b0;
                   font:13px/1.5 'JetBrains Mono','Fira Code','Inconsolata',
                                  'DejaVu Sans Mono',ui-monospace,monospace}
  pre.clerk-stderr{background:transparent;color:#7a4a1a;
                   padding:.1em 0 .1em 1em;margin:0;overflow:auto;
                   border-left:2px dashed #c8a050;
                   font:13px/1.5 'JetBrains Mono','Fira Code','Inconsolata',
                                  'DejaVu Sans Mono',ui-monospace,monospace}
  .clerk-md{border-left-color:transparent;padding:.2em 0}
  .clerk-md .clerk-md-body{
    font-family:'Linux Libertine O','Libertinus Serif',
                'Source Serif 4','Source Serif Pro',
                Georgia,'Times New Roman',serif;
    font-size:1.15em;line-height:1.55;color:#383838;max-width:64ch}
  .clerk-md .clerk-md-body p{margin:.6em 0;text-align:justify;hyphens:auto}
  .clerk-md .clerk-md-body h1,
  .clerk-md .clerk-md-body h2,
  .clerk-md .clerk-md-body h3{
    font-family:'Linux Biolinum O','Libertinus Sans',
                'Source Sans 3','Source Sans Pro',
                system-ui,-apple-system,Segoe UI,sans-serif;
    font-weight:normal;color:#2a2a2a;line-height:1.2}
  .clerk-md .clerk-md-body h1{font-size:1.9em;margin:1.5em 0 .4em}
  .clerk-md .clerk-md-body h2{font-size:1.45em;margin:1.4em 0 .3em}
  .clerk-md .clerk-md-body h3{font-size:1.2em;margin:1.2em 0 .3em}
  .clerk-md code{color:#5a3a2a;
                  font:.9em 'JetBrains Mono','Fira Code','Inconsolata',
                             'DejaVu Sans Mono',ui-monospace,monospace}
  #status{position:fixed;top:.5em;right:1em;
          font:11px/1 ui-monospace,monospace;padding:.25em .55em;
          background:#eae5d8;color:#7a6a4a;border-radius:3px}
  #status.live{background:#d6e6d6;color:#2c4a2c}
  #status.dead{background:#f0c8c0;color:#6a1f1f}
  /* Markdown list spacing */
  .clerk-md .clerk-md-body ul,
  .clerk-md .clerk-md-body ol{margin:.3em 0 .3em 1.5em;padding:0}
  .clerk-md .clerk-md-body li{margin:.1em 0}
  /* Syntax highlighting palette (Sarabander / Google-Code-Prettify) */
  pre.clerk-source .pln{color:#606060}
  pre.clerk-source .kwd{color:#4070a0}
  pre.clerk-source .lit{color:#509040}
  pre.clerk-source .str{color:#985098}
  pre.clerk-source .com{color:#b08050;font-style:italic}
  pre.clerk-source .opn,pre.clerk-source .clo{color:#989898}
  pre.clerk-source .pun{color:#909020}
  pre.clerk-source .atn{color:#606}
  pre.clerk-source .err{color:#c06050}
  ``)

(def math-tags
  ``
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
  ``)

(def math-render-script
  ``
  <script>
    window.clerkRenderMath = function(root) {
      if (typeof renderMathInElement !== 'function') return;
      var els = (root || document).querySelectorAll('.clerk-md .clerk-md-body');
      els.forEach(function(el) {
        renderMathInElement(el, {
          delimiters: [
            { left: '$$', right: '$$', display: true },
            { left: '$', right: '$', display: false },
            { left: '\\[', right: '\\]', display: true },
            { left: '\\(', right: '\\)', display: false }
          ],
          throwOnError: false
        });
      });
    };
    document.addEventListener('DOMContentLoaded', function() {
      var poll = setInterval(function() {
        if (typeof renderMathInElement === 'function') {
          clearInterval(poll);
          window.clerkRenderMath();
        }
      }, 50);
    });
  </script>
  ``)

(def font-link-tags
  ``
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&family=Source+Sans+3:wght@400;500&display=swap">
  ``)

(defn live-shell-html [title]
  (string
    `<!doctype html><html><head><meta charset="utf-8"><title>` title `</title>`
    font-link-tags
    math-tags
    `<style>` shell-css `</style>`
    math-render-script
    `</head><body>`
    `<div id="status">connecting…</div>`
    `<main id="cells"></main>`
    `<script src="/client.js"></script>`
    `</body></html>`))

(defn static-shell-html [title body]
  (string
    `<!doctype html><html><head><meta charset="utf-8"><title>` title `</title>`
    font-link-tags
    math-tags
    `<style>` shell-css `</style>`
    math-render-script
    `</head><body>`
    `<main id="cells">` body `</main>`
    `</body></html>`))

(def client-js
  ``
  (function () {
    var statusEl = document.getElementById("status");
    var cellsEl  = document.getElementById("cells");
    function setStatus(t, cls) { statusEl.textContent = t; statusEl.className = cls || ""; }
    function parseFragment(html) {
      var tmp = document.createElement("div");
      tmp.innerHTML = html;
      return tmp.children;
    }
    function applyInit(msg) {
      if (msg.title) document.title = msg.title + " — clerk";
      cellsEl.replaceChildren();
      for (var i = 0; i < msg.cells.length; i++) {
        var nodes = parseFragment(msg.cells[i].html);
        while (nodes.length) cellsEl.appendChild(nodes[0]);
      }
      if (typeof window.clerkRenderMath === "function") {
        window.clerkRenderMath();
      }
    }
    function applyMessage(msg) {
      if (msg.type === "init") applyInit(msg);
      else if (msg.type === "error") {
        var pre = document.createElement("pre");
        pre.className = "clerk-error";
        pre.textContent = msg.message || "(empty error)";
        cellsEl.replaceChildren(pre);
      }
    }
    function connect() {
      var es = new EventSource("/events");
      setStatus("connecting…");
      es.onopen = function() { setStatus("live", "live"); };
      es.onmessage = function(ev) {
        try { applyMessage(JSON.parse(ev.data)); }
        catch (e) { console.error("bad message", ev.data, e); }
      };
      es.onerror = function() { setStatus("disconnected — retrying…", "dead"); };
    }
    connect();
  })();
  ``)
