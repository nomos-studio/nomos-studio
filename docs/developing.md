# Developing nomos-studio

This guide covers building from source, the system architecture, component
boundaries, and development workflow. It assumes familiarity with at least one of
the languages in the stack (Elixir, Clojure, C++).

---

## Prerequisites

| Tool | Version | Used by |
|------|---------|---------|
| Elixir | 1.16+ | nomos_beam |
| Erlang/OTP | 26+ | nomos_beam, Jinterface (JVM peers) |
| Java | 17+ | nous, bwosc, Jinterface |
| Leiningen | 2.11+ | nous, alembic, ctrl-tree, nomos-maths |
| CMake | 3.20+ | nomos-rt, kairos, aion, edn-cpp |
| Clang | 15+ | nomos-rt, kairos, aion (C++20) |
| Node.js | 20+ | Shadow-CLJS (browser ClojureScript build) |
| Rust / Cargo | 1.75+ | Tauri desktop wrapper |
| Faust | 2.60+ | Alembic DSP compilation target |

On macOS, Homebrew covers most of these:

```sh
brew install elixir cmake llvm faust node
brew install --cask temurin   # Java 21 LTS
```

On Ubuntu 22.04:

```sh
sudo apt install elixir erlang cmake clang-15 nodejs npm default-jdk faust
curl https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein \
  -o ~/.local/bin/lein && chmod +x ~/.local/bin/lein
```

---

## Build from source

`install.sh` builds all components in dependency order and installs to `PREFIX`
(default: `~/.local/nomos-studio`):

```sh
git clone https://github.com/nomos-studio/nomos-studio
cd nomos-studio
./install.sh
export PATH="$HOME/.local/nomos-studio/bin:$PATH"
```

To build a specific component only:

```sh
./install.sh --only nomos_beam
./install.sh --only nous
./install.sh --only kairos
```

To set a custom install prefix:

```sh
PREFIX=/opt/nomos-studio ./install.sh
```

---

## Repository layout

```
nomos-studio/
  README.md
  install.sh
  components.lock          — pinned SHAs for each component at last stable release
  docs/                    — user-facing documentation (this file, getting-started, user-guide)
  doc/                     — system-level design documents (cross-component concerns)
  src/
    nomos_beam/            — THE runtime root (Elixir/OTP/Phoenix)
    nous/                  — Clojure JVM peer (ctrl-tree STM, Alembic, txlog, nREPL)
    ctrl-tree/             — Clojure STM library (dep of nous)
    alembic/               — Clojure DSP DSL compiler (dep of nous)
    nomos-rt/              — C++ library: Link peer, MIDI/CV, block-rate modulation
    kairos/                — C++ CLAP host built on nomos-rt; full audio deployment
    aion/                  — C++ nomos-rt wrapper without audio; constrained nodes
    kairos-grid/           — Modular DSP engine as CLAP plugin (GPL-3)
    bwosc/                 — Bitwig extension (Java, Jinterface peer)
    txlog/clj/             — Clojure txlog library (dep of nous)
    txlog-cpp/             — C++ txlog library (dep of nomos-rt, kairos, aion)
    nomos-maths/           — Clojure music theory and math primitives
    nomos-topology/        — Clojure topology file loading/validation
    protomatter/           — Clojure proto/schema library
    edn-cpp/               — C++20 EDN parser/emitter
    maps/                  — Device maps (EDN)
```

Each component under `src/` is its own git repository, pinned in `components.lock`.
`install.sh` clones or updates each component before building.

---

## Architecture

### Runtime root: BEAM

nomos_beam (Elixir/OTP/Phoenix) is the entry point and supervisor root. Every
other process — JVM, C++, external OSC peers — reports to it. The OTP supervisor
tree provides fault isolation, restart policies, and cluster topology.

```
nomos_beam (OTP application)
  ├── Phoenix.PubSub
  ├── NomosBeamWeb.Endpoint       — HTTP + WebSocket (LiveView, Weasel nREPL proxy)
  ├── Cluster.Supervisor          — mDNS peer discovery via libcluster
  ├── Khepri                      — Raft-based distributed session topology
  ├── NousNode                    — Erlang distribution connection to nous JVM
  ├── CtrlTreeClient              — GenServer wrapping ctrl-tree IPC
  ├── MountTableSync              — Khepri watch → nous STM mount table
  ├── BeatSupervisor              — beat-quantized service supervision
  │     ├── ConductorArc          — active arc state and scheduling
  │     └── [patch point GenServers]
  └── OscServer                   — OSC/UDP inbound bridge
```

