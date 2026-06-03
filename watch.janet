# File-watcher. mtime+size polling works regardless of filesystem.
# Janet doesn't ship inotify bindings; polling is the pragmatic choice.

(defn- stamp [path]
  (try
    (let [s (os/stat path)]
      (when s [(s :modified) (s :size)]))
    ([_] nil)))

(defn- janet-file? [path]
  (and (string/has-suffix? ".janet" path)
       (= ((or (os/stat path) {}) :mode) :file)))

(defn- walk-janet-files [root]
  "Recursively collect .janet file paths under root."
  (def out @[])
  (defn go [p]
    (try
      (let [st (os/stat p)]
        (cond
          (= (st :mode) :file)
          (when (string/has-suffix? ".janet" p) (array/push out p))

          (= (st :mode) :directory)
          (each name (os/dir p)
            (when (not (or (string/has-prefix? "." name)
                            (= name "jpm_tree")
                            (= name "build")))
              (go (string p "/" name))))))
      ([_] nil)))
  (go root)
  out)

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

(defn watch-dir [root on-change &named poll-ms]
  (default poll-ms 250)
  (def stop? @{:done false})
  (defn snapshot []
    (def t @{})
    (each p (walk-janet-files root)
      (put t p (stamp p)))
    t)
  (ev/spawn
    (var last (snapshot))
    (while (not (stop? :done))
      (ev/sleep (/ poll-ms 1000))
      (def now (snapshot))
      (def changed
        (filter (fn [p] (not= (get now p) (get last p)))
                (keys now)))
      (set last now)
      (when (not (empty? changed))
        # Pick most-recently-modified to avoid thrash on simultaneous saves.
        (def chosen
          (reduce
            (fn [acc p]
              (if (> (first (get now p)) (first (get now acc))) p acc))
            (first changed) changed))
        (try (on-change chosen)
             ([err] (eprintf "clerk-janet watch-dir: on-change failed: %s" err))))))
  (fn [] (put stop? :done true)))

(defn find-notebooks [root] (walk-janet-files root))

(defn watch-tree [path on-change &named poll-ms]
  "Dispatches on file vs directory. on-change is called with the path
  that changed — in file mode that's `path`; in dir mode it's whichever
  .janet file under the root got saved."
  (default poll-ms 250)
  (def st (try (os/stat path) ([_] nil)))
  (cond
    (nil? st)
    (error (string "no such file or directory: " path))

    (= (st :mode) :file)
    (watch-file path |(on-change path) :poll-ms poll-ms)

    (= (st :mode) :directory)
    (watch-dir path on-change :poll-ms poll-ms)

    (error (string "not a file or directory: " path))))
