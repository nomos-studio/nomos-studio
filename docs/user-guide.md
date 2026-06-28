# nomos-studio user guide

This guide covers nomos-studio in depth: the patch designer, cable authoring, the
conductor arc, hardware integration, multi-node sessions, and the REPL. It assumes
you have completed [Getting started](getting-started.md) and have a working session.

---

## The ctrl-tree

The ctrl-tree is the live state of nomos-studio. Every parameter of every device in
your session — synthesizer voice parameters, effects settings, MIDI routing,
controller mappings, harmonic context — lives in the ctrl-tree as a path and value.

A ctrl-tree path looks like:

```
[:voices :v1 :cutoff]
[:voices :v1 :resonance]
[:theory :mode]
[:theory :root]
[:midi :controller-1 :cc74]
[:kairos :effects :reverb :decay]
```

Paths are hierarchical. The root segments name the mount region (`:voices`,
`:theory`, `:midi`, `:kairos`). The leaf segment names the parameter.

Everything in nomos-studio — cables, surface patches, conductor arcs, observation
instruments — is ultimately a read or write on the ctrl-tree. Understanding this
model makes the rest of the system straightforward.

---

## The patch designer

The patch designer is the visual representation of the ctrl-tree. Open it from the
left sidebar.

### Reading the graph

**Rate tier colors** indicate how fast a node updates:

| Color | Tier | Rate | Examples |
|-------|------|------|---------|
| Blue | Beat rate | 0.5–8 Hz | Conductor arc, surface patches, theory transitions |
| Yellow | Block rate | ~375 Hz | Modulation cables, LFOs, envelope followers |
| White | Sample rate | 44.1–96 kHz | Audio processing in kairos |

Cables between nodes of different colors cross a rate boundary. nomos-studio handles
the boundary automatically — but it is useful to see it in the graph because crossing
from block-rate to sample-rate has implications for latency and CPU.

**Mount regions** are the spatial areas of the graph. Each device or subsystem
appears in its own region:
- **voices** — synthesizer voices in kairos
- **theory** — harmonic context
- **midi** — MIDI inputs and controllers
- **kairos** — audio effects, outputs
- Peer nodes — each remote peer appears as a distinct mount region labelled with
  its node ID (e.g., `zynthian@local`)

### Node inspector

Click any node to open its inspector on the right panel. The inspector shows:
- Current value (live, updates continuously)
- The paths that write to it (upstream cables)
- The paths it writes to (downstream cables)
- For block-rate nodes: the expression currently compiled for this path

### Creating nodes

Ctrl-tree paths that don't exist yet can be created as named nodes. Click **+ Node**
in the toolbar and type a path. The node appears immediately and can receive cables.

---

## Cables

A cable connects a source path to a destination path, with an optional expression
that transforms the value in transit.

### Simple cables

The simplest cable is an identity mapping:

```clojure
(defcable :cc74->cutoff
  :from [:midi :controller-1 :cc74]
  :to   [:voices :v1 :cutoff])
```

MIDI CC 74 (0–127, normalized to 0.0–1.0 by nomos-studio) drives the filter cutoff
directly. The expression defaults to `identity`.

### Cables with expressions

Expressions are Clojure functions compiled at block rate. They receive the current
source value and return the destination value:

```clojure
(defcable :cc74->cutoff-scaled
  :from [:midi :controller-1 :cc74]
  :to   [:voices :v1 :cutoff]
  :expr (fn [x] (+ 0.2 (* x 0.6))))
```

This maps the CC range to cutoff values between 0.2 and 0.8, avoiding extremes.

Expressions can be as complex as needed. They run at block rate (~375 Hz), so
computationally intensive functions will affect audio performance. For heavyweight
processing, use an Alembic DSP node (see below).

### Multi-source cables

A cable can combine multiple sources:

```clojure
(defcable :blended-cutoff
  :from [[:midi :controller-1 :cc74]
         [:midi :controller-1 :cc11]]
  :to   [:voices :v1 :cutoff]
  :expr (fn [[brightness expression]]
          (+ (* brightness 0.6)
             (* expression 0.4))))
```

The expression receives a vector of all source values.

