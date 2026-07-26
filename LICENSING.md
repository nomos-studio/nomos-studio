<!--
SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors

SPDX-License-Identifier: EPL-2.0
-->

# Licensing

nomos-studio is not a single program under a single licence. It is a set of
independent components, each licensed appropriately for its role, coordinated into a
product by a network keystone. This document states the product-level position and maps
each component's licence.

## The product

**The integrated nomos-studio platform is governed by AGPL-3.0-or-later**, because the
one component that assembles and hosts the running system — **`nomos_beam`**, the
BEAM/OTP/Phoenix coordination and UI layer — is licensed AGPL-3.0-or-later. You cannot
run the coordinated product without the keystone, and the keystone is AGPL. Under
AGPL §13 this network-copyleft reaches anyone who offers a modified nomos-studio as a
hosted service: they must make their modified source available to its users.

A **commercial licence to `nomos_beam`** is the escape hatch: it removes the AGPL
obligation for parties who wish to run the integrated system closed-source or as a
proprietary hosted service. (Same open-core / copyleft-moat shape as Grafana, MongoDB,
iText.)

## The components are usable separately

The AGPL sits on the *integrated system*, not on the pieces. Every component may be used
on its own under **its own OSI licence**, independent of nomos_beam:

- `nous` (EPL-2.0) is a usable Clojure compositional engine on its own.
- The native DSP libraries (LGPL / GPL) are usable as libraries — LGPL even permits
  linking into proprietary software.
- A **library-only subset** — the engine and DSP driven from a bare REPL, without the
  BEAM coordination/UI layer — is *not* AGPL-encumbered. It is using the libraries, not
  running the product.

The moat is exactly as deep as the keystone is essential: it protects the *coordinated
product experience*, and it is the architecture — all integration routed through the one
AGPL component over documented protocols — that makes that precise.

## Containment: why the AGPL does not spread

The components are **separated by IPC / process boundaries** and communicate over
documented, arms-length protocols (see
[`doc/component-boundaries.md`](doc/component-boundaries.md)). A separate program that
talks to `nomos_beam` over Erlang distribution or a socket is not a derivative work of
it, so the AGPL is **contained within `nomos_beam`** and does not extend across the
boundary. This is not merely convenient: EPL and (A)GPL are link-incompatible, so the
IPC boundary is what lets these differently-licensed components coexist in one product
at all. It cannot be collapsed into a monolith without a relicensing event.

## Per-component licence map

| Component | Licence | Role |
|---|---|---|
| **nomos_beam** | **AGPL-3.0-or-later** (+ vendored MIT in `assets/vendor/`) | **network keystone** — BEAM/OTP peer coordination, supervision, Phoenix LiveView UI host |
| nous | EPL-2.0 (some Apache-2.0 / GPL / LGPL files) | Clojure compositional engine (theory-aware sequencing, nREPL) |
| ctrl-tree | EPL-2.0 | transactional control-surface fabric (STM tree + mounts + txlog) |
| protomatter | EPL-2.0 | IPort / IReceiver / INode / IMount substrate |
| nomos-topology | EPL-2.0 (+ GPL-3.0-or-later) | synthesis-topology schema (Session / Topology / Patch) |
| nomos-maths | EPL-2.0 | shared maths (phasor, lattice, harmonic) |
| alembic | EPL-2.0 | DSP authoring DSL (`defpatch!` → signal graph → Faust) |
| nomos-rt | LGPL-2.1-or-later (Link-linked parts GPL-2.0-or-later) | RT substrate: Link peer, MIDI/OSC/CV I/O, IPC, scheduling |
| aion | GPL-2.0-or-later | lightweight session peer (Link, no CLAP) |
| kairos | GPL (2.0-or-later / 3.0-or-later, LGPL) | CLAP host (Link + SurgeXT force GPL) |
| kairos-grid | GPL-3.0-or-later (+ BSD-3-Clause, MIT) | sample-rate engine CLAP plugin |
| txlog | BSL-1.0 / MIT | format-owned session log (cl / clj / cpp clients) |
| edn-cpp | BSL-1.0 | C++ EDN parser (IPC payload codec) |
| bwosc | EPL-2.0 | Bitwig OSC bridge |
| nomos-tauri | EPL-2.0 | desktop shell |
| nomos-studio.el | GPL-3.0-or-later | Emacs client |
| nomos-studio (this repo) | EPL-2.0 | build / orchestration meta-repo |
| txlog-cpp | see repo | C++ txlog client |
| kairos-vcv | see repo | VCVRack bridge module |

Each repository is REUSE-compliant; the authoritative per-file licensing for any
component lives in that component's own `REUSE.toml` / `LICENSES/`. Where this table and
a component's repo disagree, the repo wins.

## Contributing note

The commercial-licence lever on `nomos_beam` is only preservable while its copyright is
solely owned or aggregated. A contributor grant (CLA / DCO-with-grant) should be in
place before the first external `nomos_beam` contribution — otherwise that contribution
is AGPL-only and the dual-licence option over the whole is lost.
