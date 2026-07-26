<!--
SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors

SPDX-License-Identifier: EPL-2.0
-->

# Component boundaries

nomos-studio is built as loosely-coupled components that communicate across process
boundaries over **documented, arms-length protocols** — not by linking. This index
names every cross-process boundary, who speaks it, and where its protocol is specified.

This matters for two reasons:

1. **Engineering** — each boundary is a stable contract; either side can be
   reimplemented or replaced against the published protocol.
2. **Licensing** — the boundaries are what keep the differently-licensed components
   (and the AGPL keystone) cleanly separated. See [`../LICENSING.md`](../LICENSING.md).

## Convention

A component that *owns* a cross-process boundary documents it in its own repository, as
`doc/protocol-<name>.md`, using this template:

> **Purpose** · **Boundary parties** · **Transport** · **Framing** ·
> **Message vocabulary** · **Direction** · **Stability & versioning** ·
> **Reimplementation notes**

The protocol's normative source of truth is named at the top of each doc (usually the
header/module that defines the message vocabulary). This index links each.

## Boundaries

| Boundary | Parties | Transport | Owner | Protocol doc | Status |
|---|---|---|---|---|---|
| **NousPort / BEAM** | nous (EPL) ↔ nomos_beam (AGPL) | Erlang distribution | nomos_beam | [`nomos_beam/doc/protocol-nousport.md`](../../nomos_beam/doc/protocol-nousport.md) | **documented** |
| **nomos-rt IPC** | nous / aion / kairos ↔ nomos-rt | Unix socket / TCP, framed EDN | nomos-rt | [`nomos-rt/doc/protocol-ipc.md`](../../nomos-rt/doc/protocol-ipc.md) | **documented** |
| **kairos CLAP bus** | kairos host ↔ CLAP plugins; kairos ↔ kairos-grid | CLAP extensions (param / tap / patch bus) | kairos | `kairos/doc/protocol-clap-bus.md` | *to document* |
| **txlog format** | txlog writers ↔ readers (cl / clj / cpp clients) | on-disk / streamed log records | txlog | `txlog/doc/protocol-txlog.md` | *to document* |
| **aion sidecar block** | aion ↔ clients (original `0x00`–`0x2F` opcodes) | Unix socket, framed EDN | nomos-rt / aion | (folds into nomos-rt IPC) | *to document* |

The **NousPort / BEAM** boundary is the product's copyleft boundary: it is where the
AGPL `nomos_beam` keystone meets the EPL `nous` engine, arms-length over Erlang
distribution, so the AGPL is contained. Its doc states this explicitly.

## Follow-on

The `kairos` CLAP bus and the `txlog` format are enumerated above and will be
documented in their owning repos under the same convention, then linked here. Until
then, their message vocabularies live in code — `kairos` param/tap/patch bus
extensions, and the `txlog` record format shared across its cl/clj/cpp clients.
