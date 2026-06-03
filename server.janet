# HTTP + Server-Sent-Events server.
#
# Endpoints:
#   GET /          → shell HTML
#   GET /client.js → client script
#   GET /events    → SSE stream; one `data: <json>\n\n` per save
#
# Shared state is held in `clerk-server` records:
#   - connections : table of channel → conn-stream
#   - init-bytes  : the latest payload, sent to newly-connecting clients
#   - sema        : protects the above

(import spork/http)
(import ./shell)

(defn- write-bytes [conn bytes]
  (try (do (:write conn bytes) true)
       ([err] false)))

(defn- write-http [conn status content-type body]
  (def body (if (buffer? body) body (string body)))
  (def head (string/format "HTTP/1.1 %d OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
                           status content-type (length body)))
  (write-bytes conn head)
  (write-bytes conn body))

(defn- write-sse-headers [conn]
  (def head "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n")
  (write-bytes conn head))

(defn- write-sse-event [conn data-str]
  # SSE protocol: `data: <line>\n` per line, blank line terminates event.
  # JSON has no newlines (when produced compactly), so one `data:` line suffices.
  (write-bytes conn (string "data: " data-str "\n\n")))

# clerk-server is a struct of fns + a state table held in a closure-ish way.
(defn make-server [&named port title]
  (default port 7777)
  (default title "clerk-janet")
  (def state @{:conns @{}
               :init-bytes ""
               :next-id 0})

  (defn register [conn]
    (def id (state :next-id))
    (put state :next-id (+ id 1))
    (put (state :conns) id conn)
    id)

  (defn unregister [id]
    (put (state :conns) id nil))

  (defn broadcast [bytes]
    (each id (keys (state :conns))
      (def conn ((state :conns) id))
      (when conn
        (unless (write-sse-event conn bytes)
          (unregister id)))))

  (defn set-init [bytes]
    (put state :init-bytes bytes))

  (defn handle-conn [conn]
    (def buf @"")
    (def req (try (http/read-request conn buf)
                  ([err] nil)))
    (cond
      (or (nil? req) (= req :error)) (try (:close conn) ([_] nil))

      (or (= (req :route) "/") (= (req :route) ""))
      (do (write-http conn 200 "text/html; charset=utf-8" (shell/live-shell-html title))
          (try (:close conn) ([_] nil)))

      (= (req :route) "/client.js")
      (do (write-http conn 200 "application/javascript; charset=utf-8" shell/client-js)
          (try (:close conn) ([_] nil)))

      (= (req :route) "/events")
      (do
        (write-sse-headers conn)
        # Send current init payload (if any) right away.
        (def init (state :init-bytes))
        (when (and init (not (empty? init)))
          (write-sse-event conn init))
        (def id (register conn))
        # Park this fiber waiting on the connection. When the connection
        # dies (writes fail), the broadcast loop will unregister us.
        # Keep-alive: send a comment every 30s so proxies don't time out.
        (forever
          (ev/sleep 30)
          (unless (write-bytes conn ":\n\n")
            (unregister id)
            (break))))

      # Not found
      (do (write-http conn 404 "text/plain" "not found")
          (try (:close conn) ([_] nil)))))

  (defn start []
    (net/server "127.0.0.1" (string port)
                (fn [conn]
                  (ev/spawn
                    (try (handle-conn conn)
                         ([err]
                          (eprintf "clerk-janet: connection error: %s" err)
                          (try (:close conn) ([_] nil))))))))

  (def server (start))

  @{:broadcast broadcast
    :set-init set-init
    :stop (fn [] (when server (:close server)))})