### Peer connectivity: Jinterface and ei

Peers connect to the BEAM cluster as named Erlang nodes, not as OTP Port processes.
This gives them full Erlang message passing semantics without the Port overhead.

- **JVM peers** (nous, bwosc): use Jinterface (`OtpNode`, `OtpMailbox`). The JVM
  process registers as a named node (e.g., `nous@localhost`) and connects to the
  BEAM cookie. Messages are Erlang maps encoded as ETF.

- **C++ peers** (kairos, aion): use `ei` (erl_interface). The C++ process
  registers as a C node and participates in Erlang distribution. Messages are
  Erlang maps encoded as ETF.

**The protocol** is semantic IPC carried as Erlang terms:

```erlang
%% BEAM → nous: write a ctrl-tree path
#{op => ctrl_write,
  id => <<"ghi789">>,
  path => [voices, v1, cutoff],
  value => 0.7,
  beat => 33.125,
  source => 'laptop@localhost'}

%% nous → BEAM: beat tick
#{op => beat_tick, beat => 33.125, bpm => 120.0}

%% BEAM → nous / nous → BEAM: request/response
#{op => ping, id => <<"abc123">>}
#{op => pong, id => <<"abc123">>}
```

For the browser (WebSocket) and OSC peers, the same semantic protocol is carried
in JSON and OSC respectively. The BEAM translates at the boundary — external
peers never need to understand ETF.

For RTOS/bare-metal nodes (Daisy, RP2350): a compact binary encoding is used
on the wire (op byte + path ID + value + beat position ≈ 12 bytes), with a
symbol table negotiated at session init. The upstream ei node (aion or kairos)
owns the translation to/from ETF before forwarding to the BEAM.

### The ctrl-tree

The ctrl-tree is a Clojure STM ref tree in nous. It is the single authoritative
live state of the session. Every parameter of every device is a path in the tree.

The ctrl-tree is **not** distributed — there is one ctrl-tree, in nous, on the
session-leading node. Remote nodes write to it via IPC. Remote nodes do not hold
a copy or replica of the ctrl-tree.

Key invariant: **the ctrl-tree STM post-commit is the one txlog writer**. Nothing
else writes txlog entries. nomos-rt does not call a txlog write function. BEAM
GenServers do not write txlog entries. Fennel scripts do not. All of them send
IPC messages that arrive at the ctrl-tree write path in nous; the txlog observes
the STM commit as a post-commit side effect.

### The txlog

The txlog records ctrl-tree transitions, beat-indexed, as Parquet. It is an
artifact of the session, not a runtime database — the ctrl-tree STM is the live
state; the txlog is the historical record.

Each capable node produces its own txlog (one Parquet file per node). At session
close, node txlogs are woven into a session total order using the Link beat
position as the merge key — a deterministic sort, recomputable from the inputs.

Source attribution flows through IPC message headers: a Pi Zero that sends
`ctrl_write` messages has its events recorded in the upstream node's txlog
attributed to `pimonome@pizero.local`. The Pi Zero needs no txlog library.

### UI: Phoenix LiveView + ClojureScript + Weasel

Three channels, one Phoenix server:

- **Phoenix LiveView** — server-side reactive UI components; patch designer panels,
  session browser, device panel; works in browser, wraps in Tauri for desktop.
- **Shadow-CLJS / ClojureScript / Reagent** — rich client panels: modulation scope,
  graph visualization, arc timeline; compiled at build time, served as static assets.
- **Weasel** — nREPL over WebSocket; the browser REPL panel is a Weasel client
  connecting to the nous nREPL server. Same session as Emacs/Cider.

Tauri (Rust + system webview: WebKit on macOS, WebKitGTK on Linux) wraps the
Phoenix LiveView for desktop packaging. No bundled Chromium.

### nomos-rt: library, not process

nomos-rt is a C++ library — not a standalone process. It provides: Ableton Link
peer binding, block-rate modulation graph, MIDI I/O, CV generation/capture.

Two process-level deployments:
- **kairos**: nomos-rt + sample-rate audio tier as a CLAP host. Full deployment.
- **aion**: nomos-rt without audio. For constrained hosts (Pi Zero, headless nodes)
  or RTOS wrapping (nomos-rt as a library task on FreeRTOS/TrampolineOS).