### Beat-rate cables

Some cables should only update on beat boundaries, not continuously:

```clojure
(defcable :mode-on-bar
  :from  [:conductor :theory-mode]
  :to    [:theory :mode]
  :rate  :beat
  :phase 0)   ; apply at the bar, not on any sub-beat
```

Beat-rate cables are shown in blue in the patch designer.

### Removing cables

Click the cable in the graph and press Delete, or:

```clojure
(remove-cable! :cc74->cutoff)
```

### The cable as live code

Every cable defined visually generates the equivalent `defcable` form. You can
copy it from the node inspector. Typing a `defcable` form in the REPL creates the
same cable visually. There is no difference between the two paths — they share one
representation.

---

## Alembic DSP nodes

For audio-rate or block-rate computation more complex than a simple expression,
Alembic provides a DSL for DSP authored in Clojure that compiles to Faust and runs
as a CLAP plugin in kairos.

An Alembic patch:

```clojure
(defpatch envelope-follower
  :input  [:voices :v1 :output]
  :output [:modulation :env-follower :level]
  (-> (alembic/rms 0.02)
      (alembic/slew 0.1 0.3)))
```

This defines a block-rate RMS envelope follower on voice 1's output, with
asymmetric slew (10ms attack, 300ms release), writing to a modulation path.
Once compiled, it appears in the graph as a yellow block-rate node.

`defpatch` forms are saved with the session and recompile on session load.

---

## The theory engine

The theory engine maintains the active harmonic context: key, mode, scale, density,
and harmonic function (tonic, subdominant, dominant). Every layer reads it.

### Setting the context

```clojure
(theory/set! :root :f#)
(theory/set! :mode :minor)
(theory/set! :scale :natural)
(theory/set! :density 3)      ; 1–7, chord voicing density
(theory/set! :function :tonic)
```

Or write the ctrl-tree paths directly:

```clojure
(ctrl/set! [:theory :root] :f#)
(ctrl/set! [:theory :mode] :minor)
```

### The theory keyboard

The Theory Keyboard panel shows the active scale highlighted on a piano keyboard.
Click any key to hear it through the active voice and add it to the theory context.
The LinnStrument layout updates in real time to reflect the current scale and root.

### Harmonic density

Density (1–7) controls how many voices are used when nomos-studio generates chords
from the theory context. At density 3, a tonic chord is a triad. At density 5, it
is a ninth chord. Generators and arpeggiation schemes respect density.

---

## Surface patches

A surface patch is a named, partial ctrl-tree snapshot — a bundle of values that
represent a musical intention. Applying a patch writes all of its values
atomically, in a single ctrl-tree transaction.

### Defining patches

```clojure
(defsurface-patch :buildup
  [:voices :v1 :cutoff]         0.72
  [:voices :v1 :resonance]      0.38
  [:kairos :effects :reverb :mix] 0.6
  [:theory :mode]               :dorian
  [:theory :density]            5)
```

Patches can contain any number of ctrl-tree paths. They do not need to be
contiguous or within one mount region.

### Applying patches

Click the patch name in the Surface Patches panel, or:

```clojure
(apply-surface-patch! :buildup)
```

### Beat-quantized patch application

To apply a patch on the next beat boundary rather than immediately:

```clojure
(apply-surface-patch! :buildup :on :next-bar)
```

Or with a specific beat offset:

```clojure
(apply-surface-patch! :buildup :at (+ (current-beat) 4))
```

### Comparing patches

The Surface Patches panel shows all defined patches. Click **Diff** between two
patches to see which ctrl-tree paths differ and by how much. Useful for checking
that two related patches (e.g., :buildup and :breakdown) have the right relationship.

---

## The conductor arc

The conductor arc is the score for your performance — a beat-aligned sequence of
gestures. It is always live: you can rewrite it during a performance, and the
updated arc takes effect on the next scheduled event.

### Defining an arc

```clojure
(defarc :main
  (at 0   (apply-surface-patch! :intro))
  (at 32  (apply-surface-patch! :buildup))
  (at 48  (theory/set! :mode :phrygian))
  (at 64  (apply-surface-patch! :peak))
  (at 96  (apply-surface-patch! :breakdown))
  (at 128 (apply-surface-patch! :outro)))
```

