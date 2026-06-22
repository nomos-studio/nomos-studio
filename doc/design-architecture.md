# nomos-studio — System Architecture

## The vision in one sentence

**The session is the nous score. Everything else is execution.**

---

## Core principle

Control surfaces are not special. DAWs are not special. Synthesizers are not
special. They are all devices — nodes in the session topology with protocols
they speak, capabilities they expose, and data flowing in, out, or both.

nous is not a device in this topology. nous is the orchestration layer above it.
It speaks all of these protocols, presents itself as any of them when needed,
and holds the session model that all devices execute.

---

## Components

| Component | Language | Role |
|-----------|----------|------|
| **nous** | Clojure | Compositional surface — theory engine, live loops, journey conductor, ctrl tree, REPL |
| **nomos-rt** | C++ | Shared substrate — Ableton Link peer, MIDI/OSC I/O, mDNS, IPC |
| **alembic** | Clojure DSL → C++ | DSP authoring — `defpatch!` → signal graph → CLAP/WASM via Faust |
| **kairos** | C++ | CLAP host + nomos-rt integration — the live audio execution engine |
| **kairos-grid** | C++ (GPL-3) | Modular DSP engine as CLAP plugin — patch-bus EDN graph, Surge XT DSP blocks, MI modules, Faust WASM |
| **aion** | C++ | Lightweight standalone peer — nomos-rt only, no CLAP; for embedded/headless nodes |
| **txlog** | C++ / Clojure | Session transaction log — SQLite + EDN; score persistence |
| **edn-cpp** | C++ | Standalone C++20 EDN parser/emitter |
| **nomos-maths** | Clojure | Music theory and math primitives |
| **nomos-topology** | Clojure | Topology file loading and validation |

### Dependency topology

```
nous ──────────────────────────────────────────────────────────────────┐
  depends on: nomos-maths, nomos-topology, txlog                      │
  speaks to: kairos (IPC/EDN), aion (IPC/EDN), bwosc (OSC), surfaces  │
                                                                       │
kairos ─────────────────────────────────────────────────────────────── hosts
  depends on: nomos-rt, edn-cpp                                        │
  hosts: kairos-grid (CLAP), alembic patches (CLAP), Surge XT (CLAP)  │
                                                                       │
kairos-grid ────────────────────────────────────────────────────────── is
  depends on: kairos (CLAP API), surge-xt (source, GPL-3), eurorack   │
  exposes: patch-bus EDN graph of audio-rate DSP modules              │
                                                                       │
alembic ────────────────────────────────────────────────────────────── feeds
  compiles defpatch! → Faust → WASM → loaded into kairos-grid         │
                                                                       │
aion ── lightweight alternative to kairos (MIDI+Link only, no CLAP)   │
nomos-rt ── shared C++ substrate used by both kairos and aion ─────────┘
```

---

## The ctrl tree as universal session state

Every device is a reader and/or writer of ctrl tree paths. Protocol adapters
translate between a device's wire format and ctrl tree operations.

```
Device gesture          Protocol adapter         Ctrl tree
──────────────────────────────────────────────────────────
FaderPort fader move  → FP native decoder    → [:surface :fp16 :strip 3 :fader]   = 0.73
Bitwig track volume   → bwosc OSC            → [:bitwig :track :lead-synth :vol]  = 0.8
T-1 note on           → MIDI-in handler      → [:ivk :current-pitch]              = 62
journey bar tick      → bar counter          → [:journey :current-bar]            = 47
harmonic tension calc → harmony engine       → [:harmony :tension]                = 0.6
kairos param change   → CLAP automation      → [:kairos :surge-xt :param :cutoff] = 0.4
```

Paths are named at every level. The path key is the scribble strip label on
any surface that addresses it. No separate label table is needed.

---

## The peer protocol

All nodes in the fabric communicate via the three-plane protocol defined in
`nous/doc/archive/design-distributed-embedded.md`:

| Plane | Protocol | Use |
|-------|----------|-----|
| 1 — Control | OSC UDP fire-and-forget | Real-time parameter changes, ctrl tree subscription pushes |
| 2 — Data | EDN over TCP | Bulk data — ctrl tree snapshots, device maps, session state |
| 3 — Scheduling | OSC bundle timetags | Beat-critical remote event scheduling via Link timeline |

