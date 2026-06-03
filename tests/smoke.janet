# End-to-end smoke test.
#
# Builds a tiny notebook in a tmpdir, runs it through the full pipeline,
# and asserts on the resulting cell statuses + values. Boots the live
# server briefly to verify nothing crashes on startup.

(import ../eval :as ev)
(import ../render)
(import ../viewer)
(import ../main :as m)

(defn- fail [msg] (eprintf "FAIL: %s" msg) (os/exit 1))

(defn- assert-eq [a b msg]
  (unless (deep= a b)
    (eprintf "FAIL: %s\n  expected: %p\n  got:      %p" msg b a)
    (os/exit 1))
  (printf "OK: %s" msg))

# --- Build a small notebook in /tmp ---------------------------------

(def tmp (string (os/getenv "TMPDIR" "/tmp") "/clerk-janet-smoke.janet"))

(defn- write-source [body]
  (spit tmp body))

(write-source ``
# # Smoke
#
# A small smoke-test notebook.

(def x 7)

(* x x)
``)

# --- Pipeline test --------------------------------------------------

(def results (ev/eval-notebook tmp))
(assert-eq (length results) 3 "three cells (md + def + expr)")

(def kinds (map |(($ :cell) :kind) results))
(assert-eq kinds @[:md :define :expr] "expected kind sequence")

(def values (map |($ :value) results))
(assert-eq (values 1) 7 "(def x 7) bound to 7")
(assert-eq (values 2) 49 "(* x x) yields 49")

# --- Per-cell error isolation ---------------------------------------

(write-source ``
(def good 1)
(error "bad cell")
(+ good good)
``)

(def errs (ev/eval-notebook tmp))
(assert-eq (length errs) 3 "three cells with error in middle")
(assert-eq (truthy? ((errs 0) :error)) false "good cell 0 has no error")
(assert-eq (truthy? ((errs 1) :error)) true  "error cell 1 has error")
(assert-eq (truthy? ((errs 2) :error)) false "good cell 2 still runs after error")
(assert-eq ((errs 2) :value) 2 "cell 2 evaluates after the error")

# --- Stdout capture --------------------------------------------------

(write-source ``
(print "hello world")
``)

(def out-res (ev/eval-notebook tmp))
(assert-eq (string/trim ((out-res 0) :stdout)) "hello world"
           "print captured to stdout")

# --- Viewer registry -------------------------------------------------

(viewer/register-viewer! :smoke-marker
                         (fn [v] (= v :smoke-marker))
                         (fn [_] "<span>SMOKE</span>"))
(def html (viewer/render-value :smoke-marker))
(assert-eq html "<span>SMOKE</span>" "custom viewer registered + used")

# --- Markdown link rendering (regression: nested <a> double-wrap) ---

(write-source ``
# Visit [the docs](https://example.com/x) and also https://example.com/y.
``)

(def link-html ((ev/eval-notebook tmp) 0))
(def rendered (render/render-cell link-html))
(assert-eq (string/find "<a href=\"<a " rendered) nil
           "explicit [text](url) link not double-wrapped by autolink pass")
(assert-eq (truthy? (string/find "<a href=\"https://example.com/x\">the docs</a>" rendered)) true
           "explicit link renders cleanly")
(assert-eq (truthy? (string/find "<a href=\"https://example.com/y\">https://example.com/y</a>" rendered)) true
           "bare URL on same line still autolinks")

# --- Server boot ----------------------------------------------------

(def stop (m/clerk-serve tmp :port 7889))
(ev/sleep 0.3)
(stop)
(print "OK: server booted + stopped cleanly")

(os/rm tmp)
(print "Smoke test passed.")
