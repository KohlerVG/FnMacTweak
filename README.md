# 🎮 FnMacTweak

> **Play Fortnite on Mac the way it was meant to be played.**

FnMacTweak is a [Theos](https://theos.dev) tweak for **Fortnite iOS running on Apple Silicon Macs via Sideloadly**. It bridges the gap between touch-only iOS input and a full keyboard + mouse experience — giving you PC-accurate sensitivity, 120 FPS, proper mouse lock, and remappable controls, all without touching Fortnite's files.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🖱️ **FPS Cursor Lock** | Lock/Unlock with **L⌥ + Left Click** for perfect FPS aiming. |
| ⚡ **120 FPS** | Play at up to 120 FPS on supported ProMotion screens. |
| 🎨 **High Graphics** | Unlock High and Epic graphics settings usually hidden on mobile. |
| 🎯 **Zero-Lag Input** | Perfectly smooth mouse movement and instant responsiveness. |
| 🏗️ **Build Mode** | Build and aim easily using a special draggable crosshair. |
| 🎮 **Pro Controllers** | Use your favorite console controller with zero extra lag. |
| 🗂️ **Live Settings** | Press `P` in-game to customize everything on the fly. |

---

## 🚀 Getting Started

### Requirements
- Apple Silicon Mac (M1 or later)
- Fortnite iOS installed via **Sideloadly**
- [Theos](https://theos.dev/docs/installation) (to build from source)

### Installation (Pre-built)
Download the latest `.deb` from the [Releases](https://github.com/KohlerVG/FnMacTweak/releases/) page and install it through Sideloadly in Advanced Options > Tweak Injection.

> **Welcome screen:** A welcome popup appears on first launch. Press **"Don't Show Again"** to dismiss it permanently for that version. It automatically re-appears whenever you install a new version, so you never miss what's changed.

### Building from Source
```bash
git clone https://github.com/KohlerVG/FnMacTweak.git
cd FnMacTweak
make package FINALPACKAGE=1
```
Requires Theos to be installed and `$THEOS` set in your environment.

---

## 🖱️ Mouse Lock

Mouse locking uses a single deliberate gesture for both lock and unlock:

| Action | Gesture |
|---|---|
| 🔒 **Lock** | Hold **L⌥** → **Left Click** |
| 🔓 **Unlock** | Hold **L⌥** → **Left Click** |

- Only the **first** left click per Option hold counts — extra clicks while Option is held are ignored.
- The lock click is fully suppressed — it will **not** fire a shot, place a build, or interact with the UI.
- Any active UI touches are cleared the moment Left Option is pressed, preventing stuck inputs.
- The `P` key always force-unlocks the mouse when opening the settings panel.

---

## 🎯 Sensitivity System

FnMacTweak replicates the **exact nested sensitivity formula** used by PC Fortnite:

```
effective = (Base ÷ 100) × (Look% ÷ 100) × Scale
```

| Setting | Default | What it does |
|---|---|---|
| `BASE_XY_SENSITIVITY` | 6.4 | Matches Fortnite's X/Y-Axis base sensitivity |
| `LOOK_SENSITIVITY_X/Y` | 50% | Hip-fire horizontal / vertical |
| `SCOPE_SENSITIVITY_X/Y` | 50% | ADS horizontal / vertical |
| `MACOS_TO_PC_SCALE` | 20.0 | Converts macOS mouse delta to PC units |

Sensitivities are **pre-calculated once at startup** and cached — no per-frame math overhead. Sub-pixel movements are accumulated and never lost.

Press `P` in-game → **Sensitivity** tab to adjust these live.

---

## ⌨️ Key Remapping

Two independent remapping layers stack on top of each other:

1. **Fortnite Keybinds** — Remaps game actions (Forward, Reload, Build…) to your preferred keys.
2. **Advanced Custom Remaps** — Raw key-to-key overrides that take priority over everything else.

Both layers use **direct array lookups** (indexed by `GCKeyCode`) for ~2ns overhead per keypress — effectively zero latency.

Press `P` → **Key Remap** tab to configure.

---

## 🏗️ Build Mode

Build Mode lets you use mouse clicks to build and edit just like on PC:

- **Right-Click (Hold)**: Aim down sights normally.
- **Left-Click**: Places builds or selects edits wherever the **Red Dot Crosshair** is placed.
- **Draggable Crosshair**: Open the `P` settings panel while Build Mode is on — the red dot appears on screen. Drag it to align with your crosshair. Position is saved automatically.

Toggle Build Mode in the **P** menu → **Build Mode** tab.

---

## 🗂️ Project Structure

```
FnMacTweak/
├── src/
│   ├── Tweak.xm                   # Entry point: all %hook patches + constructor
│   ├── globals.h                  # Shared constants, extern declarations, inline helpers
│   ├── globals.m                  # Global variable definitions + utility functions
│   └── views/
│       ├── popupViewController.h  # Settings popup public interface + tab enum
│       ├── popupViewController.m  # Full settings UI (sensitivity, keybinds, build mode, container, quick start)
│       ├── welcomeViewController.h # Welcome screen public interface
│       └── welcomeViewController.m # First-launch welcome screen (shown once per version)
├── lib/
│   └── fishhook.{h,c}             # Facebook's fishhook — used for sysctl device spoofing
├── Makefile                       # Theos build config
├── control                        # Debian package metadata (single source of truth for version)
└── FnMacTweak.plist               # Theos injection filter (targets Fortnite bundle)
```

---

## 🤝 Contributing

Contributions are welcome! Here's how to get oriented:

- **`Tweak.xm`** is where all the Theos `%hook` patches live. If you're changing how input is intercepted or adding a new game hook, start here.
- **`globals.h/.m`** holds all shared state. Add new settings constants here and declare them `extern` so every file can access them.
- **`popupViewController.m`** is the settings UI. Each tab is a self-contained `UIView` built in code — no Xib/Storyboard.
- **`welcomeViewController.m`** handles the first-launch welcome popup — shown once per version install.

When submitting a PR, please:
1. Keep hooks focused — one concern per `%hook` block.
2. Update `CHANGELOG.md` with a short description of your change.
3. Test with both Zero Build and Build Mode enabled.

---

## 📋 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full version history and technical breakdown of every change.

---

## 🏆 Credits

- **[@kohlervg](https://github.com/KohlerVG)** — Project Overhaul: Re-engineered the sensitivity system, keymapping, build mode, import/export, zero-lag optimizations, cursor lock system, and custom PiP.
- **[@rt2746](https://github.com/rt2746)** — Original Author: Creator of the initial [FnMacTweak](https://github.com/rt-someone/FnMacTweak) repository.
- **[Facebook fishhook](https://github.com/facebook/fishhook)** — Used for `sysctl` hooking in a jailed environment.
- **[PlayCover / PlayTools](https://github.com/PlayCover/PlayTools)** — Inspiration for device model spoofing.

---

## ⚖️ License

See [LICENSE](LICENSE) for details.

> **Disclaimer:** This project is not affiliated with or endorsed by Epic Games. Use at your own risk.