### OSC peer subscription protocol (Phase 3, not yet implemented)

The ctrl tree synchronisation convention for non-Clojure peers (bwosc, VCVRack,
GigPerformer, future non-JVM nodes):

```
/nous/<node-id>/sub <path-edn>          ; subscriber → peer: subscribe to subtree
/nous/<node-id>/val <path-edn> <value>  ; peer → subscriber: push state change
/nous/<node-id>/val <path-edn> <value>  ; subscriber → peer: write (command)
```

The `/val` message is uniform in both directions. `nREPL` (`nous.remote`) is for
Clojure-to-Clojure peer connections only (nous ↔ kairos, nous ↔ aion). The OSC
subscription protocol handles everything else.

Peer discovery: UDP multicast beacon on 239.255.43.99:7743 (implemented). mDNS
(`nous.discovery`) is Phase 3 — planned as the longer-term replacement for
cross-subnet and VPN scenarios.

### Ableton Link

All nodes join the same Link session. Link is the beat/bar synchronisation
backbone — it does not transmit timing pulses, it synchronises the phase
relationship between local clocks. MIDI clock is a leaf output produced
per-node from the local Link timeline; it is never routed between nodes.

In a studio with hardware word clock, Bitwig (and kairos) are additionally
slaved to the same word clock master (RME Digiface USB) for sample-accurate
audio buffer alignment. Word clock and Link operate independently.

---

## Three-host studio topology

```
┌─────────────────────────────────────────────────────────────────────┐
│  nous — session orchestration (Mac Mini)                            │
│  score (Clojure value) · ctrl tree · journey conductor              │
│  harmony engine · generative fields · trajectory curves             │
└──────┬────────────────────────┬────────────────────┬───────────────┘
       │ bwosc OSC /sub /val    │ MCU / OSC          │ OSC (TotalMix FX)
┌──────▼──────┐           ┌─────▼──────┐    ┌────────▼─────────────┐
│   Bitwig    │           │  MixBus    │    │  Windows NUC         │
│  synthesis  │           │  tracking  │    │  routing hub         │
│  clips      │           │  mixing    │    │  RME Digiface 32×32  │
│  devices    │           │  Harrison  │    │  VCVRack (CV bridge) │
│  Grid       │           │  ch-strip  │    │  GigPerformer VSTs   │
│  (Ubuntu)   │           │  (Ubuntu)  │    └──────────────────────┘
└─────────────┘           └────────────┘
```

**Mac Mini** — composition brain. nous runs here. Focusrite Scarlett 18i20
(4th gen) → ADAT → Digiface ch 1–8. SPDIF → Tascam DA-3000 stereo recorder.

**Ubuntu Bitwig host** — synthesis and performance engine. kairos also runs
here as the headless CLAP host for FOSS plugins and alembic DSP. nous launches
clips, automates devices, drives kairos/Grid patches. Bitwig is a peer via bwosc.

**Windows NUC** — signal routing and processing hub. Not a DAW.
- RME Digiface USB: 32×32 audio matrix. Channel map:
  - ch 1–8 in/out: Mac Mini Scarlett 18i20 (ADAT)
  - ch 9–16 in: Focusrite OctoPre (preamp expansion)
  - ch 9–16 out: Arturia X-8
  - ch 17–24 in/out: ExpertSleepers ES-3/ES-5/ES-6 (Eurorack CV/gate bridge)
  - ch 25–32 in/out: Ubuntu Studio Scarlett 18i20 3rd gen (ADAT)
- VCVRack: virtual CV engine → Digiface → ExpertSleepers → hardware Eurorack
- GigPerformer Pro: VST rack, Elektron Overbridge, OSC/MIDI bridge
- Digiface/TotalMix FX: OSC on ports 7001 (receive) / 9001 (feedback)

**Windows integration is application-layer only.** aion has not been ported to
Windows and there are no plans to do so. The Windows node participates via OSC,
bwosc (Bitwig), and GigPerformer's native Link support — no nomos-rt binary.

---

## kairos — declared CLAP host

kairos is the live audio execution engine on non-Windows hosts. It is a
**declared CLAP host**, not a general plugin container:

- Plugins are declared in the topology EDN and loaded at startup. No runtime
  plugin discovery, no plugin browser, no arbitrary third-party loading.
