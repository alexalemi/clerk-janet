# Binary-level integration test.
#
# The in-process server stress test (tests/stress.janet) passes cleanly —
# 50 GETs, 32 concurrent connections, half-formed requests, SSE
# force-close, broadcast-through-dead-clients all survive. That means
# the brittleness the user sees isn't in server.janet itself; it must
# be in how main.janet wires the pieces together, or specific to the
# self-contained ELF.
#
# This test spawns the installed `clerk-janet` binary as a subprocess
# and beats on it. After each phase we check the process is still
# alive AND still responding. The point isn't to prove "the binary
# works" — it's to find out what kills it.

(def port 7798)
# CLERK_BIN env var overrides the binary location, so we can test
# changes to main.janet without rebuilding the system install.
# When set to "source", we run `janet main.janet ...` directly.
(def bin-mode (or (os/getenv "CLERK_BIN") "/usr/local/bin/clerk-janet"))
(def cmd
  (if (= bin-mode "source")
    ["janet" "main.janet"]
    [bin-mode]))

(defn- ok [msg] (eprintf "OK: %s" msg))
(defn- fail [msg] (eprintf "FAIL: %s" msg) (os/exit 1))

# --- Build a tiny notebook in a tmpdir -----------------------------

(def tmpdir (string (os/getenv "TMPDIR" "/tmp") "/clerk-janet-bin-test"))
(os/mkdir tmpdir)
(def nb (string tmpdir "/notebook.janet"))
(spit nb ``
# # Binary smoke
#
# A trivial notebook.

(def x 7)
(* x x)
``)

# --- Spawn the binary ----------------------------------------------

(def stderr-path (string tmpdir "/clerk-stderr.log"))
(def stderr-file (file/open stderr-path :w))

(def proc
  (os/spawn [;cmd nb "--port" (string port)]
            :p
            {:err stderr-file :out :pipe :in :pipe}))

(defn- proc-alive? []
  # /proc/<pid> exists iff the process is still around (Linux-only,
  # which matches where clerk-janet runs). proc :return-code is also
  # set when Janet has reaped the child, but on Linux the /proc check
  # is the most direct.
  (and (nil? (get proc :return-code))
       (truthy? (os/stat (string "/proc/" (get proc :pid))))))

(defn- assert-alive [tag]
  (unless (proc-alive?)
    (file/close stderr-file)
    (def stderr (slurp stderr-path))
    (fail (string tag ": binary died (return-code=" (string/format "%p" (get proc :return-code))
                  ")\n--- clerk-janet stderr ---\n" stderr))))

# Wait for it to bind. Probe / until we get a response.
(var bound? false)
(loop [_ :range [0 30] :until bound?]
  (ev/sleep 0.1)
  (try
    (do
      (def c (net/connect "127.0.0.1" (string port)))
      (:close c)
      (set bound? true))
    ([_] nil)))
(unless bound?
  (file/close stderr-file)
  (def stderr (slurp stderr-path))
  (fail (string "binary never bound to port " port "\n--- stderr ---\n" stderr)))

(assert-alive "boot")
(ok "binary booted and is listening")

# --- HTTP probe helper ---------------------------------------------

(defn- get-status [route]
  (def conn (try (net/connect "127.0.0.1" (string port)) ([_] nil)))
  (when conn
    (try
      (do
        (:write conn (string "GET " route " HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"))
        (def buf @"")
        (def chunk (:read conn 1024 buf))
        (try (:close conn) ([_] nil))
        (when chunk
          (when-let [m (peg/match ~(* "HTTP/1.1 " (number (some :d))) buf)]
            (first m))))
      ([_] (try (:close conn) ([_] nil)) nil))))

(unless (= 200 (get-status "/"))
  (fail "initial GET / did not return 200"))
(ok "initial GET / returned 200")

# --- Test 1: sequential GETs --------------------------------------

(loop [i :range [0 30]]
  (def s (get-status "/"))
  (unless (= s 200)
    (fail (string "sequential GET #" i " got " (string/format "%p" s)))))
(assert-alive "after 30 sequential GETs")
(ok "30 sequential GETs survived")

# --- Test 2: concurrent GETs --------------------------------------

