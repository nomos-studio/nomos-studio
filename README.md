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

Run this once per repo. The clang-format check is skipped on repos with no C++ files; secret and personal-path checks apply everywhere.

## Documentation

System-level design documents live in `doc/` — concerns that cross component
boundaries and don't belong in any single component repo.

| Document | Contents |
|----------|----------|
| [`doc/design-architecture.md`](doc/design-architecture.md) | Component roles, peer protocol, three-host studio topology, kairos as declared CLAP host, surface model |
| [`doc/design-decisions-open.md`](doc/design-decisions-open.md) | Cross-component open questions (kairos CLAP GUI, Surge XT preset bridge, OSC peer subscription, surface adapters) |

Component-internal design documents live in each component's own `doc/` directory.

## Layout

```
doc/                — system-level design documents
install.sh          — build + install everything to PREFIX
bin/nomos-studio    — start script (installed to PREFIX/bin/)
components.lock     — pinned component SHAs for this release
```
