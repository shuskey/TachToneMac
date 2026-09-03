# TachTone for macOS

> Your Mac sounds like an engine. CPU load drives the RPM.

[![GitHub repo](https://img.shields.io/badge/repo-TachToneMac-181717?logo=github)](https://github.com/shuskey/TachToneMac)
![Platform](https://img.shields.io/badge/platform-macOS-000000?logo=apple)

TachTone is a lightweight menu bar utility for macOS that turns system activity into a living engine soundtrack. As CPU usage rises, the tone revs higher. Disk, network, GPU, and context-switching activity layer in percussion, harmonics, and arpeggios. And when Claude Code needs your attention, the app honks from the menu bar like a car horn.

---

## What you hear

| Activity | Sound |
| --- | --- |
| CPU load | Engine RPM / harmonic stack |
| Context switches / interrupt pressure | Vibrato / RPM instability |
| Disk I/O | Tom-style percussion hits |
| Network traffic | Bell and piano arpeggios |
| GPU usage | Synth organ layer |
| Claude needs attention | Two-tone honk |
| Token-cost feedback | Coin chime burst |

---

## Features

- Menu bar app with a compact settings window
- Real-time audio synthesis built on AVFoundation
- CPU, disk, network, and GPU monitoring
- Claude Code listener via local UDP socket hooks
- Optional “impatient honking” behavior when attention is ignored
- Launch-at-login support
- Per-channel volume controls for master, CPU, network, disk, GPU, honk, and token-cost feedback

---

## Install

### Build the app

From the project root:

```bash
make
```

This builds the macOS app bundle under:

```text
build/DerivedData/Build/Products/Release/TachToneMac.app
```

### Install the app and Claude hooks

```bash
./install.sh
```

This performs two actions:

1. Installs the app to `/Applications/TachToneMac.app`
2. Copies the Claude Code hook script and configures `~/.claude/settings.json`

Useful variants:

```bash
./install.sh --app-only
./install.sh --hooks-only
```

### If macOS blocks the app

Because this is a locally built app, Gatekeeper may reject it on first launch. If needed, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine "/Applications/TachToneMac.app"
```

Then open the app again. If further blocking occurs, allow it in System Settings → Privacy & Security.

---

## Run it

Launch `TachToneMac` from:

- `/Applications`
- Spotlight
- Launchpad

Once running, it sits quietly in the macOS menu bar as a small `T` indicator.

### Menu bar actions

- Settings… — open the volume mixer and behavior controls
- Quit TachTone — stop the app

---

## Settings

Choose Settings… from the menu bar icon to adjust:

- Master
- CPU
- Network
- Disk
- GPU
- Honk
- Token Cost

Additional toggles:

- Impatient honking — allow the honk to escalate if attention is ignored
- Launch at login — register or unregister the app for login startup

---

## Claude Code integration

The installer automatically configures hooks for Claude Code by copying:

```text
hooks/token_coins.py
```

into:

```text
~/.claude/token_coins.py
```

and merging the hook entries into:

```text
~/.claude/settings.json
```

The app listens on UDP loopback port `9876` for Claude notifications such as:

- `need attention`
- `user_prompt_submit`
- `claude task complete`
- `pre_tool_use`
- `post_tool_use`
- `coins:N`

This lets TachTone react when Claude needs review, completed a task, or emitted token-cost feedback.

---

## Development

### Build

```bash
make
```

### Install

```bash
./install.sh
```

### Clean build artifacts

```bash
make clean
```

---

## Project structure

```text
TachToneMac/
  App/
  Audio/
  Listeners/
  Pollers/
  State/
  UI/
TachToneMacTests/
hooks/
install.sh
Makefile
project.yml
```

---

## Stack

- Swift
- AppKit
- AVFoundation
- Network framework
- System monitoring via Apple APIs and Darwin accessors

---

## Notes

This project is a macOS adaptation of the same concept behind the Windows/Linux TachTone utility: turning system activity into a live audio feedback loop while staying lightweight and unobtrusive.

The Mac version is designed to run as a menu bar utility and to integrate with Claude Code without requiring a full dashboard or window to stay open.
