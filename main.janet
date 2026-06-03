# Public entry point — clerk-serve! ties read+eval+render+server+watch
# into one running session. Mirrors clerk-racket/serve.rkt.

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
     "title" path
     "cells" (tuple ;(map result->row results))}))

(defn- error-msg [message]
  (json/encode {"type" "error" "message" message}))

(defn- recompute [path]
  (def res (try (eval/eval-notebook path) ([err] [:err err])))
  (if (and (tuple? res) (= (get res 0) :err))
    (error-msg (string (get res 1)))
    (init-msg path res)))

(defn clerk-serve [path &named port]
  (default port 7777)
  (printf "clerk-janet: serving %s on http://localhost:%d" path port)
  (def srv (server/make-server :port port :title (string path " — clerk")))
  (defn refresh []
    (def bytes (recompute path))
    ((srv :set-init) bytes)
    ((srv :broadcast) bytes))
  (refresh)
  (def stop-watch (watch/watch-file path refresh))
  (fn []
    (stop-watch)
    ((srv :stop))))

# CLI entry — `janet main.janet <file>` or `jpm run clerk -- <file>`
(defn main [& argv]
  (def file (or (get argv 1)
                (do (eprint "usage: clerk-janet <file>") (os/exit 1))))
  (def stop (clerk-serve file))
  (eprint "press enter to stop.")
  (file/read stdin :line)
  (stop))