(def results @[])
(def ch (ev/chan 32))
(loop [i :range [0 20]]
  (ev/spawn
    (array/push results (get-status "/"))
    (ev/give ch :done)))
(loop [_ :range [0 20]] (ev/take ch))
(def ok-n (count |(= $ 200) results))
(unless (= ok-n 20)
  (fail (string "concurrent: only " ok-n "/20 returned 200")))
(assert-alive "after 20 concurrent GETs")
(ok "20 concurrent GETs survived")

# --- Test 3: SSE connect + abrupt close (browser navigation away) --

(defn- open-sse []
  (def c (net/connect "127.0.0.1" (string port)))
  (:write c "GET /events HTTP/1.1\r\nHost: x\r\nAccept: text/event-stream\r\n\r\n")
  c)

(loop [i :range [0 5]]
  (def c (open-sse))
  (def buf @"")
  (try (:read c 1024 buf) ([_] nil))
  (:close c))
(ev/sleep 0.2)
(assert-alive "after 5 SSE force-closes")
(ok "5 SSE force-closes survived")

# --- Test 4: touch the notebook to trigger watcher + broadcast ----

(def live (open-sse))
(def init-buf @"")
# Drain whatever's there at connect time (HTTP headers + init payload).
# Two reads with a small gap so we get both the headers and the init
# broadcast that clerk-serve fires right after server start.
(try (:read live 8192 init-buf) ([_] nil))
(ev/sleep 0.2)
(try (:read live 8192 init-buf) ([_] nil))
(ok (string "live SSE got " (length init-buf) " bytes on connect"))

# Use a distinctive sentinel value (4242) so the post-edit broadcast
# is unambiguously different from the initial state, even if reads
# from before+after end up in adjacent buffers.
(spit nb ``
# # Binary smoke (edited)
(def x 4242)
(* x x)
``)
(ev/sleep 0.8)  # watcher polls every 250ms; allow 3 ticks of margin

(def update-buf @"")
# ev/with-deadline so a *missing* broadcast (the most likely failure
# mode for this test) returns control quickly instead of blocking on
# :read for the full 30s test timeout.
(try
  (ev/with-deadline 2
    (:read live 8192 update-buf))
  ([_] nil))
(unless (string/find "4242" update-buf)
  (fail (string "broadcast after notebook edit missing — watcher's "
                "on-change probably raised silently. "
                "update-buf (truncated): "
                (string/format "%p" (string/slice update-buf 0 (min 400 (length update-buf)))))))
(ok "broadcast after notebook edit reached SSE client")

(:close live)
(assert-alive "after file edit + broadcast")

# --- Test 5: many file edits in quick succession ------------------

(loop [i :range [0 5]]
  (spit nb (string "(def x " i ")\n(* x x)\n"))
  (ev/sleep 0.3))
(assert-alive "after 5 rapid file edits")
(ok "5 rapid file edits survived")

# --- Test 5b: stdin EOF must not stop the server -------------------
#
# The previous block-forever used (file/read stdin :line), which made
# *anything* that EOF'd stdin (terminal close, shell backgrounding,
# Ctrl-D, accidental enter) silently kill the server. Close the proc's
# stdin pipe and verify the server keeps serving.

(:close (get proc :in))
(ev/sleep 0.4)
(assert-alive "after stdin EOF")
(unless (= 200 (get-status "/"))
  (fail "stdin EOF: server stopped responding"))
(ok "server survived stdin EOF")

# --- Test 6: SSE open + edit + close (what a real browser does) ---

(loop [i :range [0 3]]
  (def c (open-sse))
  (def b @"")
  (try (:read c 1024 b) ([_] nil))
  (spit nb (string "(def x " (+ 100 i) ")\n"))
  (ev/sleep 0.4)
  (try (:read c 4096 b) ([_] nil))
  (:close c))
(assert-alive "after browser-like sessions")
(ok "browser-like open/edit/close cycles survived")

# --- Final probe ---------------------------------------------------

(unless (= 200 (get-status "/"))
  (fail "final GET / did not return 200"))
(ok "final GET / still returns 200")

# --- Shutdown -----------------------------------------------------

(os/proc-kill proc)
(file/close stderr-file)
(eprint "Binary integration test passed.")
