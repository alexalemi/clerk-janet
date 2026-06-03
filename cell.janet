# Cell model.
#
# A notebook is an ordinary Janet file whose `#`-line comments are
# interpreted as Markdown prose. Read source twice:
#   1. Parse top-level forms (Janet's `parser` library) with line ranges.
#   2. Scan source text line-by-line for prose comments and directives
#      that live in the gaps between forms.
# Final cells are the line-sorted interleaving.

(def- prose-peg
  # Line whose first non-whitespace is `#`. Captures the text after
  # the `#`+ optional space.
  (peg/compile
    ~(* (any (set " \t"))
        "#"
        (any "#")
        (? " ")
        (capture (any 1)))))

(def- directive-peg
  # `# @clerk:NAME [ARG]` — captures name then optional arg.
  (peg/compile
    ~(* (any (set " \t"))
        "#"
        (any "#")
        (any (set " \t"))
        "@clerk:"
        (capture (some (+ :w (set "-_"))))
        (? (* (some (set " \t"))
              (capture (some 1)))))))

(def- blank-peg
  (peg/compile ~(* (any (set " \t")) -1)))

(defn- blank? [line] (truthy? (peg/match blank-peg line)))

# --- Read forms with positions ---------------------------------------

(defn- read-forms-with-positions
  "Feed the parser one line at a time. Track when the parser transitions
  *out of* `:root` (between-forms) state — that's the line the form
  *actually* began on, which can be later than 'line after previous
  form' when there are intervening blank/comment lines."
  [src]
  (def lines (string/split "\n" src))
  (def p (parser/new))
  (def forms @[])
  (var form-start nil)
  (var line-num 0)
  (each line lines
    (++ line-num)
    (parser/consume p line)
    (parser/consume p "\n")
    # If the parser left :root during this consume, this is the form's
    # start line. Single-line forms: status returns to :root after
    # consume but has-more is true. Multi-line forms: status becomes
    # :pending.
    (when (and (not form-start)
               (or (= (parser/status p) :pending)
                   (parser/has-more p)))
      (set form-start line-num))
    (while (parser/has-more p)
      (array/push forms
                  {:form (parser/produce p)
                   :start-line form-start
                   :end-line line-num})
      (set form-start nil)))
  (parser/eof p)
  (while (parser/has-more p)
    (array/push forms
                {:form (parser/produce p)
                 :start-line (or form-start line-num)
                 :end-line line-num}))
  forms)

# --- Extract prose + directives --------------------------------------

(defn- covered-lines [forms]
  (def t @{})
  (each f forms
    (loop [l :range-to [(f :start-line) (f :end-line)]]
      (put t l true)))
  t)

(defn- form-start-set [forms]
  (def t @{})
  (each f forms (put t (f :start-line) true))
  t)

(defn- match-prose [line]
  (when-let [m (peg/match prose-peg line)] (m 0)))

(defn- match-directive [line]
  (when-let [m (peg/match directive-peg line)]
    [(keyword (m 0)) (if (> (length m) 1) (m 1) nil)]))

(defn- extract-prose-and-directives [src-lines forms]
  (def covered (covered-lines forms))
  (def form-starts (form-start-set forms))
  (def prose-cells @[])
  (def directives-by-line @{})
  (var prose-start nil)
  (def prose-buf @[])
  (def pending-dirs @[])

  (defn flush-prose! []
    (when prose-start
      (def text (string/join prose-buf "\n"))
      (array/push prose-cells {:start prose-start :text text})
      (set prose-start nil)
      (array/clear prose-buf)))

  (var line-num 0)
  (each line src-lines
    (++ line-num)
    (cond
      # Inside a code form — flush prose if this is the start of a new one.
      (covered line-num)
      (when (form-starts line-num)
        (flush-prose!)
        (when (not (empty? pending-dirs))
          (put directives-by-line line-num (tuple ;pending-dirs))
          (array/clear pending-dirs)))

      # Directive line takes priority over prose match.
      (let [d (match-directive line)]
        (when d
          (flush-prose!)
          (array/push pending-dirs d)))
      (do)

      # Prose comment line.
      (let [t (match-prose line)]
        (when t
          (when (not prose-start) (set prose-start line-num))
          (array/push prose-buf t)))
      (do)

      # Blank line — preserve para break inside prose.
      (blank? line)
      (when prose-start (array/push prose-buf ""))

      # Catch-all: shouldn't happen at top level.
      (do (flush-prose!) (array/clear pending-dirs))))

  (flush-prose!)
  [prose-cells directives-by-line])