- Supported plugins are intentionally narrow: "well understood" CLAP plugins
  available on open-source terms. Surge XT is the first candidate.
- Functional parity with GigPerformer at the **data-defined level** — rackspace
  and patch management driven by EDN topology, not a GUI — is the v1 goal.
  Non-headless GUI for kairos is not a v1 goal.

### kairos-grid

kairos-grid is a separate CLAP plugin (GPL-3) hosted by kairos. It is a modular
DSP engine — a directed graph of audio-rate modules wired by cables and described
by a patch-bus EDN descriptor. Modules include:

- Surge XT DSP blocks: oscillators, filters, effects, modulators — built
  directly from Surge's source tree at compile time (same approach as surge-rack)
- Mutable Instruments (MI) modules: Plaits macro-oscillator, SVF, one-pole filter
- Faust WASM modules: alembic `defpatch!` compiles → WASM → loaded at runtime
- Environment module: tempo, beat, transport, voice info from kairos

kairos-grid is the alembic execution target — custom DSP authored at the REPL,
compiled by alembic, hot-swapped into a running kairos-grid instance.

### Surge XT — two integration layers

These are complementary, not competing:

1. **Surge DSP blocks in kairos-grid** (implemented): individual oscillators,
   filters, effects, modulators as grid modules in a composable patch. For
   custom signal chains authored via alembic/DSL.

2. **Surge XT as a full synthesizer** (not yet implemented): load `SurgeXT.clap`
   as a declared topology entry. Full patch library, mod matrix, voice allocation,
   wavetable management. Parameter automation via CLAP parameter IDs → ctrl tree.
   Preset loading via CLAP state extension → ctrl tree bridge (open design question;
   see `design-decisions-open.md` Q2).

### Plugin GUI delegation

Certain CLAP plugins (Surge XT being the canonical case) require interaction
modes — wavetable browsing, mod matrix configuration, preset browsing — that
cannot be expressed as parameter value writes. The correct answer is bounded
delegation: kairos surfaces the plugin's own GUI window via the CLAP GUI extension
for authoring and setup. The performance path remains ctrl-tree-driven and headless.
See `design-decisions-open.md` Q1 for what implementing this implies.

---

## Surface topology

Surface strips are not mixer channels — they are physical controls for any
ctrl tree path. Assignment is EDN data; switching layouts is a runtime operation.

### Full studio

```
nous (Mac Mini)
├── FaderPort 16   — 16 compositional or conventional strips
├── FaderPort 1    — focus strip, always on the most load-bearing parameter
├── SSL UF8        — 8 additional strips via SSL 360°/MCU
├── SSL UF1        — master section / monitor control
├── SSL UC1        — plugin / device param deep control
├── TouchOSC       — iPad soft surface (OSC)
├── Bitwig         — creative DAW peer (Ubuntu)
└── MixBus         — tracking DAW peer (Ubuntu)
```

### Travel / gig minimum

```
nous (laptop)
├── FaderPort 8    — 8 compositional strips
└── ivk keyboard   — note/interval input, harmonic pivots
```

The travel instance is not a reduced version of the studio. It is the same
compositional vocabulary in a carry-on bag. When the travel rig joins the studio
as a peer via mDNS, the FaderPort 8 becomes additional surface area — more strips,
a second operator surface, a second note input.

### The gig as composition session

A nous gig produces the score. Every mutation, harmonic context, ctrl tree state,
and tension arc ridden by hand is a Clojure value. When the studio opens the next
morning, the journey conductor is paused at the bar where the set ended — not
reconstructed from audio, but resumed from the actual compositional state.

---

## Composition drives execution — the full stack

```
nous score (Clojure value)
  ↓ journey conductor fires transition at bar 48
    ↓ crystallize! ost-a — mutation rate drops toward zero
    ↓ filter-journey! ch1 — filter opens over next 32 bars
    ↓ bwosc OSC → Bitwig: launch clip :lead-synth/:drop
    ↓ kairos: load Surge XT patch :evolving-pads/morphic-bliss
    ↓ MixBus: reverb send track 1 0→0.8 over 16 bars
    ↓ surface: strip 1 fader motors to new mutation rate position
    ↓ surface: scribble strips update to "CRYST 0.02"
```

One compositional event. Every execution engine responds. No device is driving
the session — the score is.
