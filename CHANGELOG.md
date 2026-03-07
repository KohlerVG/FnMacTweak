# 📋 Changelog

All notable changes to FnMacTweak are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.0.4] — March 2026

### 🐛 Fixed
- **Mouse movement stuttering / burst lag** — Sub-pixel accumulation was using `int` truncation (`(int)mouseAccumX`) which always rounds toward zero, causing small movements to build up and release in sudden bursts. Replaced with `roundf` + carry remainder, which distributes movement evenly and eliminates the burst pattern. Mouse feel is now significantly smoother especially at lower sensitivities.
- **BUILD mode stuck fire (ADS race condition)** — When holding left-click (UITouch) and pressing right-click to ADS, `leftClickSentToGame` was being set inside a `dispatch_async` block. If the player released left-click before that block executed, the release handler saw `leftClickSentToGame=NO` and skipped sending the GC button-up, leaving the fire input permanently stuck in the game. Flag is now set synchronously before the async dispatch.
- **BUILD mode stuck fire (ADS release)** — When releasing right-click (ADS) while still holding left-click, the left button remained registered as a GC press in the game with no release path, since the left button handler only sends a GC release on physical left-click release. Right-click release now explicitly sends the GC release and resets state so left-click re-enters the UITouch path cleanly.
- **Sensitivity not applied at launch** — `recalculateSensitivities()` was called in `%ctor` before any settings were loaded from `NSUserDefaults`, so it always computed from hardcoded defaults. Saved sensitivity values only took effect after opening the P menu. Settings are now loaded from `NSUserDefaults` before `recalculateSensitivities()` in `%ctor`.

### ⚡ Performance
- **Eliminated 120Hz heap allocation** — `lastMousePosition` was being updated on every mouse move event using a `connectedScenes` lookup (which allocates an `NSSet` internally). The variable was never read anywhere in the codebase. Entire block removed.
- **Cached `keyWindow` reference** — `connectedScenes → keyWindow` lookups in the UITouch hooks and BUILD mode left button handler now use a static cached reference instead of re-resolving on every touch event. Cache is invalidated on lock state change.
- **`GCMouse.handlerQueue` set only once** — The `%hook GCMouse - mouseInput` was setting `handlerQueue` on every access to `.mouseInput`. A static dirty flag now ensures it is set exactly once.

### 🗑️ Removed
- `keyboardChangedHandler` global — declared and exported but never assigned or read anywhere
- `isAlreadyFocused` global — only ever written to (`= NO`), never read in any conditional
- `saveFortniteKeybinds()` — declared, defined, and exported but never called; body was just `loadFortniteKeybinds()`

---

## [2.0.3] — March 2026

### 🐛 Fixed
- **Crash on macOS Sequoia** — `setScrollValueChangedHandler:` on `GCMouseInput` is a Tahoe-only API and does not exist on Sequoia (macOS 15), causing an instant crash on launch. Scroll wheel handling is now hooked via `setValueChangedHandler:` on `GCControllerDirectionPad` with a `respondsToSelector:` runtime guard to safely identify the scroll pad on both Sequoia and Tahoe.

---

## [2.0.2] — February 2026

### ✨ Added
- **Resizable Quick Start video popup** — The tutorial video window can now be dragged anywhere on screen and resized from any edge or corner. Aspect ratio is locked to 16:9 during resize with a 400×225 minimum size. Correct macOS resize cursors appear on hover for each edge and corner.
- **Shadow wrapper** — The video popup now renders a drop shadow outside its rounded-rect bounds for a polished floating appearance.
- **Pass-through overlay** — Touches outside the video popup fall through to the game so Fortnite remains fully interactive while the video is open.

### 🗑️ Removed
- **`postinst` script** — Removed entirely. Version detection is now self-contained in `%ctor` — the current version is hardcoded directly in `Tweak.xm` and written to `fnmactweak.lastSeenVersion` at runtime. No post-install script needed.

### 🐛 Fixed
- **Quick Start video not loading** — The video popup now reliably loads and plays on first open. Previously, `AVPlayer` was sometimes called before the player item was attached, causing a permanently stalled state with no recovery path.

## [2.0.1] — February 2026

### 🐛 Fixed
- **Stuck left-click (UITouch & GC paths)** — Fixed a race condition in Build Mode where `leftClickSentToGame` was set to `YES` before the async GC press event fired. If the user released left-click during that window, the release handler would dispatch a GC button-up to the game before the GC press had landed, leaving the game with a stuck input. `leftClickSentToGame` is now set atomically inside the `dispatch_async` block, immediately after the GC press is sent, eliminating the race.
- **"Don't Show Again" not persisting** — The welcome popup ignored the suppression preference on every launch. The `%ctor` version-gate was clearing `kWelcomeSeenVersion` on each update, wiping the flag. Added a separate `fnmactweak.welcomeSuppressed` key that is written by "Don't Show Again" and is intentionally never cleared by the version gate, so the preference survives updates permanently.
- **Welcome popup never reshowing on version bump** — `postinst` was writing `fnmactweak.version` to `com.epicgames.fortnite` (wrong domain), so the key was never readable at runtime. `currentVersion` always fell back to the hardcoded `"2.0.0"`, meaning `kWelcomeSeenVersion` always matched and the popup never reshowed after updates. Fixed by writing to the correct domains (`com.epicgames.FortniteGame.57R7T7Q6F9` and `com.epicgames.FortniteGame.FC2QCLNL95`).

