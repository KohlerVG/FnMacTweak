# 📋 Changelog

All notable changes to FnMacTweak are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [4.0.0] — March 2026

### ✨ Added
- **Typing Mode (Caps Lock)** — Press **Caps Lock** to toggle raw keyboard input. Disables all tweak-specific keybinds and passes raw characters to the game. Syncs with the keyboard's hardware light.
- **Gyro-Mouse Proxy** — Zero-latency, demand-driven mouse synthesis via CoreMotion hooks for the smoothest aiming experience.
- **Controller Mode** — Full physical controller support (Xbox, PS5, etc.) with hardware remapping.
- **Advanced Virtual Controller Remaps** — Map any Keyboard/Mouse input directly to a Controller button button (e.g., Space to Jump).
- **GCMouseInput Toggle** — Dedicated key (default: `` ` ``) for instant cursor lock/unlock and passthrough.
- **Settings Import/Export** — Fully robust JSON backup/restore for all settings, including Controller and Virtual remaps.
- **Welcome UI Improvements** — Added Typing Mode info card and refined border aesthetics to match the main settings pane.

### 🔄 Changed
- **Cursor Management** — Updated to modern standards: **L** key to toggle lock/unlock, **Option (⌥)** to temporarily warp cursor to the Blue Dot.
- **Blue Dot System** — Draggable crosshair target for rapid cursor teleports during building or menu navigation.
- **Project Structure** — Organized `src/` directory with clear separation between Tweak hooks, Gyro synthesis, and UI views.

### 🗑️ Removed
- **Obsolete "Build Mode"** — Legacy build mode and zero-build logic/comments have been purged.
- **Obsolete "Red Dot"** — Removed in favor of the more flexible Blue Dot crosshair system.

### 🐛 Fixed
- **Settings Persistence** — Corrected `NSUserDefaults` suite management for controller settings, ensuring they persist and export correctly.
- **Rebind Dialog Interference** — Implemented a "1-click pass through" workaround for all capture prompts, preventing accidental bindings when clicking UI buttons.
- **Backtick (`) Key Support** — Fully unified keycode 53 (Backtick) across the UI, reset logic, and migration paths.
- **Controller Latency** — Optimized input synthesis to zero-latency element-based handling.

## [3.0.0] — March 2026

### ✨ Added
- **Borderless fullscreen mode** — Play without the macOS title bar. The window fills the screen edge-to-edge using `visibleFrame` for correct centering below the menu bar, with the title bar and traffic lights hidden automatically.
- **Significantly smoother mouse movement** — Replaced the sub-pixel accumulation method with `roundf` + carry remainder, eliminating burst lag caused by integer truncation. Movement is now evenly distributed every frame with zero input loss, especially noticeable at lower sensitivities.
- **Mouse button support** — Middle click and all auxiliary mouse buttons are now fully remappable just like keyboard keys, via the Key Remap tab.
- **Discrete scroll wheel remapping** — Scroll up and scroll down can be mapped to any key or Fortnite action (e.g. weapon switch, USE, build select). Works as a true per-tick keypress with no bleed-through.
- **Unified Lock / Unlock Cursor card** — The welcome screen and Quick Start guide now show a single combined card instead of two separate Lock / Unlock cards. Keybind displayed as `L⌥ + Click` with updated description: *"Hold Left Option and click to lock or unlock your mouse cursor to the game window."*
- **Version pill** — Both the P settings pane and the Welcome popup now show a `v3.0.0` pill in the title bar.

### 🔄 Changed
- **Lock / Unlock gesture redesigned** — Mouse lock and unlock now both require `L Option + Left Click`. A bare Left Option tap no longer does anything. This prevents accidental lock/unlock mid-game and makes the gesture intentional and consistent in both directions.
- **One gesture per Option hold** — Lock or unlock fires only on the first left click per Option hold. Any additional clicks while Option is still held are ignored, preventing accidental re-lock immediately after unlocking.

### 🐛 Fixed
- **Scroll keybind fallback** — When scroll up/down was mapped to a Fortnite default keybind (e.g. USE → E), the remap was silently ignored because `mouseScrollRemapArray` was only populated by advanced remaps. Fortnite default keybinds now populate a separate `mouseScrollFortniteArray` and are checked as a fallback when no advanced remap is set.
- **Raw scroll bleed-through when keybind mapped** — When a scroll direction had a keybind assigned, the hardware scroll event was still passed through to GCKit if the mouse was unlocked. The NSEvent monitor now always consumes the event when a keybind is mapped, regardless of lock state — the keypress only fires when the mouse is locked.
- **Raw scroll bleed-through via GCKit wrapped handler** — GCKit could fire scroll directly to the game while the mouse was unlocked. The wrapped handler now checks `isMouseLocked` and suppresses all scroll when unlocked.
- **Opposite scroll direction blocked when one direction bound** — Previously if scroll-down was bound to a key, scroll-up was also blocked from reaching the game as weapon switch. Suppression is now per-direction — each direction is checked independently.
- **Scroll blocked inside P settings panel** — When the settings panel was open, scroll was consumed even though the mouse was unlocked and the user needed to scroll the panel. Scroll now passes through freely when `isPopupVisible` is true.
- **Build mode stuck gun** — When right-click was pressed while left was held in build mode, the code called `leftButtonGameHandler` (the custom wrapper) to send the GC press. The wrapper re-entered with stale state and never forwarded the press to the game. The right button handler now calls `leftButtonRawHandler` directly, bypassing the wrapper entirely.
- **Stuck left click when locking with a click already in flight** — The lock path now clears click state and sends a matched GC release if a GC press was outstanding, preventing a stuck press with no release path.
- **Spurious GC release without prior press** — Both lock and unlock paths now guard the GC release on `leftClickSentToGame` (GC press actually sent) rather than `leftButtonIsPressed` alone, preventing unmatched releases that corrupt the game's input state.
- **Non-build mode spurious GC release after lock** — Left button release in non-build mode now only calls `handler()` if `leftClickSentToGame` was `YES`, matching the build mode behaviour.
- **Stuck UITouch when Left Option pressed mid-click** — `_cancelAllTouches` is now called synchronously the moment Left Option is pressed, before `isTriggerHeld` is set, nuking any in-flight UITouch before the type hook changes behaviour.
- **Stuck left click on release while Option held** — The `isTriggerHeld` block now always clears `leftButtonIsPressed` and `leftClickSentToGame` on release and sends a matched GC release if one is needed, instead of silently returning.
- **Re-lock after unlock while Option still held** — `lockClickConsumed` is now set to `YES` on unlock so further clicks while Option is held are blocked until it is released.
- **Unlocked UITouch stuck when locking quickly** — `_cancelAllTouches` now fires unconditionally on every lock rather than only when `leftButtonIsPressed` is set, covering in-flight touches from when the cursor was unlocked.

