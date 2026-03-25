# 🎮 FnMacTweak

> **Play Fortnite on Mac the way it was meant to be played.**

FnMacTweak is a [Theos](https://theos.dev) tweak for **Fortnite iOS running on Apple Silicon Macs**. It bridges the gap between touch-only iOS input and a full PC/Console experience by synthesizing high-performance hardware inputs for the game engine.

---

## ✨ Features (v4.0.0)

| Feature | Description |
|---|---|
| 🎯 **Gyro-Mouse Proxy** | **New in v4.0.0.** Zero-latency, demand-driven mouse synthesis via CoreMotion hooks. The smoothest aiming experience available. |
| 🎮 **Controller Mode** | **New in v4.0.0.** Full physical controller support (Xbox, PS5, etc.) with hardware remapping and **Advanced Virtual Controller Remaps**. |
| 🖱️ **GCMouseInput Toggle** | **New in v4.0.0.** Instant cursor lock/unlock with a dedicated key bind (Default: `` ` ``). |
| ⌨️ **Typing Mode** | **New in v4.0.0.** Press **Caps Lock** to instantly disable all keybinds and pass raw keyboard input to the game (for chat or searching). |
| ⌨️ **Universal Remapping** | **New in v4.0.0.** Map any key or mouse button to any Fortnite action or controller button with ~2ns overhead. |
| ⚡ **120 FPS & ProMotion** | Play at native high refresh rates on supported Apple Silicon displays. |
| 🎨 **Graphics Unlocked** | Force High/Epic graphics settings and device spoofing for maximum fidelity. |
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

**Typing Mode** is a first-class feature in v4.0.0 designed for quick communication. 

- **How it works**: Press **Caps Lock** at any time to toggle Typing Mode.
- **When ON**: All custom keybinds and controller remappings are temporarily disabled. Your keyboard behaves like a standard keyboard, passing raw characters to the game.
- **Visual Feedback**: Syncs with your keyboard's hardware Caps Lock light.
- **Safety**: Caps Lock cannot be assigned to any other action in the settings menu, ensuring it is always available for typing.

---

## 🎯 The Gyro-Mouse System

In v4.0.0, FnMacTweak moved away from traditional delta accumulation in favor of a **Demand-Driven Gyro Proxy**. 

Standard mouse input in iOS wrappers often suffers from jitter or "staircasing". FnMacTweak bypasses this by hooking the game's CoreMotion rotation requests and injecting synthesized velocity data precisely when the engine asks for it.

- **Sensitivity Formula:** `(Base ÷ 100) × (Look% ÷ 100) × Scale × (Gyro Multiplier ÷ 100)`
- **Pixel Perfection:** Sub-pixel mouse deltas are preserved and consumed at the game's polling rate.
- **Scaling:** Match your exact PC DPI/Sensitivity feel using the `MACOS_TO_PC_SCALE` and `Gyro Multiplier` settings in the `P` menu.

---

## 🎮 Controller Mode & Virtual Remaps

FnMacTweak provides two powerful ways to use a controller:

1. **Hardware Mapping**: Map your physical controller's buttons to other controller inputs.
2. **Advanced Virtual Remaps**: Map Keyboard keys or Mouse buttons directly to Controller inputs. This allows you to "spoof" a controller while using KBM, which can be useful for specific game configurations or accessibility.

Both systems operate with instant, immediate saving — no "Apply" step required for controller changes.

---

## ⌨️ Input Customization

Press **`P`** (default) in-game to open the settings panel.

- **Sensitivity Tab**: Adjust mouse look speed, gyro multipliers, and the GCMouseInput Toggle key.
- **Keyboard Tab**: Traditional keyboard-to-game mappings (Movement, Building, etc.).
- **Controller Tab**: Manage physical controller mappings and virtual controller overrides.
- **Advanced Tab**: Manage global Import/Export and experimental features.

---

## 🖱️ Cursor Management

| Action | Mapping | Description |
|---|---|---|
| 🔒 **Toggle Lock/Unlock** | Press **L** | Toggles between FPS mouse look and free cursor. |
| 🎯 **Teleport to Blue Dot** | Hold **Option (⌥)** | Temporarily unlocks and warps the cursor to the "Blue Dot" center (for building/menus). Releasing Option relocks the mouse and warps it back to the center of the screen. |

- **Blue Dot Position**: When usage of the `P` setup panel is active, a blue dot circle indicator appears. Drag it to your desired position to set the "Blue Dot" teleport target.
- The **GCMouseInput Toggle** (default: `` ` ``) is a separate dedicated key for direct in-game action passthrough.
- The settings panel automatically releases the mouse cursor when opened.

---

## 🗂️ Project Structure

```
FnMacTweak/
├── src/
│   ├── Tweak.xm           # Hook entry point (CGEventTap & HID lifecycle)
│   ├── globals.h/m        # Global state, persistence, and suite management
│   ├── ue_reflection.h/m  # CoreMotion / Gyro-Mouse synthesis logic
│   ├── FnOverlayWindow.h/m# Custom overlay for Blue Dot & UI rendering
│   └── views/             # UI Components (Settings Popup, Welcome Screen)
├── Makefile               # Build configuration (Theos)
└── control                # Package metadata
```

---

## 🏆 Credits

- **[@kohlervg](https://github.com/KohlerVG)** — v4.0.0 Architect: Gyro-Mouse Proxy, Controller Mode, UI Overhaul.
- **[@rt2746](https://github.com/rt2746)** — Original Author.
- **[Majkel]** — Special thanks for the virtual controller implementation idea!

---

## ⚖️ License

See [LICENSE](LICENSE) for details. Use at your own risk.