On any given host, either kairos or aion runs — not both.

---

## Running in development

### Start the BEAM application

```sh
cd src/nomos_beam
mix deps.get
iex -S mix
```

This is the developer entry point. (The product entry point is the Tauri .app or
`.desktop` launcher — `iex -S mix` is not something users see.)

Phoenix starts on `http://localhost:4000`. If you open a browser there before
nous is connected, you will see the UI with a "waiting for nous" indicator.

### Start nous (JVM peer)

```sh
cd src/nous
lein repl :headless :host localhost :port 7888
```

nous starts as `nous@localhost` and joins the BEAM cluster. In `iex`:

```elixir
Node.list()
#=> [:"nous@localhost"]
```

Send a ping to verify IPC:

```elixir
NomosBeam.NousNode.ping()
#=> {:ok, "pong"}
```

### Start kairos (C++ CLAP host)

```sh
cd src/kairos
cmake --build build --target kairos
./build/kairos --node kairos@localhost --cookie nomos-dev
```

kairos registers as an ei C node and joins the cluster. Verify:

```elixir
Node.list()
#=> [:"nous@localhost", :"kairos@localhost"]
```

### Shadow-CLJS watch (ClojureScript dev build)

```sh
cd src/nomos_beam/assets
npm install
npx shadow-cljs watch app
```

ClojureScript panels hot-reload in the browser. Phoenix LiveView components
hot-reload via the standard Phoenix live-reloader.

---

## Component boundaries and invariants

These are the architectural decisions that must not be violated. Each one exists
for a specific reason; violations tend to create distributed consistency bugs that
are hard to trace.

**1. txlog write boundary is the ctrl-tree STM post-commit in nous.**

Nothing else calls into txlog-clj's write surface. The ctrl-tree STM commit is
the txlog write. This keeps the txlog schema, ring buffer, Parquet serialization,
beat-position stamping, and source attribution in one place.

**2. nomos-rt is a library. Aion and kairos are its process wrappers.**

nomos-rt does not start threads, own a main loop, or manage IPC connections.
Callers (aion, kairos) do that. This makes nomos-rt usable as an RTOS task
without modification.

**3. IPC is the chokepoint for all cross-process state.**

No peer writes to the ctrl-tree by any path other than IPC `ctrl_write` messages.
No peer reads the ctrl-tree by any path other than IPC `ctrl_read` messages.
This ensures source attribution and txlog coverage are complete.

**4. The BEAM does not write txlog entries.**

BEAM GenServers send IPC to nous; nous writes the txlog. BEAM never imports
txlog-clj. This keeps the txlog boundary clean and prevents distributed write
contention.

**5. One semantic protocol, multiple encodings.**

The `:op`/`:path`/`:value`/`:beat`/`:source` protocol is the same across all
transports. ETF for Erlang nodes, JSON for WebSocket/browser, OSC encoding for
OSC peers, compact binary for RTOS nodes. Do not design encoding-specific protocol
extensions; extend the protocol, then add encoding support for each transport.

**6. nomos_beam is the runtime root; nomos-studio is the product.**

`mix run` / `iex -S mix` is the developer invocation. Users never see it. The
product entry point is the Tauri .app on macOS, the .desktop entry on Ubuntu,
the Nerves image on embedded targets.

---

## Component build reference

### nomos_beam (Elixir)

```sh
cd src/nomos_beam
mix deps.get
mix compile
mix test
```

Phoenix assets (ClojureScript, CSS):

```sh
cd src/nomos_beam/assets
npm install
npm run build          # production build
npx shadow-cljs watch  # dev watch
```

Tauri desktop build:

```sh
cd src/nomos_beam
cargo tauri build      # produces .app (macOS) or .deb/.AppImage (Linux)
```

### nous (Clojure/JVM)

```sh
cd src/nous
lein deps
lein compile
lein test
lein repl              # interactive development
```

### ctrl-tree, alembic, nomos-maths (Clojure libraries)

```sh
cd src/<component>
lein install           # installs to ~/.m2 for local deps
lein test
```

### nomos-rt, kairos, aion (C++)

```sh
cd src/<component>
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(nproc)
ctest --test-dir build
```

