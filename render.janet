# Render cell-results to HTML.

(import ./cell)
(import ./highlight)
(import ./viewer)

(defn- html-escape [s]
  (def s (string s))
  (->> s
       (string/replace-all "&" "&amp;")
       (string/replace-all "<" "&lt;")
       (string/replace-all ">" "&gt;")))

(defn- pp [v]
  (string/format "%p" v))

# --- Markdown subset --------------------------------------------------

(def- header3-peg (peg/compile ~(* "###" (some (set " \t")) (capture (any 1)))))
(def- header2-peg (peg/compile ~(* "##"  (some (set " \t")) (capture (any 1)))))
(def- header1-peg (peg/compile ~(* "#"   (some (set " \t")) (capture (any 1)))))
(def- ul-item-peg
  (peg/compile ~(* (any (set " \t")) (set "-*+") (some (set " \t"))
                   (capture (any 1)))))
(def- ol-item-peg
  (peg/compile ~(* (any (set " \t")) (some :d) "." (some (set " \t"))
                   (capture (any 1)))))
(def- blank-peg (peg/compile ~(* (any (set " \t")) -1)))

(defn- inline [s]
  (def s (html-escape s))
  # Stash code spans behind NUL-placeholders so later passes leave them
  # alone (URLs/bold/italic inside backticks should NOT be reprocessed).
  (def stash @[])
  (def s
    (peg/replace-all
      ~(* "`" (capture (some (if-not "`" 1))) "`")
      (fn [_ inner]
        (array/push stash inner)
        (string "\0CODE" (- (length stash) 1) "\0"))
      s))
  # Explicit links: [text](url). Stash the produced <a> so the autolink
  # pass below can't re-match the URL sitting inside href="...".
  (def s
    (peg/replace-all
      ~(* "[" (capture (some (if-not "]" 1))) "]" "("
          (capture (some (if-not ")" 1))) ")")
      (fn [_ text url]
        (array/push stash (string "<a href=\"" url "\">" text "</a>"))
        (string "\0LINK" (- (length stash) 1) "\0"))
      s))
  # Bare URLs — http(s)://... up to whitespace or terminator. Trailing
  # sentence punctuation (.,;:!?) is stripped off and emitted after the
  # </a> so prose like "see https://x.com." doesn't capture the period.
  (def s
    (peg/replace-all
      ~(capture (* "http" (? "s") "://"
                   (some (if-not (set " \t\n\r<>\"()") 1))))
      (fn [_ url]
        (def trail-len
          (let [n (length url)]
            (var i n)
            (while (and (> i 0)
                        (string/find (string/from-bytes (get url (- i 1)))
                                     ".,;:!?"))
              (-- i))
            (- n i)))
        (def clean (string/slice url 0 (- (length url) trail-len)))
        (def trail (string/slice url (- (length url) trail-len)))
        (string "<a href=\"" clean "\">" clean "</a>" trail))
      s))
  # Bold and italic
  (def s
    (peg/replace-all
      ~(* "**" (capture (some (if-not "**" 1))) "**")
      (fn [_ inner] (string "<strong>" inner "</strong>"))
      s))
  (def s
    (peg/replace-all
      ~(* "*" (capture (some (if-not "*" 1))) "*")
      (fn [_ inner] (string "<em>" inner "</em>"))
      s))
  # Restore code spans
  (def s
    (peg/replace-all
      ~(* "\0CODE" (capture (some :d)) "\0")
      (fn [_ idx-str]
        (string "<code>" (get stash (scan-number idx-str)) "</code>"))
      s))
  # Restore explicit-link <a> tags
  (def s
    (peg/replace-all
      ~(* "\0LINK" (capture (some :d)) "\0")
      (fn [_ idx-str] (get stash (scan-number idx-str)))
      s))
  s)

(defn- md->html [text]
  (def lines (string/split "\n" text))
  (def out @"")
  (var para @[])
  (var list-kind nil)        # :ul, :ol, or nil
  (var list-items @[])

  (defn flush-para []
    (when (not (empty? para))
      (buffer/push-string out "<p>" (inline (string/join para " ")) "</p>")
      (array/clear para)))

  (defn flush-list []
    (when (and list-kind (not (empty? list-items)))
      (def tag (if (= list-kind :ul) "ul" "ol"))
      (buffer/push-string out "<" tag ">")
      (each it list-items
        (buffer/push-string out "<li>" (inline it) "</li>"))
      (buffer/push-string out "</" tag ">"))
    (set list-kind nil)
    (array/clear list-items))

  (defn flush []
    (flush-para)
    (flush-list))

  (each line lines
    (cond
      (peg/match blank-peg line) (flush)

      (let [m (peg/match header3-peg line)]
        (when m (flush) (buffer/push-string out "<h3>" (inline (m 0)) "</h3>")))
      :ok

      (let [m (peg/match header2-peg line)]
        (when m (flush) (buffer/push-string out "<h2>" (inline (m 0)) "</h2>")))
      :ok

      (let [m (peg/match header1-peg line)]
        (when m (flush) (buffer/push-string out "<h1>" (inline (m 0)) "</h1>")))
      :ok

      (let [m (peg/match ul-item-peg line)]
        (when m
          (flush-para)
          (when (not= list-kind :ul) (flush-list) (set list-kind :ul))
          (array/push list-items (m 0))))
      :ok

      (let [m (peg/match ol-item-peg line)]
        (when m
          (flush-para)
          (when (not= list-kind :ol) (flush-list) (set list-kind :ol))
          (array/push list-items (m 0))))
      :ok

      # Plain text — flush any open list, accumulate as a paragraph.
      (do (flush-list) (array/push para line))))
  (flush)
  (string out))

# --- Value rendering -------------------------------------------------

(defn- render-value [v &opt viewer-name]
  (viewer/render-value v viewer-name))

(defn- render-source [c]
  (if (cell/cell-hidden-code? c)
    ""
    (string "<pre class=\"clerk-source\">"
            (highlight/highlight-janet
              (or (c :source-str) (pp (c :source))))
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
  (def viewer-name
    (when-let [n (cell/cell-viewer-name c)]
      (keyword n)))
  (cond
    (r :error)
    (string "<pre class=\"clerk-error\">" (html-escape (r :error)) "</pre>")
    (cell/cell-hidden-result? c) ""
    (render-value (r :value) viewer-name)))

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
