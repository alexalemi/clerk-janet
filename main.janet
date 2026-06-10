# Public entry point — clerk-serve ties read+eval+render+server+watch
# into one running session. Mirrors clerk-racket/serve.rkt.
#
# Two modes:
#   - File mode: (clerk-serve "foo.janet")
#   - Directory mode: (clerk-serve "./notebooks") — any .janet save
#     under the tree switches the view to that file.

(import spork/json)
(import ./eval)
(import ./render)
(import ./server)
(import ./watch)

(defn- result->row [r]
  (def c (r :cell))
  {"id" (c :id)
   "html" (render/render-cell r)
   "status" (if (r :error) "error" "fresh")
   "index" (c :index)})

(defn- init-msg [path results]
  (json/encode
    {"type" "init"
     "title" (string path)
     "cells" (tuple ;(map result->row results))}))

(defn- error-msg [message]
  (json/encode {"type" "error" "message" message}))

(defn- recompute [path]
  (def res (try (eval/eval-notebook path) ([err] [:err err])))
  (if (and (tuple? res) (= (get res 0) :err))
    (error-msg (string (get res 1)))
    (init-msg path res)))

(defn- initial-active [path]
  "Pick the file the live view should start with. For a directory,
  use the most-recently-modified .janet under it."
  (def st (try (os/stat path) ([_] nil)))
  (cond
    (nil? st) (error (string "no such file or directory: " path))
    (= (st :mode) :file) path
    (= (st :mode) :directory)
    (let [files (watch/find-notebooks path)]
      (when (empty? files)
        (error (string "no .janet files found under " path)))
      (reduce
        (fn [acc p]
          (let [a-mod ((os/stat acc) :modified)
                p-mod ((os/stat p) :modified)]
            (if (> p-mod a-mod) p acc)))
        (first files) files))
    (error (string "not a file or directory: " path))))

(defn clerk-serve [path &named port]
  (default port 7777)
  # Resolve the active notebook first — `initial-active` validates the
  # path and raises a readable error on a missing file, whereas calling
  # ((os/stat path) :mode) on nil crashes with "expected integer key".
  (def active (initial-active path))
  (def is-dir (= ((os/stat path) :mode) :directory))
  (printf "clerk-janet: serving %s%s on http://localhost:%d"
          path (if is-dir " (directory mode)" "") port)
  (def srv (server/make-server :port port
                               :title (string active " — clerk")))
  (def active-box @{:path active})
  (defn refresh [changed]
    (put active-box :path changed)
    (def bytes (recompute changed))
    ((srv :set-init) bytes)
    ((srv :broadcast) bytes))
  (refresh (active-box :path))
  (def stop-watch (watch/watch-tree path refresh))
  (fn []
    (stop-watch)
    ((srv :stop))))

(defn- parse-args [argv]
  "Very small flag parser: --port N. Returns [path port]."
  (var port 7777)
  (var path nil)
  (def args (drop 1 argv))
  (var i 0)
  (def n (length args))
  (while (< i n)
    (def a (get args i))
    (cond
      (= a "--port")
      (do
        (def v (get args (+ i 1)))
        (def p (and v (scan-number v)))
        (unless p
          (eprint "clerk-janet: --port requires a number")
          (os/exit 1))
        (set port p)
        (+= i 2))
      (set path a)
      (++ i)))
  [path port])

(defn- block-forever []
  "Sit on the event loop forever. Ctrl-C exits via SIGINT; the previous
  `(file/read stdin :line)` approach was brittle — *anything* that
  EOF'd stdin (shell backgrounding, terminal close, pane drop, even an
  accidental Ctrl-D) would silently shut the server down."
  (eprint "Ctrl-C to stop.")
  (forever (ev/sleep 3600)))

(defn main [& argv]
  (def [path port] (parse-args argv))
  (unless path
    (eprint "usage: clerk-janet <file-or-dir> [--port N]")
    (os/exit 1))
  # Top-level catch: if anything inside crashes the main fiber, we want
  # the user to see *why* instead of staring at a process that just
  # vanished. Without this, an uncaught error in clerk-serve (notebook
  # eval, server bind, watcher start) exits with no breadcrumb.
  (try
    (do
      (def stop (clerk-serve path :port port))
      (block-forever)
      (stop))
    ([err fib]
      (eprintf "clerk-janet: fatal: %s" err)
      (debug/stacktrace fib err "")
      (os/exit 1))))