Events are in beats. The arc does not loop by default; to loop, define the arc
recursively or use the `:loop` option.

### Starting and stopping

```clojure
(arc/start! :main)
(arc/stop!)
```

The arc runs against the live Link beat clock. Events fire at the beat they are
scheduled for, not relative to when `arc/start!` was called.

### Live rewriting

Evaluate a new `defarc` form mid-performance. The arc updates on the next beat.
Events that have already fired are not re-fired; events that have not yet fired
use the new definition.

### The arc timeline panel

The Conductor Arc panel shows the current arc as a horizontal timeline. Beat markers
at the top; patch events as colored blocks. The playhead moves in real time with
the Link beat clock.

- Click an event block to jump to that beat.
- Drag an event to reschedule it.
- Click an empty area to add a new event.
- Right-click an event to change which surface patch it applies.

---

## Hardware integration

### MIDI controllers

MIDI controllers appear automatically in the Device panel. Every CC, note, and
channel pressure maps to a ctrl-tree path under `[:midi :<device-name> ...]`.

For a controller named "Arturia KeyStep":
```
[:midi :arturia-keystep :cc1]     ; modwheel
[:midi :arturia-keystep :cc11]    ; expression
[:midi :arturia-keystep :pressure] ; channel aftertouch
```

Rename a device by clicking its name in the Device panel. The name persists across
sessions and across reconnections.

### LinnStrument and MPE controllers

nomos-studio handles MPE natively. When an MPE controller is connected, per-note
dimensions (X=pitch slide, Y=timbre, Z=pressure) are exposed as distinct ctrl-tree
paths per voice slot:

```
[:midi :linnstrument :voice-1 :pitch]
[:midi :linnstrument :voice-1 :timbre]
[:midi :linnstrument :voice-1 :pressure]
```

The theory keyboard updates to display the LinnStrument layout (isomorphic grid)
when a LinnStrument is the active controller. The root and scale highlight on the
grid.

### CV/modular (Expert Sleepers)

Connect an Expert Sleepers ES-3, ES-5, or ES-6 (or compatible module) via ADAT
or USB. nomos-studio sees it as a set of CV input and output channels.

CV outputs map to ctrl-tree paths under `[:cv :out-1]` through `[:cv :out-8]`.
Cable from any ctrl-tree path to a CV output to send control voltage to your
modular system.

CV inputs (via ES-6 or ES-7) appear as `[:cv :in-1]` etc. and can drive any
ctrl-tree path via cable.

### OSC controllers (TouchOSC)

nomos-studio compiles TouchOSC layouts from the ctrl-tree automatically. The
Device panel → TouchOSC section shows available layout exports.

Alternatively, any OSC device that sends to the nomos-studio OSC port (default:
UDP 7700) can write to ctrl-tree paths via the OSC protocol:

```
/ctrl/voices/v1/cutoff 0.7
/ctrl/theory/mode dorian
```

Path separators map directly to ctrl-tree path segments.

### Bitwig (bwosc)

If Bitwig Studio is running, the nomos-studio Bitwig extension (bwosc) discovers
the nomos session automatically. The Bitwig peer appears in the Device panel.

Bitwig tracks and devices appear as a mount region in the patch designer:
```
[:bitwig :track-1 :volume]
[:bitwig :track-1 :device-1 :macros :macro-1]
```

You can cable from the ctrl-tree to Bitwig parameters or from Bitwig to
ctrl-tree paths. The Bitwig project is collected as an artifact at session close.

---

## Observation instruments

Observation instruments let you see what the ctrl-tree is doing in real time
without affecting it.

### Modulation scope

The Modulation Scope panel plots ctrl-tree parameter values over time. Click **+
Track** and type any ctrl-tree path to add it. Multiple paths overlay on the same
scope.

Useful for: verifying that a cable expression is doing what you expect, checking
modulation depth, identifying noise or jitter on a control signal.

### Parameter meters

The Parameter Meters panel shows VU-style live value displays for any ctrl-tree
path. Add paths from the node inspector or directly in the panel.

### Conductor arc timeline

