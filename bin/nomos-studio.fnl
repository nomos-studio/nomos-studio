;; nomos-studio.fnl — main launcher
;;
;; Called by bin/nomos-studio after Fennel has been located.
;;
;; Usage:
;;   nomos-studio               start BEAM + Tauri (normal use)
;;   nomos-studio --headless    start BEAM only, no Tauri window
;;   nomos-studio --help        show usage
;;
;; Layout assumed (dev / source build):
;;   $AREA/src/nomos-studio/bin/nomos-studio.fnl   ← this file
;;   $AREA/src/nomos_beam/                          ← mix project
;;   $AREA/src/nomos-tauri/src-tauri/target/debug/  ← cargo build output

(local os os)
(local io io)
(local math math)

;;; ── utilities ────────────────────────────────────────────────────────────

(fn log [msg]
  (io.stderr:write (.. "[nomos-studio] " msg "\n"))
  (io.stderr:flush))

(fn die [msg]
  (log (.. "ERROR: " msg))
  (os.exit 1))

;; Return a path to a unique temporary file (not yet created).
(fn tmpfile []
  (.. "/tmp/nomos-" (tostring (math.floor (os.difftime (os.time) 0)))))

;; Spawn cmd in background; return its PID as a number or nil.
;; Writes a small wrapper script to avoid shell quoting issues.
(fn spawn [cmd]
  (let [sh-file  (.. (tmpfile) ".sh")
        pid-file (.. (tmpfile) ".pid")
        f        (io.open sh-file :w)]
    (when (not f) (die (.. "cannot write temp script: " sh-file)))
    (f:write (.. "#!/bin/sh\n" cmd " &\necho $! > " pid-file "\n"))
    (f:close)
    (os.execute (.. "chmod +x " sh-file " && " sh-file))
    (os.remove sh-file)
    (let [pf (io.open pid-file :r)]
      (if pf
          (let [pid-str (pf:read :*l)]
            (pf:close)
            (os.remove pid-file)
            (tonumber pid-str))
          nil))))

;; Kill a PID with SIGTERM.
(fn kill-pid [pid]
  (when (and pid (> pid 0))
    (os.execute (.. "kill " (tostring pid) " 2>/dev/null"))))

;; Return true if the process is still alive (uses kill -0, flag-file pattern
;; to avoid relying on LuaJIT os.execute return-value semantics).
(fn running? [pid]
  (let [flag (.. (tmpfile) ".alive")]
    (os.execute (.. "kill -0 " (tostring pid) " 2>/dev/null && touch " flag))
    (let [f (io.open flag)]
      (if f (do (f:close) (os.remove flag) true) false))))

;; Poll localhost:port until HTTP 200 or max-seconds elapsed.
(fn wait-for-phoenix [port max-seconds]
  (log (.. "waiting for Phoenix on :" (tostring port) " ..."))
  (var elapsed 0)
  (var ready false)
  (while (and (not ready) (< elapsed max-seconds))
    (let [flag (.. (tmpfile) ".ready")]
      (os.execute
        (.. "curl -sf http://localhost:" (tostring port)
            "/ >/dev/null 2>&1 && touch " flag))
      (let [f (io.open flag)]
        (if f
            (do (f:close) (os.remove flag) (set ready true))
            (do (os.execute "sleep 0.5")
                (set elapsed (+ elapsed 0.5)))))))
  ready)

;;; ── path resolution ──────────────────────────────────────────────────────

;; Resolve src/ from arg[0] (this script's absolute path).
;; Script lives at $AREA/src/nomos-studio/bin/nomos-studio.fnl
;;   bin/ → nomos-studio/ → src/
(fn resolve-src-dir []
  (let [script (. arg 0)
        f      (io.popen
                 (.. "cd \"$(dirname '" script "')/../..\" && pwd") :r)
        dir    (f:read :*l)]
    (f:close)
    (or dir (die "cannot resolve src/ directory from script path"))))

;;; ── component launchers ──────────────────────────────────────────────────

(fn start-beam [src-dir]
  ;; Dev mode: mix phx.server in nomos_beam source tree.
  ;; Installed mode (future): $PREFIX/bin/nomos_beam start.
  (let [beam-dir (.. src-dir "/nomos_beam")]
    (let [f (io.open (.. beam-dir "/mix.exs"))]
      (when (not f)
        (die (.. "nomos_beam not found at " beam-dir
                 "\nRun: mr checkout  (from src/)")))
      (f:close))
    (log "starting nomos_beam ...")
    (spawn (.. "cd " beam-dir " && mix phx.server"))))

(fn start-tauri [src-dir]
  ;; Dev mode: debug binary from cargo build.
  ;; Installed mode (future): .app bundle.
  (let [bin (.. src-dir "/nomos-tauri/src-tauri/target/debug/nomos-tauri")]
    (let [f (io.open bin)]
      (when (not f)
        (die (.. "nomos-tauri binary not found at " bin
                 "\nRun: cargo build  (in src/nomos-tauri/src-tauri/)")))
      (f:close))
    (log "starting nomos-tauri ...")
    (spawn bin)))

;;; ── argument parsing ─────────────────────────────────────────────────────

(fn parse-args [args]
  (var headless false)
  (each [_ v (ipairs (or args []))]
    (match v
      :--headless (set headless true)
      :--help     (do
                    (print "Usage: nomos-studio [--headless] [--help]")
                    (print "  --headless   start BEAM only; no Tauri window")
                    (os.exit 0))
      other       (die (.. "unknown argument: " other))))
  {: headless})

;;; ── main ─────────────────────────────────────────────────────────────────

(let [opts     (parse-args arg)
      src-dir  (resolve-src-dir)
      beam-pid (start-beam src-dir)]

  (when (not beam-pid)
    (die "failed to spawn nomos_beam"))
  (log (.. "nomos_beam PID " (tostring beam-pid)))

  (if opts.headless
      (do
        (log "headless mode — BEAM running, Tauri suppressed")
        (while (running? beam-pid)
          (os.execute "sleep 1"))
        (log "nomos_beam exited"))
      (do
        (when (not (wait-for-phoenix 4000 30))
          (kill-pid beam-pid)
          (die "Phoenix did not start within 30 s"))
        (let [tauri-pid (start-tauri src-dir)]
          (when (not tauri-pid)
            (kill-pid beam-pid)
            (die "failed to spawn nomos-tauri"))
          (log (.. "nomos-tauri PID " (tostring tauri-pid)))
          (while (running? tauri-pid)
            (os.execute "sleep 1"))
          (log "Tauri window closed — stopping BEAM ...")
          (kill-pid beam-pid)
          (log "done")))))
