# nomos-studio

nomos-studio is a live performance environment for electronic music. It is the
layer that unifies your synthesizers, controllers, DAW, and studio hardware into
a single conductable instrument — patchable at every timescale from audio rate to
session arc.

The interface is a browser. Open the desktop app, point any browser to the device,
or deploy it on a Raspberry Pi as a dedicated nomos-instrument. The same session
runs on a laptop during composition and on an embedded touchscreen device on stage.

A built-in REPL (Clojure/nREPL, accessible from the browser or Emacs) lets you
define cables, apply patches, and rewrite the conductor arc live without leaving
the performance context.

---

## For musicians — download and install

**[→ Getting started](docs/getting-started.md)**

Requirements: macOS 13+ or Ubuntu 22.04+. No programming background required.

For embedded deployment on Raspberry Pi or Zynthian hardware:
→ [Nerves image installation](docs/getting-started.md#nerves-installation)

---

## For developers — build from source

**[→ Developer setup and architecture](docs/developing.md)**

nomos-studio is an Elixir/OTP/Phoenix application at its root, with a Clojure JVM
peer (nous), C++ audio engine (kairos built on nomos-rt), and a browser UI built on
Phoenix LiveView and ClojureScript. Start with the developer guide for prerequisites,
build instructions, and the architecture overview.

```sh
git clone https://github.com/nomos-studio/nomos-studio
cd nomos-studio
./install.sh
```

---

## What it does

**Synthesis.** kairos is a CLAP host running SurgeXT and Alembic-authored DSP
plugins at audio rate. Every parameter — oscillator type, filter cutoff, reverb
decay, effect send — lives in the ctrl-tree and is reachable by every other layer.

**Modulation.** Cables connect ctrl-tree paths with expressions ranging from simple
value mapping to continuous DSP running at block rate (~375 Hz). Define a cable
visually in the patch designer or type `defcable` in the REPL — both produce the
same form and the UI updates immediately.

**Theory.** An active harmonic context (key, mode, scale, density, function) that
every layer reads. Change the mode from the keyboard panel; the LinnStrument layout,
arpeggiators, chord generators, and voice leading all respond without reconfiguration.

**Performance structure.** The conductor arc: a beat-aligned timeline of surface
patches — named full-system configurations applied as single musical gestures.
"Apply :buildup" shifts oscillator balance, filter sweeps, effects routing, and
theory context simultaneously, in one ctrl-tree transaction.

**Hardware integration.** MIDI controllers and synths, CV/modular via Expert Sleepers
ES modules, LinnStrument MPE, OSC controllers including TouchOSC with ctrl-tree-
compiled layouts. Bitwig runs as a peer — the DAW is one device in the session, not
the host.

**Session capture.** A nomos-studio session is a git repository. The txlog records
ctrl-tree transitions beat by beat. At session close, DAW artifacts, MIDI captures,
patches, and live code are committed alongside the txlog. The session total order
is a Parquet file queryable with DuckDB, SQL, or any tool that reads Parquet.

---

## Architecture overview

```
Desktop app (Tauri) / Browser / Nerves touchscreen
         ↕  Phoenix LiveView, ClojureScript panels, Weasel nREPL-over-WebSocket
BEAM (nomos_beam)
  OTP supervisor tree — BeatSupervisor, Khepri session topology, mDNS peer discovery
         ↕  Erlang distribution (Jinterface — named nodes)
nous  (Clojure/JVM)
  ctrl-tree STM — live session state
  Alembic compiler — defcable → block-rate DSP
  txlog writer — beat-indexed session history
  nREPL — the REPL surface, accessible from browser and Emacs
         ↕  ei (Erlang interface, C nodes)
kairos (C++ CLAP host) — full deployment: laptop, desktop, Pi 4
aion   (C++ Link peer) — constrained deployment: Pi Zero, headless nodes
         both built on nomos-rt (shared C++ library: Link, MIDI, block-rate modulation)
```

The BEAM is the runtime root. All peers — JVM, C++, external hardware bridges —
report to it via Erlang distribution. The ctrl-tree in nous is the live session
state; the txlog is its history. bwosc (Bitwig extension) and external OSC peers
join as named nodes through the same protocol.

---

## Deployment spectrum

| Target | What runs | UI |
|---|---|---|
| macOS desktop | Tauri .app + BEAM + kairos | Tauri webview |
| Ubuntu Studio | Gnome .desktop + BEAM + kairos | Tauri webview |
| Raspberry Pi 4 + touchscreen | Nerves image, Sway + BEAM + kairos/aion | Tauri + Sway |
| Raspberry Pi 4 headless | Nerves image, BEAM + kairos/aion | Remote browser |
| Raspberry Pi Zero | Nerves, BEAM + aion | Plug endpoint or focused LiveView |
| RTOS / bare metal | nomos-rt library task | None (IPC upstream) |

---

## Component index

| Component | Role |
|-----------|------|
| [nomos_beam](src/nomos_beam/) | Runtime root — Elixir/OTP/Phoenix |
| [nous](src/nous/) | Ctrl-tree STM, Alembic, txlog writer, nREPL |
| [nomos-rt](src/nomos-rt/) | C++ library — Link peer, MIDI/CV, block-rate modulation |
| [kairos](src/kairos/) | CLAP host + nomos-rt; full audio deployment |
| [aion](src/aion/) | nomos-rt without audio; constrained/headless nodes |
| [alembic](src/alembic/) | DSP DSL — `defcable` → Faust → WASM/CLAP |
| [txlog](src/txlog/) | Session transaction log (Parquet, beat-indexed) |
| [bwosc](src/bwosc/) | Bitwig extension (Jinterface peer) |
| [ctrl-tree](src/ctrl-tree/) | Clojure STM library (dep of nous) |
| [edn-cpp](src/edn-cpp/) | C++20 EDN parser/emitter |
| [kairos-grid](src/kairos-grid/) | Modular DSP engine as CLAP plugin |

---

## Documentation

| Document | Audience |
|----------|----------|
| [Getting started](docs/getting-started.md) | First installation and first session |
| [User guide](docs/user-guide.md) | Patch designer, cables, arcs, hardware, multi-node |
| [Developing](docs/developing.md) | Build from source, architecture, contributing |
| [doc/design-architecture.md](doc/design-architecture.md) | System design reference |
