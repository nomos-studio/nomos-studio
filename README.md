# nomos-studio

Orchestration repo for the nomos-studio platform — a live-coding compositional
environment built on Clojure, C++20, and Ableton Link.

## Components

| Component | Role |
|-----------|------|
| [nous](https://github.com/nomos-studio/nous) | Compositional surface — Clojure nREPL, theory engine, live loops |
| [nomos-rt](https://github.com/nomos-studio/nomos-rt) | C++ substrate — Link peer, MIDI/OSC I/O |
| [alembic](https://github.com/nomos-studio/alembic) | DSP authoring DSL — defpatch! → CLAP/WASM via Faust |
| [kairos](https://github.com/nomos-studio/kairos) | CLAP host + nomos-rt integration |
| [aion](https://github.com/nomos-studio/aion) | Lightweight standalone peer (nomos-rt, no CLAP) |
| [txlog](https://github.com/nomos-studio/txlog) | Session transaction log (SQLite + EDN) |
| [edn-cpp](https://github.com/nomos-studio/edn-cpp) | Standalone C++20 EDN parser/emitter |

## Quick start

```sh
git clone https://github.com/nomos-studio/nomos-studio
cd nomos-studio
./install.sh          # builds everything → ~/.local/nomos-studio
export PATH="$HOME/.local/nomos-studio/bin:$PATH"
nomos-studio          # starts nous nREPL
```

From the nous REPL:

```clojure
(start-sidecar! :midi-port "IAC")   ; connect MIDI via nous-sidecar
(session! :bpm 120)                 ; set Link tempo
```

## Requirements

- Leiningen (`lein`)
- Java 11+ (`JAVA_HOME` set, or `/opt/homebrew/opt/openjdk` auto-detected on macOS)
- CMake ≥ 3.20
- C++20 compiler (Clang 15+ / GCC 12+)

## Component versions

See [`components.lock`](components.lock) for the pinned SHA of each component
at the last stable release. Update with:

```sh
bin/nomos-studio lock --update
git add components.lock && git commit -m "chore: update component lock"
```

## Development setup

Each component repo ships a `scripts/pre-commit` hook that blocks secrets,
hardcoded personal paths, and C++ formatting violations. After cloning a
component repo, install it:

```sh
cp scripts/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

Run this once per repo. The hook is a no-op on repos with no C++ files.

## Layout

```
install.sh          — build + install everything to PREFIX
bin/nomos-studio    — start script (installed to PREFIX/bin/)
components.lock     — pinned component SHAs for this release
```