# --- Cell construction -----------------------------------------------

(defn- classify [form]
  (cond
    (not (tuple? form)) [:expr nil form]
    (empty? form)       [:expr nil form]
    (let [head (form 0)]
      (cond
        (or (= head 'def) (= head 'defn))
        [:define (when (symbol? (form 1)) (form 1)) form]

        (= head 'var)
        [:define (when (symbol? (form 1)) (form 1)) form]

        (or (= head 'import) (= head 'use) (= head 'require))
        [:meta nil form]

        (= head 'defmacro)
        [:syntax (when (symbol? (form 1)) (form 1)) form]

        # default: expression
        [:expr nil form]))))

(defn- substring-of [start-line end-line src-lines]
  (string/join (array/slice src-lines (- start-line 1) end-line) "\n"))

(defn- positional-id [i] (string "c" i))

(defn- build-md-cell [entry i]
  @{:id (positional-id i) :index i :kind :md
    :name nil :source nil :rewrite nil
    :source-hash (hash (entry :text))
    :directives []
    :prose (entry :text)
    :source-str nil})

(defn- build-code-cell [entry i src-lines]
  (def form (entry :form))
  (def [k name rewrite] (classify form))
  (def src-str (substring-of (entry :start-line) (entry :end-line) src-lines))
  (def auto-name (when (= k :expr) (symbol "_clerk-cell-" i)))
  (def final-name (or name auto-name))
  (def final-rewrite
    (if (= k :expr)
      (tuple 'def auto-name form)
      rewrite))
  @{:id (positional-id i) :index i :kind k
    :name final-name
    :source form
    :rewrite final-rewrite
    :source-hash (hash form)
    :directives (or (entry :dirs) [])
    :prose nil
    :source-str src-str})

# --- Public ----------------------------------------------------------

(defn read-notebook [path]
  (def src (slurp path))
  (def src-lines (string/split "\n" src))
  (def forms (read-forms-with-positions src))
  (def [prose-cells directives-by-line]
    (extract-prose-and-directives src-lines forms))
  (def entries @[])
  (each p prose-cells
    (array/push entries {:kind :md :start-line (p :start) :text (p :text)}))
  (each f forms
    (array/push entries
                {:kind :code
                 :start-line (f :start-line)
                 :end-line (f :end-line)
                 :form (f :form)
                 :dirs (or (directives-by-line (f :start-line)) [])}))
  (def sorted (sort-by |($ :start-line) entries))
  (def cells @[])
  (var i 0)
  (each entry sorted
    (def c (case (entry :kind)
             :md   (build-md-cell entry i)
             :code (build-code-cell entry i src-lines)))
    (array/push cells c)
    (++ i))
  cells)

(defn cell-md-text [c]
  (when (= (c :kind) :md) (c :prose)))

(defn cell-directive [c name]
  (let [d (find |(= ($ 0) name) (c :directives))]
    (when d (d 1))))

(defn cell-hidden-code? [c]
  (truthy? (find |(= ($ 0) :hide-code) (c :directives))))

(defn cell-hidden-result? [c]
  (truthy? (find |(= ($ 0) :hide-result) (c :directives))))

(defn cell-viewer-name [c]
  (cell-directive c :viewer))
