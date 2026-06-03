# File-watcher.
#
# Polls the path's mtime+size every ~250ms and fires `on-change` on
# any difference. Janet doesn't ship with inotify bindings out of the
# box and the file-watching surface across OSes is enough of a mess
# that polling is the pragmatic v1 choice.

(defn- stamp [path]
  (try
    (let [s (os/stat path)]
      (when s
        [(s :modified) (s :size)]))
    ([_] nil)))

(defn watch-file [path on-change &named poll-ms]
  (default poll-ms 250)
  (def stop? @{:done false})
  (ev/spawn
    (var last (stamp path))
    (while (not (stop? :done))
      (ev/sleep (/ poll-ms 1000))
      (def now (stamp path))
      (when (and now (not= now last))
        (set last now)
        (try (on-change path)
             ([err] (eprintf "clerk-janet watch: on-change failed: %s" err))))))
  (fn [] (put stop? :done true)))
