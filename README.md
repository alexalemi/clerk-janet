# clerk-janet

Live, browser-rendered notebooks for [Janet](https://janet-lang.org/)
— a port of [clerk-racket](https://github.com/alexalemi/clerk-racket),
which in turn carries forward the design of nextjournal's original
[Clerk](https://github.com/nextjournal/clerk) for Clojure.

A notebook is an **ordinary Janet file**. `#`-line comments become
Markdown, code cells get syntax-highlighted, values render inline,
and saving the file live-updates the browser. The file still runs
standalone with `janet file.janet` — clerk just gives it a richer
view.

```janet
# # Pythagoras
#
# A quick demo. The text above is **Markdown** — written as
# ordinary `#`-line comments.

(defn sq [x] (* x x))

(def a 3)
(def b 4)

(math/sqrt (+ (sq a) (sq b)))
```

`janet main.janet pythagoras.janet` → browser shows the prose,
the defines, the value `5`. Edit, save, watch it update.

## Install

Two options.

**As a `clerk-janet` binary on your `PATH`** (recommended):

```sh
git clone https://github.com/alexalemi/clerk-janet.git
cd clerk-janet
sudo jpm install
```

`jpm install` builds a self-contained ELF that bundles `main.janet`
plus all transitive imports and the native `spork/json.so`, then
drops it into the install prefix (typically `/usr/local/bin/`).
Spork is fetched automatically from the `:dependencies` list in
`project.janet`.

**As a checkout you run with `janet`** (good for hacking on
clerk-janet itself):

```sh
git clone https://github.com/alexalemi/clerk-janet.git
cd clerk-janet
jpm --local deps   # puts spork in ./jpm_tree, no sudo needed
```

## Use

If you installed the binary:

```sh
# Live server on a single file (default port 7777)
clerk-janet examples/tour.janet

# Directory mode: watch every .janet under a tree. Saving any
# of them switches the live view to that file.
clerk-janet examples/

# Pick a different port
clerk-janet examples/tour.janet --port 8000
```

From a checkout, replace `clerk-janet` with `janet main.janet`:

```sh
janet main.janet examples/tour.janet
janet main.janet examples/

# Build a static HTML snapshot (no live server)
janet -e '
  (import ./eval)
  (import ./render)
  (import ./shell)
  (def res (eval/eval-notebook "examples/tour.janet"))
  (spit "out.html" (shell/static-shell-html "tour" (render/render-cells res)))'
```

## How notebooks work

A clerk-janet notebook is plain Janet source:

| Source                                | Renders as                                   |
|---------------------------------------|----------------------------------------------|
| `#` line comments (top level)         | Markdown prose                               |
| `(def x ...)` / `(defn ...)`          | Code cell + the bound value                  |
| `(any-expression)`                    | Code cell + the value it produces            |
| `(import ...)` / `(use ...)`          | Code cell, no value                          |
| `(print ...)`, `(printf ...)`         | Code cell + captured stdout shown inline     |

### Markdown supported

- Headers: `#`, `##`, `###`
- Paragraphs (blank line separates)
- **Bold** (`**text**`), *italic* (`*text*`), `` `code` ``
- Unordered lists (`-`, `*`, `+`) and ordered lists (`1.`, `2.`, …)
- Links: `[text](url)` and bare URLs become clickable
- LaTeX math: `$inline$` and `$$display$$` via KaTeX

### Typography

Same Sarabander-inspired design as clerk-racket: serif body, sans
headings, off-white background, brick-red links, reading-width
prose. Falls back through Linux Libertine → Source Serif 4 → Georgia
based on what's installed.

Source blocks get server-side syntax highlighting via a hand-rolled
PEG tokenizer, emitted as class-tagged spans with the same color
palette as Sarabander's SICP edition (`.kwd` blue, `.lit` green,
`.pun` olive, `.opn`/`.clo` light gray, `.str` purple, `.com` tan).

### Captured output

`(print ...)`, `(printf ...)`, anything else that writes to
`(dyn :out)` during a cell's evaluation is captured into the cell's
rendered output rather than dumped to the terminal. `(eprint ...)`
captures to a separate stderr block in a warning color.

### Directives

Three directives, written as `# @clerk:NAME` immediately above a form:

- `hide-code` — don't show the source of this cell
- `hide-result` — don't show the value
- `viewer NAME` — force a specific viewer (currently scaffolded, not
  fully wired)

```janet
# @clerk:hide-code
(import spork/json)
```

## Design

Mostly identical to clerk-racket. Janet-specific choices worth
flagging:

- **Per-cell error isolation via `protect`.** Each cell's form is
  compiled and run inside `protect`, so a runtime error in cell 3
  shows an error block in cell 3 — cells 4, 5, 6 still render their
  values.

- **Stdout/stderr capture via `with-dyns`.** Janet's `print` family
  writes to `(dyn :out)`. Parameterizing it around each cell's eval
  redirects all output to a buffer.

- **SSE instead of WebSocket.** Spork doesn't ship a WS module in
  the standard install, but our wire protocol is one-way anyway
  (server → browser). Server-Sent Events are HTTP, work with raw
  `spork/http`, and get free auto-reconnect from the browser's
  `EventSource` API.

- **mtime polling for file watch.** Janet doesn't ship inotify
  bindings. Polling at ~250ms with mtime+size as the change tuple
  works on every filesystem.

- **Form start-line tracking.** Janet's `parser/where` reports the
  *next* token position, not the previous form's start. To get
  correct start-lines for forms (after blank/comment lines), we
  feed the parser line-by-line and snapshot the moment `status`
  transitions out of `:root` into `:pending` or to a complete form.

## Status

This is v0.1. Examples in `examples/` (`tour.janet`,
`pythagoras.janet`) cover every feature.

Not yet:
- Custom viewer registry
- Rich-value rendering (SVG / images / plots) — Janet's value
  ecosystem doesn't have a `file/convertible`-equivalent protocol
- A standalone `clerk-janet` CLI binary (currently `janet main.janet
  <file>`)

## About this code

This was **vibecoded** through extended live conversation with
Claude (Anthropic). Heavily commented at the design-decision level,
with explicit notes about *why* something is the way it is rather
than just *what* it does. Treat the comments as a partial design
journal as well as documentation.

## License

MIT.