### ⚡ Performance
- **Eliminated per-event `NSInvocation` alloc on scroll** — `NSSelectorFromString(@"scrollingDeltaY")` and `NSInvocation` were allocated on every scroll event. The SEL is now cached statically once and the call uses a direct `objc_msgSend` cast — zero alloc per scroll tick.
- **Per-direction scroll check** — Scroll suppression now uses a single direct array lookup on `idx` instead of looping over all scroll directions — O(1), zero overhead.

---

## [2.0.4] — March 2026

### 🐛 Fixed
- **Mouse movement stuttering / burst lag** — Sub-pixel accumulation was using `int` truncation which rounds toward zero, causing small movements to build up and release in bursts. Replaced with `roundf` + carry remainder for smooth, even distribution.
- **BUILD mode stuck fire (ADS race condition)** — `leftClickSentToGame` was set inside a `dispatch_async` block. If the player released left-click before the block executed, the release handler skipped the GC button-up, leaving fire stuck. Flag is now set synchronously.
- **BUILD mode stuck fire (ADS release)** — Releasing right-click while holding left-click left the GC press with no release path. Right-click release now explicitly sends the GC release and resets state.
- **Sensitivity not applied at launch** — `recalculateSensitivities()` was called before settings were loaded from `NSUserDefaults`. Saved values now load first.

### ⚡ Performance
- **Eliminated 120Hz heap allocation** — `lastMousePosition` update block (never read) removed entirely.
- **Cached `keyWindow` reference** — `connectedScenes → keyWindow` lookups now use a static cached reference, invalidated on lock state change.
- **`GCMouse.handlerQueue` set only once** — A static dirty flag ensures it is set exactly once instead of on every `.mouseInput` access.

### 🗑️ Removed
- `keyboardChangedHandler` global — never assigned or read
- `isAlreadyFocused` global — only ever written to, never read
- `saveFortniteKeybinds()` — never called; body was just `loadFortniteKeybinds()`

---

## [2.0.3] — March 2026

### 🐛 Fixed
- **Crash on macOS Sequoia** — `setScrollValueChangedHandler:` is Tahoe-only. Scroll handling now uses `setValueChangedHandler:` on `GCControllerDirectionPad` with a runtime guard for compatibility with both Sequoia and Tahoe.

---

## [2.0.2] — February 2026

### ✨ Added
- **Resizable Quick Start video popup** — Draggable, resizable from any edge/corner, 16:9 locked, 400×225 minimum.
- **Shadow wrapper** — Drop shadow outside rounded-rect bounds on the video popup.
- **Pass-through overlay** — Touches outside the video popup fall through to the game.

### 🗑️ Removed
- **`postinst` script** — Version detection is now self-contained in `%ctor`.

### 🐛 Fixed
- **Quick Start video not loading** — `AVPlayer` was sometimes called before the player item was attached.

---

## [2.0.1] — February 2026

### 🐛 Fixed
- **Stuck left-click (UITouch & GC paths)** — `leftClickSentToGame` race condition in Build Mode; now set atomically inside the `dispatch_async` block.
- **"Don't Show Again" not persisting** — Added a separate `fnmactweak.welcomeSuppressed` key never cleared by the version gate.
- **Welcome popup never reshowing on version bump** — `postinst` was writing to the wrong NSUserDefaults domain.

---

## [2.0.0] — February 2026

### ✨ Added
- FPS Cursor Lock, fractional accumulation, PC Fortnite formula match, pre-calculated sensitivity cache, two-tier key remapping, Build Mode, red dot crosshair, Quick Start tab, settings import/export, Apply Defaults button, -O3 optimisation.

### 🐛 Fixed
- Camera snap on ADS toggle, stuck left-click in Build Mode, blurry Retina UI, gamepad pass-through logic error.

---

## [1.0.0] — Initial Release

- Mouse pointer lock toggle, 120 FPS unlock, graphics preset unlock, basic sensitivity, settings popup, touch interaction fix, fishhook integration.
