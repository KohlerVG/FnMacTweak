# 🎮 FnMacTweak

> **Play Fortnite on Mac the way it was meant to be played.**

FnMacTweak is a [Theos](https://theos.dev) tweak for **Fortnite iOS running on Apple Silicon Macs**. It bridges the gap between touch-only iOS input and a full PC/Console experience by synthesizing high-performance hardware inputs for the game engine.

---

## ✨ Features (v5.0.0)

| Feature | Description |
|---|---|
| 🖱️ **Raw HID Mouse Pipeline** | **New in v5.0.0.** Mouse input is read directly from hardware at your mouse's native polling rate, bypassing the OS event system entirely for the lowest possible latency. |
| 🎯 **Engine-Level Aim Hook** | **New in v5.0.0.** Camera aiming is injected directly into Unreal Engine's internal orientation function, with a sub-millisecond trajectory correction to compensate for OS input latency. |
| ⚡ **Auto 120 FPS** | **New in v5.0.0.** Automatically corrects `GameUserSettings.ini` to enforce 120 FPS every time Fortnite rewrites the file. No more manual ini edits. |
| 🛡️ **Stealth Suite** | **New in v5.0.0.** Full dyld image hiding, sysctl virtualization, and process introspection protection. |
| 🌍 **EU Marketplace Support** | **New in v5.0.0.** Bypasses Epic's EU marketplace eligibility checks. |
| 🎯 **Gyro-Mouse Proxy** | Zero-latency, demand-driven mouse synthesis via CoreMotion hooks. The smoothest aiming experience available. |
| 🎮 **Controller Mode** | Full physical controller support (Xbox, PS5, etc.) with hardware remapping, **Advanced Virtual Controller Remaps**, and sensible default bindings out of the box. |
| 🖱️ **GCMouseInput Toggle** | Instant cursor lock/unlock with a dedicated key bind (Default: `` ` ``). |
| ⌨️ **Typing Mode** | Press **Caps Lock** to instantly disable all keybinds and pass raw keyboard input to the game (for chat or searching). |
| ⌨️ **Universal Remapping** | Map any key or mouse button to any Fortnite action or controller button with near-zero overhead. |
| 🎨 **Graphics Unlocked** | Device spoofing for maximum graphics fidelity. |
| 🗂️ **Live Import/Export** | Customize everything in the `P` menu and export your entire setup to JSON for backup or sharing. |

---

## 🚀 Getting Started

### Requirements
- Apple Silicon Mac (M1 or later)
- Fortnite iOS installed (via Sideloadly or similar injection method)
- [Theos](https://theos.dev/docs/installation) (only if building from source)

### Installation
Download the latest `.deb` and inject it into your Fortnite IPA using Sideloadly (Advanced Options > Tweak Injection) or your preferred IPA patcher.

> **Note:** A welcome popup appears on first launch. Press **"Don't Show Again"** to dismiss it. It will return automatically when you upgrade to a new version.

### Building from Source
```bash
make package FINALPACKAGE=1
```
The resulting `.deb` will be in the `packages/` directory.

---

## ⌨️ Typing Mode (Caps Lock)

**Typing Mode** is designed for quick in-game communication without disrupting your setup.

- **How it works**: Press **Caps Lock** at any time to toggle Typing Mode.
- **When ON**: All custom keybinds and controller remappings are temporarily disabled. Your keyboard behaves like a standard keyboard, passing raw characters to the game.
- **Visual Feedback**: Syncs with your keyboard's hardware Caps Lock light.
- **Safety**: Caps Lock cannot be assigned to any other action in the settings menu, ensuring it is always available for typing.

---

## 🎯 The Gyro-Mouse System

FnMacTweak uses a **Demand-Driven Gyro Proxy** combined with a direct **Engine-Level Orientation Hook** for the lowest latency aiming possible.

Standard mouse input in iOS wrappers often suffers from jitter or "staircasing". FnMacTweak bypasses this by hooking the game's CoreMotion rotation requests and injecting synthesized velocity data precisely when the engine asks for it. In v5.0.0, this is further reinforced by a direct hook into Unreal Engine's internal orientation function.

- **Sensitivity Formula:** `(Base ÷ 100) × (Look% ÷ 100) × Scale × (Gyro Multiplier ÷ 100)`
- **Pixel Perfection:** Sub-pixel mouse deltas are preserved and consumed at the game's polling rate.
- **Scaling:** Match your exact PC DPI/Sensitivity feel using the `MACOS_TO_PC_SCALE` and `Gyro Multiplier` settings in the `P` menu.

---

## 🎮 Controller Mode & Virtual Remaps

FnMacTweak provides two powerful ways to use a controller:

1. **Hardware Mapping**: Map your physical controller's buttons to other controller inputs.
2. **Advanced Virtual Remaps**: Map keyboard keys or mouse buttons directly to controller inputs. This allows you to "spoof" a controller while using KBM, which can be useful for specific game configurations or accessibility.

Both systems come with **sensible default bindings out of the box** and operate with instant, immediate saving — no "Apply" step required.

---

## ⌨️ Input Customization

Press **`P`** (default) in-game to open the settings panel.

- **Sensitivity Tab**: Adjust mouse look speed, gyro multipliers, and the GCMouseInput Toggle key.
- **Keyboard Tab**: Traditional keyboard-to-game mappings (Movement, Building, etc.).
- **Controller Tab**: Manage physical controller mappings and virtual controller overrides.
- **Container Tab**: Grant the tweak access to Fortnite's data folder for advanced features.
- **Quick Start Tab**: Tutorials and setup guides.

---

## 🖱️ Cursor Management

| Action | Mapping | Description |
|---|---|---|
| 🔒 **Toggle Lock/Unlock** | Press **L** | Toggles between FPS mouse look and free cursor. |
| 🎯 **Teleport to Blue Dot** | Hold **Option (⌥)** | Temporarily unlocks and warps the cursor to the "Blue Dot" center (for building/menus). Releasing Option relocks the mouse and warps it back to the center of the screen. |

- **Blue Dot Position**: When the `P` settings panel is open, a blue dot indicator appears. Drag it to your desired position to set the teleport target.
- The **GCMouseInput Toggle** (default: `` ` ``) is a separate dedicated key for direct in-game action passthrough.
- The settings panel automatically releases the mouse cursor when opened.

---

## 🗂️ Project Structure

```
FnMacTweak/
├── src/
│   ├── Tweak.xm              # Hook entry point (CGEventTap & HID lifecycle)
│   ├── globals.h/m           # Global state, persistence, and suite management
│   ├── ue_reflection.h/m     # Engine-level aim hook & Gyro-Mouse synthesis
│   ├── PerformanceGuard.h/m  # Process performance and scheduling management
│   ├── FnOverlayWindow.h/m   # Custom overlay for Blue Dot & UI rendering
│   └── views/                # UI Components (Settings Popup, Welcome Screen)
├── tools/
│   └── ldid                  # codesign shim for reliable build signing
├── Makefile                  # Build configuration (Theos)
└── control                   # Package metadata
```

---

## 🏆 Credits

- **[@kohlervg](https://github.com/KohlerVG)** — v4.0.0 / v5.0.0 Architect: Raw HID Pipeline, Engine Aim Hook, Stealth Suite, UI Overhaul.
- **[@rt2746](https://github.com/rt2746)** — Original Author.
- **[Majkel]** — Special thanks for the virtual controller implementation idea!

---

## ⚖️ License

See [LICENSE](LICENSE) for details. Use at your own risk.
