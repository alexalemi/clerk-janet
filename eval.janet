# Evaluate a notebook cell-by-cell.
#
# Each cell is compiled and run in a shared environment, with output
# captured to a buffer and errors caught via `protect`. A failure in
# one cell doesn't kill the others — closely matches clerk-racket's
# per-cell-error model.

(import ./cell)

# A cell-result is {:cell c :value v :error msg|nil :stdout str :stderr str}
# error=nil means the cell ran cleanly; otherwise it's the error message.

(defn- new-env []
  # Fresh root-env-like environment that inherits from the current one
  # so `defn`, `import`, math, etc. are visible.
  (def env (make-env))
  env)

(defn- run-form-in-env [form env]
  "Evaluate a single form via `run-context` so that `import`/`use`/`require`
  install bindings into `env`. Returns the form's value, or throws a
  human-readable error string."
  (def src (string/format "%n" form))
  (var emitted false)
  (def errors @[])
  (var last-value nil)
  (run-context
    {:env env
     :source "notebook-cell"
     :chunks (fn [buf _parser]
               (when (not emitted)
                 (buffer/push-string buf src)
                 (set emitted true)))
     :on-compile-error (fn [msg & _]
                         (array/push errors (string "compile error: " msg)))
     :on-parse-error (fn [p & _]
                       (array/push errors (string "parse error: " (parser/error p))))
     :on-status (fn [fiber value]
                  (if (= (fiber/status fiber) :error)
                    (array/push errors (string value))
                    (set last-value value)))})
  (unless (empty? errors)
    (error (string/join errors "; ")))
  last-value)

(defn- eval-one-cell [c env]
  (case (c :kind)
    :md
    {:cell c :value nil :error nil :stdout "" :stderr ""}

    # All other kinds: try to run the rewrite, then fetch the binding
    # if we synthesized one. Capture stdout/stderr by installing the
    # buffers as dynamic bindings *in the cell env itself* — the cell
    # runs in a fresh fiber (via `run-context`) whose dyn lookups go
    # through `env`, so `with-dyns` on *this* fiber would never be seen.
    (let [out-buf @""
          err-buf @""]
      (put env :out out-buf)
      (put env :err err-buf)
      (def res (protect (run-form-in-env (c :rewrite) env)))
      (put env :out nil)
      (put env :err nil)
      (def [ok? val] res)
      (if ok?
        # Success — fetch the named binding for its value.
        # `def` bindings store the value under :value; `var` bindings
        # store a one-element boxed array under :ref.
        (let [v (cond
                  (nil? (c :name)) nil
                  (let [b (get env (c :name))]
                    (when b
                      (if-let [ref (b :ref)] (ref 0) (b :value)))))]
          {:cell c :value v :error nil
           :stdout (string out-buf)
           :stderr (string err-buf)})
        # Error path — val is the error message
        {:cell c :value nil :error (string val)
         :stdout (string out-buf)
         :stderr (string err-buf)}))))

(defn eval-notebook [path]
  "Read the notebook at `path` and evaluate each cell. Returns an array
  of cell-results."
  (def cells (cell/read-notebook path))
  (def env (new-env))
  (def results @[])
  (each c cells
    (array/push results (eval-one-cell c env)))
  results)