---

## [2.0.0] — February 2026

### ✨ Added
- **FPS Cursor Lock** — `L⌥ + Left Click` locks the mouse for FPS aiming; `L⌥` alone unlocks. The lock-click is fully suppressed and will not fire a shot, place a build, or interact with the UI.
- **Lock Cursor hint on Welcome screen** — Info box on the first-launch welcome popup showing the `L⌥ + Click` keybind with styled key badges.
- **Fractional accumulation** — Sub-pixel mouse deltas are accumulated across frames. Previously any `deltaX × sensitivity < 1.0` was silently dropped; now zero input is ever lost.
- **PC Fortnite formula match** — Sensitivity uses the exact `(Base ÷ 100) × (% ÷ 100) × Scale` chain that PC Fortnite uses. All six parameters are tunable.
- **Pre-calculated sensitivity cache** — `hipSensitivityX/Y` and `adsSensitivityX/Y` are computed once at startup and on settings save. The mouse handler does a single multiply per axis instead of 2–3 divisions + a multiply.
- **Two-tier key remapping system** — Fortnite Action Keybinds (game-action → default key) and Advanced Custom Remaps (raw key → key) operate as independent layers with defined priority ordering. Both use direct array lookups (~2 ns per keypress).
- **Build Mode** — Dedicated mode for build-and-aim play. Right-click toggles ADS (GameController); left-click sends a UITouch at the draggable red dot crosshair position.
- **Red dot crosshair** — Draggable on-screen indicator showing where left-click lands in Build Mode. Appears immediately when the settings panel opens. Position saved to NSUserDefaults between sessions.
- **Quick Start tab** — In-app tutorial video presented in a custom liquid glass player with skip ±5 s, scrubber, and replay.
- **Settings import / export** — Export all settings to a JSON file and import them on another device via the Container tab.
- **Apply Defaults button** — One-click reset to recommended sensitivity values (Base 6.4, Look/Scope 50%, Scale 20).
- **Version gate** — On update, Advanced Custom Remaps are cleared automatically to prevent stale key code conflicts. Fortnite keybinds are preserved.
- **-O3 Compiler Optimization** — Highest level of compiler optimization enabled in the Makefile for maximum runtime speed.
- **Diagnostic Log Stripping** — All per-event logging is wrapped in `FTLog` and compiled out in release builds, eliminating diagnostic overhead.

### 🔄 Changed
- **Targeted pointer-lock broadcaster** — `updateMouseLock` calls `setNeedsUpdateOfPrefersPointerLocked` on the game window's root VC (`IOSViewController`) directly, rather than broadcasting to all windows. Broadcasting caused a race with the base `UIViewController` hook (which returns `NO`), producing non-deterministic lock state.
- **Eager mouse button identification** — `GCControllerButtonInput` button type is captured at hook-install time. `GCMouse.current` is only valid during Fortnite's startup init window; lazy in-block lookup returned `nil` after that, breaking button identification.
- **Optimized view hierarchy traversal** — `hitTest:` uses a fast O(n) search instead of O(n log n) sorting. UITouch hierarchy walk uses a single-entry O(1) cache (~1 ns hit rate ~85%).
- Sensitivity settings renamed for clarity (`LOOK_MULTIPLIER_X/Y` → `LOOK_SENSITIVITY_X/Y`, etc.).
- ADS state now read from the `eventMouse` event object rather than `GCMouse.current` to prevent stale reads during focus transitions.
- Mouse unlock resets the fractional accumulator to prevent an incorrect first-delta on re-lock.
- Popup window uses `UIWindowScene` APIs throughout — no deprecated `keyWindow` calls.
- All UI coordinates pixel-aligned via `PixelAlign()` for crisp rendering on Retina displays.
- Settings popup height increased from 400 px to 600 px to accommodate new tabs.
- Key remapping array uses `(GCKeyCode)-1` as a sentinel for "block this key" to distinguish from "no remap" (0).

### 🐛 Fixed
- Camera snap when toggling ADS — accumulator flushed on every ADS state transition.
- Stuck left-click in Build Mode when transitioning from UITouch mode to ADS mode mid-press.
- Blurry text and borders in the settings panel on Retina displays.
- Duplicate key-press events on key-repeat caused by missing single-entry lookup cache.
- Native gamepad pass-through — fixed a logic error in `GCControllerButtonInput` that could cause lag or recursion.

---

## [1.0.0] — Initial Release

- Mouse pointer lock toggle (Left Option key)
- 120 FPS unlock via `UIScreen.maximumFramesPerSecond`
- Graphics preset unlock via device spoofing (iPad17,4)
- Basic hip-fire / ADS sensitivity multipliers
- Settings popup (P key) with sensitivity text fields
- Touch interaction fix for the mobile UI overlay
- Facebook fishhook integration for `sysctl` / `sysctlbyname` spoofing
