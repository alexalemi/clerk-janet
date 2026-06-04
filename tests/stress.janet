# Server stress / brittleness tests.
#
# The smoke test only verifies the server boots and stops cleanly. These
# tests beat on the live server with the patterns a real browser produces —
# rapid sequential GETs, concurrent connections, half-finished requests,
# SSE clients that abruptly disconnect, and broadcasts that go out to a
# mix of live and dead clients.
#
# Each block asserts the *server is still alive* afterwards by hitting `/`
# one more time. A failure that crashes the server fiber surfaces as the
# probe hanging or the TCP connect getting refused.

(import ../server)

(def port 7793)

(defn- fail [msg]
  (eprintf "FAIL: %s" msg)
  (os/exit 1))

(defn- ok [msg]
  # eprint goes to stderr (line-buffered), so progress is visible even
  # when the test wedges and the process gets killed.
  (eprintf "OK: %s" msg))

# --- TCP helpers ---------------------------------------------------

(defn- get-status [route]
  "GET <route> on the test server, return the parsed status code or
  nil on connect/read failure. Closes the connection."
  (def conn (try (net/connect "127.0.0.1" (string port))
                 ([_] nil)))
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
      ([err]
        (try (:close conn) ([_] nil))
        nil))))

(defn- assert-alive [tag]
  (def s (get-status "/"))
  (unless (= s 200)
    (fail (string tag ": server is dead, got status=" (string/format "%p" s))))
  (ok (string tag ": server still serves / with 200")))

(defn- open-sse []
  "Open an /events connection; send the request line; return the conn.
  The server sends an SSE header + init bytes and parks."
  (def conn (net/connect "127.0.0.1" (string port)))
  (:write conn "GET /events HTTP/1.1\r\nHost: x\r\nAccept: text/event-stream\r\n\r\n")
  conn)

# --- Boot ----------------------------------------------------------

(def srv (server/make-server :port port :title "stress"))

# Set a non-empty init payload so SSE clients get bytes immediately —
# matches how clerk-serve uses set-init.
((srv :set-init) "{\"type\":\"init\",\"cells\":[]}")

(ev/sleep 0.1)
(assert-alive "boot")

# --- Test 1: many sequential GET / ---------------------------------

(loop [i :range [0 50]]
  (def s (get-status "/"))
  (unless (= s 200)
    (fail (string "sequential GET #" i " got " (string/format "%p" s)))))
(ok "50 sequential GETs all returned 200")
(assert-alive "after sequential GETs")

# --- Test 2: concurrent GET / via spawned fibers --------------------

(def results @[])
(def done-ch (ev/chan 64))
(loop [i :range [0 32]]
  (ev/spawn
    (def s (get-status "/"))
    (array/push results s)
    (ev/give done-ch :done)))
(loop [_ :range [0 32]] (ev/take done-ch))
(def ok-count (count |(= $ 200) results))
(unless (= ok-count 32)
  (fail (string "concurrent: only " ok-count "/32 returned 200")))
(ok "32 concurrent GETs all returned 200")
(assert-alive "after concurrent GETs")

# --- Test 3: half-formed requests (RST mid-headers) -----------------
#
# Open conn, send a partial request line, abrupt close. The server's
# http/read-request sits in a read loop waiting for \r\n\r\n; we cut
# the rope on it. handle-conn must not panic.

(loop [i :range [0 16]]
  (def c (net/connect "127.0.0.1" (string port)))
  (:write c "GET / HTTP/1.1\r\nHost:")  # no terminating \r\n\r\n
  (:close c))
(ev/sleep 0.2)
(ok "16 abrupt half-formed requests sent")
(assert-alive "after half-formed requests")

# --- Test 4: SSE connect + abrupt close -----------------------------
#
# Open /events; read the SSE header + init bytes; close abruptly. The
# server-side fiber is parked in (forever (ev/sleep 30) ...) at this
# point. The conn registered in state-conns is now dead. Until a write
# is attempted, the server doesn't know — that's fine for survival,
# but the next broadcast (Test 6) will trip it.

(def dead-conns @[])
(loop [i :range [0 8]]
  (def c (open-sse))
  (def buf @"")
  # Read the SSE header response — should arrive promptly.
  (def chunk (try (:read c 512 buf) ([_] nil)))
  (unless chunk
    (fail (string "SSE #" i ": no bytes from server")))
  (:close c)
  (array/push dead-conns c))
(ev/sleep 0.2)
(ok "8 SSE clients connected, received headers, force-closed")
(assert-alive "after SSE force-close")

# --- Test 5: SSE that sticks around and gets a broadcast ------------

(def live-c (open-sse))
(def init-buf @"")
(def _ (:read live-c 4096 init-buf))
(ok (string "live SSE client received " (length init-buf) " init bytes"))

# --- Test 6: broadcast while live + dead clients coexist ------------
#
# The dead conns from Test 4 are still registered in srv's state-conns
# (the SSE handler only unregisters them when *it* tries to write and
# fails — and that write is the 30s heartbeat). So broadcast will hit
# them and discover they're dead. The unregister path must not crash.

((srv :broadcast) "{\"type\":\"update\",\"cells\":[]}")
(ev/sleep 0.3)

# Live client should have received the update event.
(def update-buf @"")
(def n (try (:read live-c 4096 update-buf) ([_] nil)))
(if (and n (string/find "update" update-buf))
  (ok "broadcast reached live SSE client")
  (fail (string "live client missed broadcast; n=" (string/format "%p" n)
                " buf=" (string/format "%p" (string update-buf)))))

(:close live-c)
(assert-alive "after broadcast through mixed live/dead clients")

# --- Test 7: rapid SSE churn ----------------------------------------
#
# Open + close lots of SSE connections quickly. Catches fiber leaks
# that would only show up under sustained browser-retry behavior.

(loop [i :range [0 50]]
  (def c (open-sse))
  (def buf @"")
  (try (:read c 256 buf) ([_] nil))
  (:close c))
(ev/sleep 0.3)
(ok "50 SSE open+close cycles completed")
(assert-alive "after SSE churn")

# --- Test 8: broadcast after churn ----------------------------------

((srv :broadcast) "{\"type\":\"update2\",\"cells\":[]}")
(ev/sleep 0.2)
(ok "broadcast after churn did not crash")
(assert-alive "final")

# --- Done -----------------------------------------------------------

((srv :stop))
(eprint "Stress test passed.")
