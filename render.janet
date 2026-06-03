# Render cell-results to HTML.

(import ./cell)

(defn- html-escape [s]
  (def s (string s))
  (->> s
       (string/replace-all "&" "&amp;")
       (string/replace-all "<" "&lt;")
       (string/replace-all ">" "&gt;")))

(defn- pp [v]
  (string/format "%p" v))

# --- Tiny Markdown subset --------------------------------------------

(def- header3-peg (peg/compile ~(* "###" (some (set " \t")) (capture (any 1)))))
(def- header2-peg (peg/compile ~(* "##"  (some (set " \t")) (capture (any 1)))))
(def- header1-peg (peg/compile ~(* "#"   (some (set " \t")) (capture (any 1)))))
(def- blank-peg   (peg/compile ~(* (any (set " \t")) -1)))

(defn- inline [s]
  (def s (html-escape s))
  # `code` first so we don't reprocess inside
  (def s (peg/replace-all
           ~(* "`" (capture (some (if-not "`" 1))) "`")
           (fn [_ inner] (string "<code>" inner "</code>"))
           s))
  (def s (peg/replace-all
           ~(* "**" (capture (some (if-not "**" 1))) "**")
           (fn [_ inner] (string "<strong>" inner "</strong>"))
           s))
  (def s (peg/replace-all
           ~(* "*" (capture (some (if-not "*" 1))) "*")
           (fn [_ inner] (string "<em>" inner "</em>"))
           s))
  s)

(defn- md->html [text]
  (def lines (string/split "\n" text))
  (def out @"")
  (var para @[])
  (defn flush-para []
    (when (not (empty? para))
      (buffer/push-string out "<p>" (inline (string/join para " ")) "</p>")
      (array/clear para)))
  (each line lines
    (cond
      (peg/match blank-peg line) (flush-para)
      (let [m (peg/match header3-peg line)]
        (when m (flush-para)
          (buffer/push-string out "<h3>" (inline (m 0)) "</h3>")))
      :ok
      (let [m (peg/match header2-peg line)]
        (when m (flush-para)
          (buffer/push-string out "<h2>" (inline (m 0)) "</h2>")))
      :ok
      (let [m (peg/match header1-peg line)]
        (when m (flush-para)
          (buffer/push-string out "<h1>" (inline (m 0)) "</h1>")))
      :ok
      (array/push para line)))
  (flush-para)
  (string out))

# --- Value rendering -------------------------------------------------

(defn- render-value [v]
  (cond
    (nil? v) ""
    (function? v) (string "<pre class=\"clerk-value\">"
                          (html-escape (string/format "%q" v))
                          "</pre>")
    (string "<pre class=\"clerk-value\">"
            (html-escape (pp v))
            "</pre>")))

(defn- render-source [c]
  (if (cell/cell-hidden-code? c)
    ""
    (string "<pre class=\"clerk-source\">"
            (html-escape (or (c :source-str) (pp (c :source))))
            "</pre>")))

(defn- render-output [r]
  (def o (r :stdout))
  (def e (r :stderr))
  (string
    (if (and o (not (empty? o)))
      (string "<pre class=\"clerk-stdout\">" (html-escape o) "</pre>")
      "")
    (if (and e (not (empty? e)))
      (string "<pre class=\"clerk-stderr\">" (html-escape e) "</pre>")
      "")))

(defn- render-value-block [r]
  (def c (r :cell))
  (cond
    (r :error)
    (string "<pre class=\"clerk-error\">" (html-escape (r :error)) "</pre>")
    (cell/cell-hidden-result? c) ""
    (render-value (r :value))))

(defn render-cell [r]
  (def c (r :cell))
  (def status (if (r :error) "error" "fresh"))
  (cond
    (= (c :kind) :md)
    (string/format
      `<section id="cell-%s" class="clerk-cell clerk-md" data-cell-id="%s" data-cell-kind="md" data-status="%s"><div class="clerk-md-body">%s</div></section>`
      (c :id) (c :id) status (md->html (or (c :prose) "")))

    (string/format
      `<section id="cell-%s" class="clerk-cell" data-cell-id="%s" data-cell-kind="%s" data-status="%s">%s%s%s</section>`
      (c :id) (c :id) (string (c :kind)) status
      (render-source c)
      (render-output r)
      (render-value-block r))))

(defn render-cells [results]
  (def out @"")
  (each r results
    (buffer/push-string out (render-cell r)))
  (string out))
