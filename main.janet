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
  (def is-dir (= ((os/stat path) :mode) :directory))
  (printf "clerk-janet: serving %s%s on http://localhost:%d"
          path (if is-dir " (directory mode)" "") port)
  (def active (initial-active path))
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

(defn main [& argv]
  (def file (or (get argv 1)
                (do (eprint "usage: clerk-janet <file-or-dir>") (os/exit 1))))
  (def stop (clerk-serve file))
  (eprint "press enter to stop.")
  (file/read stdin :line)
  (stop))
