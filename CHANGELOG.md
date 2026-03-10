# 📋 Changelog

All notable changes to FnMacTweak are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [3.0.0] — March 2026

### ✨ Added
- **Unified Lock / Unlock Cursor card** — The welcome screen and Quick Start guide now show a single combined card instead of two separate Lock / Unlock cards. Keybind displayed as `L⌥ + Click` with updated description: *"Hold Left Option and click to lock or unlock your mouse cursor to the game window."*

### 🔄 Changed
- **Lock / Unlock gesture redesigned** — Mouse lock and unlock now both require `L Option + Left Click`. A bare Left Option tap no longer does anything. This prevents accidental lock/unlock mid-game and makes the gesture intentional and consistent in both directions.
- **One gesture per Option hold** — Lock or unlock fires only on the first left click per Option hold. Any additional clicks while Option is still held are ignored, preventing accidental re-lock immediately after unlocking.

### 🐛 Fixed
- **Scroll keybind fallback** — When scroll up/down was mapped to a Fortnite default keybind (e.g. USE → E), the remap was silently ignored because `mouseScrollRemapArray` was only populated by advanced remaps. Fortnite default keybinds now populate a separate `mouseScrollFortniteArray` and are checked as a fallback when no advanced remap is set.
- **Raw scroll bleed-through** — GCKit's scroll pad handler fired independently even when a keybind was consuming the scroll event, causing weapon-switch scroll to bleed through alongside the key press. The GCKit pad handler is now wrapped and suppressed whenever any scroll binding is active.
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
