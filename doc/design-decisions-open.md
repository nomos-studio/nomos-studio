# nomos-studio — Open Design Decisions

Cross-component design questions that do not belong in any single component's
tracker. Component-internal questions live in each component's own
`design-decisions-open.md` (nous) or README (kairos-grid).

Each entry carries a Q-number for cross-reference.

---

## kairos — CLAP host

### Q1 — Plugin GUI delegation: what supporting CLAP GUIs implies

**Context**

kairos is headless by design. The performance path is always ctrl-tree-driven.
However, certain CLAP plugins that are in scope (Surge XT being the canonical
case) have interaction modes that cannot be expressed as parameter value writes:
wavetable browsing, mod matrix configuration, patch/preset browsing. These are
*selection* operations.

The correct answer is not to build these UIs in kairos. CLAP has a GUI extension.
kairos can surface a plugin's own editor window when needed, delegating authoring
to the instrument that knows how to do it. Plugin GUI is an authoring/setup tool,
not part of the performance path.

**What implementing CLAP GUI host-side implies for kairos:**

1. Implement the CLAP GUI extension host-side:
   - `clap_host_gui` — window lifecycle callbacks (create, destroy, show, hide)
   - Platform window embedding or floating window management (macOS: NSView/NSWindow; Linux: XEmbed or top-level)
   - Resize event handling (`request_resize` from plugin → host adjusts window)

2. A mechanism to trigger "show plugin GUI" from the ctrl tree or nous REPL:
   ```clojure
   (kairos/show-plugin-ui! :surge-xt)   ; surfaces the Surge XT editor
   (kairos/hide-plugin-ui! :surge-xt)
   ```
   This writes to `[:kairos :surge-xt :ui :visible]`. kairos watches this path
   and calls the CLAP GUI extension accordingly.

3. The plugin GUI is never on the performance path. It is opened for authoring
   (patch editing, mod matrix setup, wavetable selection) and dismissed. All
   live performance interaction goes through the ctrl tree.

**Boundary**: kairos never has a *plugin browser* or discovers plugins dynamically.
GUI delegation is per-plugin and opt-in, scoped only to topology-declared entries.
Supporting Surge XT's GUI does not make kairos a general plugin host.

**Open**: platform window strategy — embedded (NSView parented to a kairos shell
window) vs floating (detached plugin window, simpler but less integrated). Floating
is the lower-effort path and sufficient for v1.

---

### Q2 — Surge XT preset loading: ctrl tree ↔ CLAP state extension bridge

**Context**

Surge XT's parameter automation works via normal CLAP parameter IDs → ctrl tree
paths. This covers real-time control completely. What it does not cover: loading
a named patch from Surge XT's factory or user library.

Surge XT patches are files on disk (`.fxp` format, in a well-known directory
structure). Loading a patch applies a complete synthesizer state — oscillator
types, mod matrix, wavetable selections, effects — that cannot be reconstructed
by writing individual parameters.

**Proposed design:**

kairos indexes the Surge XT preset library at startup and exposes it as a ctrl
tree discovery set:

```clojure
(ctrl/get [:kairos :surge-xt :presets])
;=> #{:evolving-pads/morphic-bliss :leads/sawtooth-hero ...}
```

Loading a preset writes to a dedicated path:

```clojure
(ctrl/set! [:kairos :surge-xt :preset] :evolving-pads/morphic-bliss)
;; kairos resolves the keyword → file path → loads via CLAP state extension
```

kairos handles this by:
1. Resolving the keyword back to a file path via the preset index
2. Reading the `.fxp` bytes
3. Calling `clap_plugin_state.load()` with the state stream

The current loaded preset is readable:
```clojure
(ctrl/get [:kairos :surge-xt :preset])   ;=> :evolving-pads/morphic-bliss
```

**What this implies for kairos:**
- Implement `clap_host_state` / `clap_plugin_state` extension support
- Preset library indexer: walk Surge's factory + user patch directories at startup
- Keyword normalisation: same algorithm as bwosc name normalisation (trim, lowercase, etc.)
- `[:kairos :surge-xt :presets]` discovery index in the ctrl tree
- `[:kairos :surge-xt :preset]` readable/writable ctrl tree path

**What this implies for nous:**
- `nous.surge` namespace (or `nous.kairos` extension): `(surge/load-preset! kw)`,
  `(surge/presets)` — thin wrappers over `ctrl/set!` and `ctrl/get`
- Surge XT device map in `resources/devices/surge-xt.edn` covering the
  most important parameters by name

**Open**: keyword normalisation of the nested patch directory structure
(factory presets are in `Patches/<category>/<name>.fxp`). The `:category/name`
keyword convention above handles this; edge cases (spaces, special chars in
Surge's factory names) need the standard normalisation pass.

---

## Peer protocol

### Q3 — OSC /sub + /val subscription protocol: implement in nous.peer

**Context**

`design-distributed-embedded.md §5` defines the peer subscription protocol that
is the foundation for non-Clojure peer integration (bwosc, VCVRack, GigPerformer,
embedded nodes). Currently `nous.peer` only implements UDP multicast discovery
and `mount-peer!` (HTTP polling). The subscription push model is Phase 3 in the
original design.

bwosc depends on this being implemented in nous — specifically:

- `osc/on-msg! "/nous/bitwig/val"` — inbound subscription stream handler
- nous advertising its own OSC port in its beacon so bwosc knows where to push

**What implementing this implies for nous:**
- nous needs an inbound OSC listener (confirm `nous.osc` supports this; implement
  if not)
- Beacon payload gains `:osc-port` for nous's own OSC listener
- `nous.peer` gains `subscribe-peer!` (or folds into `nous.bitwig/connect!` for
  the bwosc case) — sends `/nous/<node-id>/sub <path>` to a discovered peer
- The inbound `/val` handler maps `(osc-decode-path path-str) → ctrl/set!`

This is also the prerequisite for any future non-Clojure peer integration beyond
bwosc (VCVRack OSC, GigPerformer, embedded Pi nodes running aion-lite).

---

## Surface adapters

### Q4 — nous.surface: in nous or standalone repo?

**Context** (from `nous/doc/design-studio-orchestration.md`)

The protocol adapters (FaderPort native, MCU, HUI) and the strip assignment model
(EDN-driven ctrl tree path → physical strip) could live in nous or as a standalone
`nomos-studio/surface` repo. Given that the strip assignment model is ctrl-tree-
dependent, keeping it in nous is lower friction initially.

**Recommendation**: start in nous as `nous.surface.*` namespaces; extract to a
standalone repo if it develops its own release cadence or outside consumers.

### Q5 — SSL 360° mediation

SSL UF8/UF1/UC1 require SSL 360° middleware running on the host. Does nous speak
MCU to SSL 360° (which then speaks to the hardware), or is there a direct path?

**Current plan**: speak MCU to 360°, treat the SSL family as MCU devices.
Confirm this is sufficient for the full UF8 feature set (soft keys, scribble
strip colour, etc.) before implementing.
