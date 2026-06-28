# Getting started with nomos-studio

nomos-studio is a live performance environment for electronic music. This guide
takes you from installation to your first session: a synth playing through your
audio interface, a controller knob mapped to a parameter, and a named surface
patch you can apply as a gesture.

---

## What you need

**For macOS or Ubuntu Studio:**
- macOS 13 (Ventura) or later, or Ubuntu 22.04 LTS or later
- An audio interface (USB or Thunderbolt)
- Optionally: a MIDI controller or synthesizer; a LinnStrument or other MPE controller

No programming background is required to get started. The REPL is there when you
want it, not before.

**For Raspberry Pi (Nerves image):** see [Nerves installation](#nerves-installation) below.

---

## Installation

### macOS

Download the latest `nomos-studio-x.y.z-macos.dmg` from the releases page.

1. Open the .dmg and drag **nomos-studio** to your Applications folder.
2. Double-click **nomos-studio** in Applications.
3. macOS will ask for microphone permission (for audio input monitoring) and
   network permission (for mDNS peer discovery). Allow both.
4. A browser window opens automatically at `http://localhost:4000`.

That is the nomos-studio interface. The application runs as a background service;
the Tauri window is its UI. Quitting the app stops the service and closes the session.

### Ubuntu Studio

Download the latest `nomos-studio-x.y.z-amd64.deb` from the releases page.

```sh
sudo dpkg -i nomos-studio-x.y.z-amd64.deb
nomos-studio
```

The Gnome .desktop entry installs automatically. You can also launch from the
applications menu under **Sound & Video → nomos-studio**.

A browser window opens at `http://localhost:4000`.

---

## First launch

When nomos-studio starts for the first time, it opens a minimal sample session:

- Your primary audio interface is connected as the output.
- All MIDI input is routed to a default SurgeXT voice.
- Beat is running at 120 BPM.
- The conductor arc is empty and ready to author.

The **patch designer** shows this as a graph. You will see:
- The **beat port** at the top — the temporal backbone everything else is anchored to.
- An **audio output** mount region for your interface.
- A **voices** mount region with a single SurgeXT voice labelled `v1`.
- No cables yet — that comes in a moment.

Play a note on your MIDI controller. You should hear the default SurgeXT patch.
If you do not hear audio, check [audio troubleshooting](#audio-troubleshooting).

---

## Connecting a MIDI device

If your MIDI controller did not appear automatically, open the **Device panel**
(icon in the left sidebar). All detected MIDI ports are listed.

Click a port to connect it. Connected MIDI input flows to the default voice
immediately. Click the port name to rename it — names persist across sessions.

For a LinnStrument or other MPE controller: nomos-studio detects MPE automatically.
In the Device panel, set the MPE zone (default: lower zone, channels 1–15). The
theory keyboard updates to show the LinnStrument grid layout.

---

## Your first cable

A cable connects one ctrl-tree path to another, with an optional expression.
The simplest cable maps a controller CC to a parameter.

**In the patch designer:**

1. Click on `[:midi :controller :cc74]` — the MIDI CC 74 node (often labelled
   "Timbre" or "Brightness" on MPE controllers).
2. Click **New cable** in the node inspector on the right.
3. Click on `[:voices :v1 :cutoff]` — the SurgeXT filter cutoff.
4. The cable appears with the expression `identity` — a direct 1:1 mapping.

Move CC 74 on your controller. The filter cutoff follows. The cable label shows
the live value.

**To give the cable an expression** — say, scale and offset — click the cable to
open the expression editor:

```clojure
(fn [x] (* x 0.8))
```

The expression is Clojure. It compiles and takes effect immediately. You do not
need to restart anything.

**Equivalently, in the REPL:**

```clojure
(defcable cc74->cutoff
  :from [:midi :controller :cc74]
  :to   [:voices :v1 :cutoff]
  :expr (fn [x] (* x 0.8)))
```

Typing this in the REPL panel produces the same cable you would draw visually.
The patch designer updates to show it.

---

## Your first surface patch

A surface patch is a named configuration you can apply as a single musical gesture.
It is a snapshot of any subset of the ctrl-tree — not a full recall, but a musical
intention: "this is what :buildup means."

**Define one:**

```clojure
(defsurface-patch :buildup
  [:voices :v1 :cutoff]   0.7
  [:voices :v1 :resonance] 0.4
  [:theory :mode]         :dorian)
```

This registers a patch that, when applied, sets the filter to an open, resonant
position and shifts the harmonic context to Dorian mode simultaneously, in a single
ctrl-tree transaction.

**Apply it:**

Click **:buildup** in the Surface Patches panel, or:

```clojure
(apply-surface-patch! :buildup)
```

Everything listed in the patch updates atomically. The theory keyboard responds
to the new mode immediately.

**Save it to the session** — surface patches defined in the REPL are saved in the
session's code artifact at session close.

---

## The REPL

The REPL is a Clojure nREPL server. You can reach it from:

- **The browser**: the REPL panel (icon in the left sidebar) connects automatically.
  Type Clojure expressions; results appear inline.
- **Emacs/Cider**: `M-x cider-connect` → localhost, port 7888 (shown in the REPL
  panel header). Same nREPL session as the browser; both are peers.

You do not need the REPL to use nomos-studio. It is there for when you want to
go beyond what the visual surface offers — defining cables with complex expressions,
writing conductor arcs, querying session history.

---

## The conductor arc

The conductor arc is a beat-aligned sequence of gestures: surface patches, theory
transitions, parameter trajectories. It is the score for your performance.

A minimal arc:

```clojure
(defarc :main
  (at 0   (apply-surface-patch! :intro))
  (at 32  (apply-surface-patch! :buildup))
  (at 64  (apply-surface-patch! :peak))
  (at 96  (apply-surface-patch! :breakdown))
  (at 128 (apply-surface-patch! :outro)))
```

This says: at beat 0, apply :intro; at beat 32, apply :buildup; and so on.

The arc runs against the live beat clock. You can rewrite it mid-performance — in
the REPL, evaluate a new `defarc` form and the arc updates on the next beat.

The Conductor Arc panel shows the current arc as a horizontal timeline. You can
drag patch points, add new events, and scrub the position marker.

---

## Saving and closing a session

nomos-studio sessions are git repositories. You do not need to know git to use
them — the porcelain handles it — but you can use `git log`, Magit, or any git
tool directly if you want to.

**Name and save the current session:**

Click **Session → Save as** in the menu bar, or:

```sh
nomos session save "live-2026-06-28"
```

This creates a named snapshot: a commit in the session repo with your cables,
surface patches, arc, and notes.

**Close a session:**

Click **Session → Close**, or:

```sh
nomos session close
```

Session close collects all artifacts: the txlog Parquet, your Bitwig project (if
running), MIDI captures, and patch files. Everything is committed to the session
repo in one artifact commit. The session is then available in Session History for
later review, query, or replay.

---

## Multi-node sessions

If you have a second machine, a Zynthian, or any other nomos-capable node on the
same network, it discovers the session automatically via mDNS. The **Device panel**
shows discovered peers.

When a peer joins:
- Its ctrl-tree mount region appears in the patch designer.
- Its MIDI devices appear in the Device panel.
- Its local txlog is attributed to its node ID in the session total order.

You can draw cables between nodes as easily as within a single node.

---

## Nerves installation

For Raspberry Pi 4 or Zynthian hardware, nomos-studio ships as a Nerves image —
a complete Linux system with BEAM, kairos, and the UI pre-configured.

### Download

Download the appropriate image for your hardware from the releases page:
- `nomos-studio-x.y.z-rpi4.img.gz` — Raspberry Pi 4 (nomos-instrument configuration)
- `nomos-studio-x.y.z-zynthian.img.gz` — Zynthian hardware

### Flash and boot

```sh
# macOS: using Etcher or dd
gunzip -c nomos-studio-x.y.z-rpi4.img.gz | sudo dd of=/dev/diskN bs=1m

# Linux:
gunzip -c nomos-studio-x.y.z-rpi4.img.gz | sudo dd of=/dev/sdX bs=1M status=progress
```

Insert the SD card, connect a display (HDMI), and power on.

On first boot, the system initializes the session storage (a few minutes). When
ready, the nomos-studio interface appears on the connected display.

### Network access

The device advertises on mDNS as `nomos-instrument.local`. From any machine on
the same network:

```
http://nomos-instrument.local:4000
```

If you have multiple Nerves nodes, each gets a unique hostname based on its hardware
ID (e.g., `nomos-instrument-a3f2.local`).

### Display and controls (Pi 4 + touchscreen)

On a Pi 4 with a connected display, Sway (a lightweight Wayland compositor) manages
the screen. The default workspace shows the nomos-studio interface. A control bar
at the bottom lets you switch between:

- **nomos-studio** — the main patch designer and session UI
- **SurgeXT** — the SurgeXT editor window (if SurgeXT is loaded and configured for
  display)

A physical button on the enclosure (if present) also switches workspaces.

---

## Audio troubleshooting

**No audio output:**
- Open the Device panel and confirm your audio interface is listed and selected as
  the primary output.
- On macOS, check System Preferences → Sound → Output.
- On Linux, check `aplay -l` to confirm the interface is visible to ALSA.

**Audio crackling or dropouts:**
- Increase the buffer size in the Device panel → Audio settings. 256 or 512 samples
  is typical for live performance; 128 if your system handles it.
- On Linux, check that your user is in the `audio` and `realtime` groups.

**MIDI not appearing:**
- On macOS, confirm the device appears in Audio MIDI Setup.
- On Linux, confirm `aconnect -l` shows the device.
- USB MIDI hubs sometimes require a powered hub; try connecting directly.
