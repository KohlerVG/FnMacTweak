# 🎮 FnMacTweak

> **Play Fortnite on Mac the way it was meant to be played.**

FnMacTweak is a [Theos](https://theos.dev) tweak for **Fortnite iOS running on Apple Silicon Macs**. It bridges the gap between touch-only iOS input and a full PC/Console experience by synthesizing high-performance hardware inputs for the game engine.

---

## ✨ Features (v5.0.0)

| Feature | Description |
|---|---|
| 🖱️ **Raw HID Mouse Pipeline** | **New in v5.0.0.** Mouse input is read directly from hardware at your mouse's native polling rate, bypassing the OS event system entirely for the lowest possible latency. |
| 🎯 **Mouse Motion Compatibility** | Mouse aiming uses the gyro proxy only while virtual mouse input is active; native physical-controller motion passes through. |
| ⚡ **Auto 120 FPS** | **New in v5.0.0.** Automatically corrects `GameUserSettings.ini` to enforce 120 FPS every time Fortnite rewrites the file. No more manual ini edits. |
| 🛡️ **Stealth Suite** | **New in v5.0.0.** Full dyld image hiding, sysctl virtualization, and process introspection protection. |
| 🌍 **EU Marketplace Support** | **New in v5.0.0.** Bypasses Epic's EU marketplace eligibility checks. |
| 🎯 **Gyro-Mouse Proxy** | Zero-latency, demand-driven mouse synthesis via CoreMotion hooks. The smoothest aiming experience available. |
| 🎮 **Controller Mode** | Native physical controller input with Auto/On/Off virtual-controller modes, keyboard/mouse-to-controller mappings, and **Advanced Virtual Controller Remaps**. |
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

FnMacTweak uses a **Demand-Driven Gyro Proxy** for mouse aiming while the virtual controller is ready and mouse aiming is active.

The proxy answers eligible motion requests with synthesized mouse velocity. Physical controller motion retains its original implementation. The previous unscoped Unreal orientation interposition is disabled.

- **Sensitivity Formula:** `(Base ÷ 100) × (Look% ÷ 100) × Scale × (Gyro Multiplier ÷ 100)`
- **Pixel Perfection:** Sub-pixel mouse deltas are preserved and consumed at the game's polling rate.
- **Scaling:** Match your exact PC DPI/Sensitivity feel using the `MACOS_TO_PC_SCALE` and `Gyro Multiplier` settings in the `P` menu.

---

## 🎮 Controller Mode & Virtual Remaps

The **Controller** tab has a **Virtual Controller** selector that saves immediately:

- **Auto** (default): use Fortnite’s native physical controller input when another controller is connected; reconnect the virtual controller when the last physical controller disconnects.
- **On**: keep the virtual controller connected, including alongside physical controllers. Fortnite may still choose between devices.
- **Off**: disconnect the virtual controller and stop controller-related keyboard/mouse suppression.

The status below the selector shows connection readiness or an error. Physical controller buttons, sticks, and gyro retain native input. Synthetic input and cleanup only target the tweak’s own virtual device.

The mapping rows bind keyboard keys or mouse buttons to virtual controller inputs. Advanced Virtual Remaps provide additional source-to-controller bindings; these do not remap physical controller hardware. Mapping rows use **Apply Changes**, while advanced virtual remaps save immediately. Saved mappings remain available when virtual input is disabled. Older imported backups default to Auto.

For physical controllers, use Auto and connect over Bluetooth or USB before launch or in the lobby. No controller power cycle should be needed; runtime compatibility still depends on Fortnite’s device handling.

---

## ⌨️ Input Customization

Press **`P`** (default) in-game to open the settings panel.

- **Sensitivity Tab**: Adjust mouse look speed, gyro multipliers, and the GCMouseInput Toggle key.
- **Keyboard Tab**: Traditional keyboard-to-game mappings (Movement, Building, etc.).
- **Controller Tab**: Choose Auto/On/Off and manage keyboard/mouse-to-controller mappings.
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
