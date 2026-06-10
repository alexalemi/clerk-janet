# Server-side syntax highlighting for Janet source.
#
# Tokenizes via a PEG and emits class-tagged spans matching the
# Google-Code-Prettify class palette that Sarabander's SICP edition
# uses (`.kwd`, `.lit`, `.pun`, `.opn`/`.clo`, `.str`, `.com`, `.pln`).
# CSS for these classes lives in `shell.janet`.

(def- keyword-set
  # Forms that get the "keyword" color.
  (let [t @{}]
    (each s ["def" "defn" "var" "set" "fn"
             "if" "cond" "case" "when" "unless"
             "let" "loop" "for" "each" "while"
             "do" "break" "return"
             "defmacro" "quote" "quasiquote" "unquote"
             "import" "use" "require" "module"
             "defn-" "defmacro-" "def-"
             "true" "false" "nil"]
      (put t s true))
    t))

(def- operator-set
  (let [t @{}]
    (each s ["+" "-" "*" "/" "<" ">" "=" "<=" ">=" "not="
            "%" "and" "or" "not"]
      (put t s true))
    t))

(defn- html-escape [s]
  (->> s
       (string/replace-all "&" "&amp;")
       (string/replace-all "<" "&lt;")
       (string/replace-all ">" "&gt;")))

# PEG that returns a stream of [type, text] pairs covering the entire
# input. Whitespace is :ws, comments are :com, etc.
(def- token-peg
  (peg/compile
    ~{:main (any (+ :comment :long-string :string :paren :keyword :number :symbol :ws :other))

      # Line comment from `#` to end of line (or eof)
      :comment (* (constant :com) '(* "#" (any (if-not "\n" 1))))

      # Long string: N backticks ... N backticks (backmatch pairs the
      # delimiters, so ` inside `` ... `` is fine). The `%` accumulator
      # folds the three captures back into one text span.
      :long-string (* (constant :str)
                      (% (* (capture (some "`") :delim)
                            (capture (any (if-not (backmatch :delim) 1)))
                            (capture (backmatch :delim)))))

      # Double-quoted string with simple escape handling
      :string (* (constant :str)
                 '(* "\""
                     (any (+ (* "\\" 1) (if-not "\"" 1)))
                     "\""))

      # Open / close parens
      :paren (+ (* (constant :opn) '(set "([{"))
                (* (constant :clo) '(set ")]}")))

      # Janet keyword: starts with `:`
      :keyword (* (constant :kw)
                  '(* ":" (any (if-not (set " \t\n()[]{}\"`',;|") 1))))

      # Number: integer, float, hex etc. — leading sign optional, then
      # a digit, then any of [.eE+-0-9a-fA-F]
      :number (* (constant :lit)
                 '(* (? (set "+-"))
                     :d
                     (any (+ :d (set ".eEpPxXabcdefABCDEFhH+-")))))

      # Symbol: any identifier-ish run of bytes
      :symbol (* (constant :sym)
                 '(some (if-not (set " \t\n()[]{}\"`',;|#") 1)))

      :ws (* (constant :ws) '(some (set " \t\n\r")))
      :other (* (constant :other) '1)}))

(defn- classify-symbol [text]
  (cond
    (get keyword-set text) "kwd"
    (get operator-set text) "pun"
    "pln"))

(defn- token-class [type text]
  (case type
    :com "com"
    :str "str"
    :opn "opn"
    :clo "clo"
    :kw  "atn"   # `:foo` keywords map to the attribute-name color
    :lit "lit"
    :sym (classify-symbol text)
    :ws  nil      # whitespace passes through plain
    :other "pln"))

(defn highlight-janet [source]
  (def tokens (peg/match token-peg source))
  (def out @"")
  (when tokens
    # tokens is a flat list alternating type and text — pair them up.
    (var i 0)
    (while (< i (length tokens))
      (def type (get tokens i))
      (def text (get tokens (+ i 1)))
      (def cls (token-class type text))
      (if cls
        (buffer/push-string out "<span class=\"" cls "\">"
                            (html-escape text) "</span>")
        (buffer/push-string out (html-escape text)))
      (+= i 2)))
  (string out))