The arc timeline (described in [The conductor arc](#the-conductor-arc) above)
doubles as an observation instrument — it shows historical events that have fired
alongside upcoming scheduled events.

---

## Multi-node sessions

nomos-studio discovers peers on the local network via mDNS. Any device running
nomos-studio that is on the same network will appear in the Device panel within
a few seconds of starting.

### Peer join

When a peer joins:
1. Its mount region appears in the patch designer.
2. Its MIDI devices and CV channels appear in the Device panel.
3. The Link beat clock synchronises automatically.

You can draw cables between your local ctrl-tree and the peer's mount region
exactly as you would within a single node.

### Distributed txlog

Each node writes its own txlog (Parquet, beat-indexed). At session close, the
node txlogs are woven into a session total order using the Link beat position as
the merge key. The result is a single chronological record of everything that
happened across all nodes, attributed by node ID.

If a peer's txlog is not immediately available at session close (delayed sync,
NAS not yet mounted), you can add it later and reweave:

```sh
nomos session weave
```

The weave is deterministic — the same inputs always produce the same total order.

### Session sync

The session repository can be pushed to a shared remote (NAS, S3, peer node):

```sh
nomos session sync --push
nomos session sync --pull    # on another machine
```

git-annex handles the large binary artifacts (Bitwig project, MIDI captures,
audio files); git handles the text artifacts (cables, patches, arc, notes).

---

## Session management

### Session history

Click **Session → History** (or `nomos session log`) to see previous sessions.
Each session entry shows: date, duration, participating nodes, and the surface
patches applied during the session.

Click a session to open it as read-only for review. Click **Replay** to play
back the txlog against the current synthesis configuration.

### Querying the session

The txlog is a Parquet file. DuckDB is included with nomos-studio:

```sh
nomos session query "SELECT * FROM txlog WHERE path LIKE '%:cutoff%' ORDER BY beat"
```

Or open a DuckDB session directly:

```sh
duckdb session/txlog/session-total-order.parquet
```

Standard SQL works against the Parquet file. Any tool that reads Parquet
(Pandas, Arrow, Spark, etc.) can read the session archive.

### Notes and seeds

The session's `README.md` is the session capture document — your notes, ideas,
and seeds from this session. Edit it in any text editor or from the Notes panel
in nomos-studio.

Seeds from the session — ideas to pursue later — can be promoted to your
personal notes with:

```sh
nomos seed "idea text here"
```

This appends to your personal seeds file outside the session repo.

---

## The REPL in depth

The REPL is a Clojure nREPL server. It shares a namespace with the live session —
cables, patches, and arcs defined in the REPL are active immediately.

### Key namespaces

```clojure
(require '[nous.ctrl :as ctrl])   ; ctrl-tree reads and writes
(require '[nous.cable :as cable]) ; cable management
(require '[nous.arc :as arc])     ; conductor arc
(require '[nous.theory :as theory]) ; harmonic context
(require '[nous.session :as session]) ; session management
```

### State inspection

```clojure
;; Read any ctrl-tree path
(ctrl/get [:voices :v1 :cutoff])  ;=> 0.7

;; Get all paths under a mount region
(ctrl/paths [:voices :v1])
;=> ([:voices :v1 :cutoff] [:voices :v1 :resonance] ...)

;; Watch a path — callback fires on every change
(ctrl/watch! [:theory :mode]
  (fn [old new] (println "Mode changed:" old "->" new)))
```

### Session state

```clojure
;; List defined cables
(cable/list)

;; List surface patches
(nous.surface/patches)

;; Current beat
(arc/current-beat)

;; Link tempo
(arc/bpm)
```

### Connecting from Emacs/Cider

```
M-x cider-connect
Host: localhost
Port: 7888
```

The browser REPL panel and Emacs/Cider share the same nREPL session. Define a
cable in one; it appears in the other. Both see the live ctrl-tree state.

### Weasel (browser nREPL)

The browser REPL panel uses [Weasel](https://github.com/nrepl/weasel) — an nREPL
transport over WebSocket. This is the same nREPL session as the Emacs connection.
No separate setup is required; it connects automatically when you open the REPL panel.