For release builds:

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PREFIX
cmake --build build --target install
```

### bwosc (Java/Bitwig extension)

```sh
cd src/bwosc
./gradlew build
./gradlew installExtension   # copies to Bitwig extension directory
```

bwosc requires Bitwig Studio to be installed (uses the Bitwig extension SDK).

---

## Testing

Each component has its own test suite. `install.sh --test` runs all of them.

```sh
./install.sh --test
```

Per-component:

```sh
lein test                        # Clojure components
mix test                         # nomos_beam
ctest --test-dir build           # C++ components
./gradlew test                   # bwosc
```

**Integration tests** (require the full stack running):

```sh
cd src/nomos_beam
mix test --only integration
```

Integration tests start nous and a mock kairos ei node, exercise the IPC
bridge, and verify ctrl-tree round-trips. They are excluded from the default
`mix test` run to keep CI fast.

---

## Code conventions

### Repository and directory naming

Naming follows toolchain conventions within each language ecosystem:

- **Elixir/Mix** (e.g., `nomos_beam`): **underscore**. Mix project names and OTP
  application atoms cannot contain hyphens; the directory name matches the app atom.
- **Everything else** (Rust, C++, Clojure, data): **hyphen**. `nomos-tauri`,
  `nomos-rt`, `nomos-maths`, `nomos-studio` follow the broader ecosystem convention
  where hyphens are the natural word separator in repo and package names.

The split is intentional and toolchain-native, not an inconsistency. When adding a
new component, follow the convention for its primary language.

### Elixir (nomos_beam)

- Standard mix format: `mix format` before committing.
- GenServer names are module-scoped (no global atom names except for the
  explicitly registered supervision tree entries).
- PubSub topic names follow the pattern `"nomos:ctrl_tree:<path>"` for
  ctrl-tree change events.

### Clojure (nous, alembic, ctrl-tree)

- Leiningen standard layout; `lein fmt` (cljfmt) before committing.
- Namespace hierarchy mirrors the source path: `nous.ctrl` is `src/nous/ctrl.clj`.
- Avoid `dosync` outside the ctrl-tree write path. STM is for the ctrl-tree;
  atoms are for everything else.

### C++ (nomos-rt, kairos, aion)

- C++20 throughout. clang-format (`.clang-format` in each repo root) enforced
  by pre-commit hook.
- nomos-rt: no heap allocation in the audio callback. Block-rate code (non-
  audio-callback path) may allocate.
- ei calls: check return values; ei errors map to OTP `{error, Reason}` replies.

### Commit messages

Follow the existing log style: imperative mood, present tense, 72-character subject.
No trailing period. Body explains *why*, not *what* (the diff shows what).

---

## Pre-commit hooks

Each component ships a `scripts/pre-commit` hook that checks for:
- Secrets and personal path hardcoding
- C++ clang-format violations (C++ repos only)

Install after cloning a component:

```sh
cp scripts/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

`install.sh` installs hooks in all cloned components automatically.

---

## Design documents

Cross-component design documentation lives in `doc/`:

| Document | Contents |
|----------|---------|
| [doc/design-architecture.md](../doc/design-architecture.md) | Component roles, peer protocol, ctrl-tree model, kairos CLAP host design |
| [doc/design-decisions-open.md](../doc/design-decisions-open.md) | Open cross-component design questions |

Component-internal design documents live in each component's own `doc/` directory
(e.g., `src/nous/doc/`, `src/kairos/doc/`).

---

## Deployment targets

See [README — deployment spectrum](../README.md#deployment-spectrum) for the full
target table. Notes relevant to developers:

**Nerves builds**: Nerves images are built with `mix firmware` inside `src/nomos_beam`
when the `MIX_TARGET` env var is set:

```sh
MIX_TARGET=rpi4 mix firmware
MIX_TARGET=rpi4 mix burn   # writes to SD card
```

The Nerves toolchain downloads automatically on first build. Cross-compilation of
kairos/aion for ARM is handled by the Nerves toolchain's sysroot.

**RTOS / bare metal**: nomos-rt can be built as a static library for RTOS targets.
CMake toolchain files for RP2350 (Pico SDK) and STM32/Daisy (arm-none-eabi) are
in `src/nomos-rt/cmake/`. The RTOS build excludes the rtmidi, Link, and edn-cpp
dependencies; wire protocol is compact binary (no EDN parser needed on-device).
