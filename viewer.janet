# Viewer registry.
#
# A viewer is `{:name kw :pred fn :render fn}`. The registry is an
# array of viewers; lookup walks newest-first, so user `register-viewer!`
# calls override built-ins. There's also a *method-based* escape hatch:
# any value carrying a `:render-html` method gets that called first,
# without going through the registry. This lets new types render
# themselves without registering a global viewer.

(defn- html-escape [s]
  (->> (string s)
       (string/replace-all "&" "&amp;")
       (string/replace-all "<" "&lt;")
       (string/replace-all ">" "&gt;")))

# Module-level mutable registry. Latest registration wins for the
# predicate walk. The :default viewer is always first (oldest), so it
# only fires if no later viewer matched. By-name lookup is a separate
# table — used when a `# @clerk:viewer NAME` directive forces a viewer.
(def registry @[])
(def by-name @{})

(defn register-viewer! [name pred render-fn]
  ``Register a viewer. `name` is a keyword used by the `viewer`
  directive; `pred` is `(value -> bool)`; `render-fn` is `(value -> html-string)`.``
  (def v {:name name :pred pred :render render-fn})
  (array/push registry v)
  (put by-name name v)
  v)

(defn lookup-viewer [name] (get by-name name))

# --- Built-in viewers ------------------------------------------------

(defn- pp [v] (string/format "%p" v))

(defn default-render [v]
  (string "<pre class=\"clerk-value\">" (html-escape (pp v)) "</pre>"))

# Tables / structs render as a 2-column key/value table.
(defn- dict-like? [v] (or (table? v) (struct? v)))

(defn- table-render-of-dict [v]
  (def rows @"")
  (each k (sorted (keys v))
    (buffer/push-string rows
      "<tr><th>" (html-escape (pp k)) "</th>"
      "<td>" (html-escape (pp (get v k))) "</td></tr>"))
  (string "<table class=\"clerk-table\"><tbody>" rows "</tbody></table>"))

(defn- uniform-dict-array? [v]
  (and (or (array? v) (tuple? v))
       (not (empty? v))
       (all dict-like? v)))

(defn- collect-keys [rows]
  "Union of keys across rows, preserving first-seen order."
  (def seen @{})
  (def out @[])
  (each row rows
    (each k (keys row)
      (unless (get seen k)
        (put seen k true)
        (array/push out k))))
  out)

(defn- table-render-of-rows [rows]
  (def ks (collect-keys rows))
  (def head @"")
  (each k ks
    (buffer/push-string head "<th>" (html-escape (pp k)) "</th>"))
  (def body @"")
  (each row rows
    (buffer/push-string body "<tr>")
    (each k ks
      (def cell (get row k ""))
      (buffer/push-string body "<td>" (html-escape (pp cell)) "</td>"))
    (buffer/push-string body "</tr>"))
  (string "<table class=\"clerk-table\"><thead><tr>" head "</tr></thead>"
          "<tbody>" body "</tbody></table>"))

(defn- table-render [v]
  (cond
    (dict-like? v) (table-render-of-dict v)
    (uniform-dict-array? v) (table-render-of-rows v)
    (default-render v)))

(defn- table-pred [v]
  (or (dict-like? v) (uniform-dict-array? v)))

# HTML viewer — value is a buffer/string that's already HTML.
(defn- html-render [v]
  (string "<div class=\"clerk-image\">" (string v) "</div>"))

# --- Method-based escape hatch --------------------------------------

(defn- method-render-html [v]
  ``If a value is callable like a method-table and has a `:render-html`
  method, use that. Returns nil if no such method.``
  (cond
    (table? v)
    (let [m (get v :render-html)]
      (when (function? m) (m v)))
    nil))

# --- Dispatcher ------------------------------------------------------

(defn- walk-registry [v]
  "Walk viewers newest-first, return the first match's render output."
  (def n (length registry))
  (var i (- n 1))
  (var out nil)
  (while (and (nil? out) (>= i 0))
    (def vw (get registry i))
    (when ((vw :pred) v) (set out ((vw :render) v)))
    (-= i 1))
  out)

(defn render-value [v &opt viewer-name]
  ``Render `v` to HTML. If `viewer-name` is set (e.g., from a `viewer`
  directive), force that viewer. Otherwise check for a method, then
  walk the registry newest-first.``
  (cond
    (nil? v) ""

    viewer-name
    (if-let [vw (lookup-viewer viewer-name)]
      ((vw :render) v)
      (default-render v))

    # Plain success path: method first, registry second, default last.
    (or (method-render-html v)
        (walk-registry v)
        (default-render v))))

# Register built-ins last (so they sit AFTER user registrations would,
# but the dispatcher walks newest-first — so user-registered viewers
# still override these via the array order).
(register-viewer! :default (fn [_] true) default-render)
(register-viewer! :table   table-pred    table-render)
(register-viewer! :html    (fn [v] (and (or (buffer? v) (string? v))
                                         (string/has-prefix? "<" (string v))))
                          html-render)
