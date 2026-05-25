# 📋 Changelog

All notable changes to FnMacTweak are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [5.0.0] — May 2026

### ✨ Added

#### 🔬 God-Mode Gyro Engine (Level 27 — Quantum Trajectory Predictor)
- **UE Engine Binary Hook** — Directly intercepts Unreal Engine's `FAppleControllerDevice::GetControllerOrientationAndPositionEiR5FQuatR7FVector` symbol via fishhook (GOT patching). Camera aim is now driven at the engine's internal polling frequency, completely bypassing the CoreMotion → GCKit → UE abstraction chain.
- **Quantum Trajectory Predictor** — Computes a 0.2 ms look-ahead on the Euler pitch/yaw velocity slope to pre-compensate for USB/OS bus latency. The game's camera receives a predicted position rather than a stale one.
- **Cache-Aligned God-Mode State (`FnGodModeState`)** — A 128-byte `__attribute__((aligned(128)))` struct holds all orientation atomics (`pitch`, `yaw`, `roll`, `lastPitch`, `lastYaw`, `lastTimestamp`, `enabled`) in a single L1 cache line, eliminating memory stalls on the hot path.
- **Atomic Dual-Buffer Mouse Accumulator** — Replaced the single `mouseAccumX/Y` doubles with `_Atomic double mouseAccumBufferX[2]` / `mouseAccumBufferY[2]` + `_Atomic int activeBufferIdx` double-buffer. The gyro hook atomically swaps buffers and drains, making accumulation fully lock-free and safe across the HID thread and the gyro polling thread.
- **Quantum Counter (Level 24 — Absolute 0 Tracking)** — `g_quantumPushedX/Y` atomics track the delta already "pre-pushed" into the game engine via the Quartz tap. The gyro `hooked_rotationRate` subtracts this from the accumulator before converting to velocity, preventing double-counting between the push path and the pull path.
- **`g_lastGyroPollTime` upgraded to `_Atomic uint64_t`** — Now measured in Mach absolute ticks for sub-microsecond dt resolution (was `double` in seconds with CACurrentMediaTime).
- **`GCMotion.rotationRate` hook** — The gyro hook now also intercepts `GCMotion` directly (in addition to `CMMotionManager` and `CMDeviceMotion`) for full virtual controller parity.
- **Mach-Time Precision in `hooked_rotationRate`** — Uses `mach_absolute_time()` + `mach_timebase_info` for ≤ 1 µs dt, compared to CACurrentMediaTime's ~1 ms floor.
- **Real-time thread elevation in gyro hook** — `elevateThreadToRealTime()` is called once (via `dispatch_once`) inside `hooked_rotationRate`, ensuring the CoreMotion thread runs at Mach real-time priority.

#### 🖱️ IOHID-Prime Raw Mouse Pipeline (Level 14)
- **IOHIDManager integration** — Directly registers an `IOHIDManager` matching USB/BT mice (`DeviceUsagePage 0x01 / DeviceUsage 0x02`). Raw HID reports bypass the Quartz event system entirely.
- **1000 Hz HID thread** — The HID run loop runs on a dedicated `DISPATCH_QUEUE_PRIORITY_HIGH` thread with `elevateThreadToRealTime()`, delivering mouse deltas at hardware polling rate.
- **16-bit high-precision HID parser** — Reports ≥ 5 bytes are parsed as 16-bit signed little-endian X/Y; shorter reports fall back to 8-bit. Covers all high-DPI gaming mice.
- **Quartz event tap bypass** — When `g_hidManager` is active, mouse-move Quartz events are swallowed and the HID source is used as the exclusive aim input, eliminating double-counting.
- **HID-clock stick re-assertion** — `_updateVStick(NO/YES, YES)` (sync) is called inside the HID report callback at 1000 Hz, removing the 1–2 ms scheduling jitter of the previous DisplayLink-only approach.
- **`g_hidManager` / `HID_SENSITIVITY_SCALAR`** — Global HID manager handle and a `2.5f` scalar exposed in `globals` for sensitivity tuning independent of the gyro multiplier.

#### 🛡️ Anti-Detection & Stealth Suite
- **Full dyld image hiding** — Six fishhook rebindings (`_dyld_image_count`, `_dyld_get_image_name`, `_dyld_get_image_header`, `_dyld_get_image_vmaddr_slide`, `_dyld_register_func_for_add_image`, `_dyld_register_func_for_remove_image`) filter the tweak's Mach-O header out of the in-process image list. Anti-cheat scanners calling `_dyld_image_count` or iterating images no longer see FnMacTweak.
- **`dladdr` hook** — Returns failure for any address inside the tweak's `dli_fbase`, hiding it from symbol resolution attempts.
- **`isMacCatalystApp` swizzle** — Added alongside the existing `isiOSAppOnMac` / `isiOSAppOnMic` swizzles; all three now cover both `NSProcessInfo` and `_NSSwiftProcessInfo`.
- **Stealth compositor window** — An invisible `UIWindow` (`alpha 0.01`, no interaction) at `UIWindowLevelStatusBar + 1000` forces macOS to stay in composited mode during fullscreen, preventing detection via compositor state queries.
- **`NSNotificationCenter` hook** — Suppresses `NSApplicationWillResignActiveNotification` and `NSApplicationDidResignActiveNotification` at the `postNotificationName:` level, preventing Fortnite from detecting the process entering the background.
- **Sysctl Virtualization Suite (Level 27)** — Hooks `sysctlnametomib` + `sysctl` + `sysctlbyname` to intercept six additional kernel queries via pseudo-MIB constants:
  - `kern.willshutdown` → `0` (not shutting down)
  - `security.mac.lockdown_mode_state` → `0` (lockdown off)
  - `kern.osrevision` → `199001`
  - `kern.uuid` → zeroed UUID
  - `machdep.cpu.brand_string` → `"Apple M1"`
  - `sysctl.proc_translated` → `0` (native, not Rosetta)

#### 🌍 EU Marketplace Bypass
- **`MKW_GetEligibilityRegion` hook** — Intercepts Epic's marketplace eligibility callback and forces `eligible = true, regionCode = "EU"`.
- **`MKW_RequestCTToken` hook** — Intercepts the CT token request and returns a mock success token, bypassing the EU compliance check.

#### 🎮 macOS 26.4 / Fortnite v40 Crash Fix
- **`_availability_version_check` hook** — Fortnite v40.00.1 contains a Swift `@available(iOS 17.4, *)` check that hits a NULL async continuation on macOS 26.4 Catalyst, causing an immediate SIGSEGV on launch. The hook returns `false` for exactly the `PLATFORM_IOS / 17.4.0` version tuple, forcing the safe fallback code path. All other version checks pass through unchanged.

#### ⚡ GameUserSettings.ini Auto-Force 120 FPS
- **`open` / `close` / `fopen` / `fclose` hooks** — Monitor all file descriptors and streams that reference `GameUserSettings.ini`. On close, a post-write scan replaces `b120FpsMode=False` → `True` and any `MobileFPSMode=Mode_{30,45,60,90}Fps` → `Mode_120Fps` in-place. Thread-safe via `pthread_mutex_t`.

#### 🎮 Ghost-Core Button Cache (Level 21)
- **`FnControllerGhostCache` struct** — Caches all `GCControllerButtonInput *` pointers (A/B/X/Y, L1/R1/L2/R2, L3/R3, Menu, Options, Home) at connect time in an `__unsafe_unretained` struct.
- **`ue_reflect_button_dispatch()`** — Routes button presses through the cache with a single `switch`; zero dictionary/string lookups on the hot path.
- **`updateGhostCache()`** — Called once after `connectWithReplyHandler:` resolves, latching all button pointers for the session.

#### 🚀 PerformanceGuard Class (New Module)
- **`PerformanceGuard` singleton** (`PerformanceGuard.h/m`) — Dedicated class encapsulating all process-level performance escalation:
  - `startHyperPerformanceMode` — Acquires `NSActivityUserInitiated` to kill App Nap without triggering hard thermal throttling.
  - `elevateProcessPriority` — Sets UNIX niceness to `-10` (balanced VIP; avoids WindowServer starvation seen at -20).
  - `currentThermalState` — Returns a human-readable thermal state string (Nominal / Fair / Serious / Critical).
- **Elite Activity Locker** — After virtual controller connect, acquires a second `NSProcessInfo` activity token with full flags (`UserInitiated | LatencyCritical | IdleSleepDisabled | DisplaySleepDisabled`) and forces `setpriority(PRIO_PROCESS, 0, -20)` for the game session.
- **P-Core affinity** — `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` on the main thread at startup.

#### 🧠 Controller & Virtual Remap Infrastructure
- **`getControllerDefaultMapping(int btnIdx)`** — Returns sensible defaults (A→Space, B→ESC, X→R, Y→Y, L2→RClick, R2→LClick, R3→RClick, Left Stick→WASD). Controller saves now only persist values that differ from the default.
- **`updateVCtrlReverseMap()`** — Maintains the `g_vctrlReverseMap[10240]` and `g_vctrlSuppressionMap[10240]` bitmask arrays from `controllerMappingArray`. Called on every load/save.
- **Three new global bitmask arrays** (`g_vctrlReverseMap`, `g_vctrlCustomMap`, `g_vctrlSuppressionMap`) — All lookup paths (keyboard, mouse, scroll, modifier) now use `__builtin_ctz`-based O(1) bitmask dispatch instead of linear scans.
- **`g_vctrlSuppressionMap`** populated by both `updateVCtrlReverseMap()` (hardware) and `recookVCtrlRemappings()` (virtual), providing a single unified suppression check for `_isMouseButtonSuppressed`.
- **`reassertAllInputs()`** — Re-fires all pressed virtual buttons + stick states when the Option key triggers a mode transition, preventing the game engine from dropping held inputs during the cursor warp.
- **Sticky button tracking** — `g_vctrlButtonTargetStates[FnCtrlButtonCount]` remembers every button's intended pressed state; the DisplayLink tick re-asserts all pressed buttons while Option is held.
- **`isSync` parameter in `dispatchControllerButton` and `_updateVStick`** — Sync dispatch (`isSync = YES`) fires immediately on the calling thread (HID/keyboard); async dispatch fires on the next DisplayLink tick for non-time-critical paths.
- **App resign-active → `resetControllerState()`** — A `UIApplicationWillResignActiveNotification` observer resets all virtual controller state when the app loses focus.
- **`g_vctrl_queue`** — Dedicated serial `dispatch_queue_t` exposed in globals for virtual controller operations.

#### 📱 UI / Settings Panel
- **"Container" tab** — New fifth tab in the settings panel providing Fortnite data folder access via security-scoped bookmarks (persisted in `NSUserDefaults` as `fnmactweak.datafolder`). Allows the tweak to access the app's sandbox from outside the sandbox boundary.
- **Liquid Glass video player** — `FnMakePill` / `FnAnimatePress` helpers implement an Apple-style blurred pill UI with a specular border for the Quick Start video transport controls (play/pause, ±5 s skip, scrubber, time labels).
- **`loadTweakSettings()`** — New settings loader that persists tweak-level preferences (`BASE_XY_SENSITIVITY`, `MACOS_TO_PC_SCALE`, `GYRO_MULTIPLIER`, `GCMOUSE_DIRECT_KEY`) in a dedicated `kSettingsKey` dictionary, separate from key remappings.
- **`loadTweakSettings()` called inside `loadKeyRemappings()`** — Guarantees sensitivity and direct-key settings are always loaded before remappings are applied.

---

### 🔄 Changed

- **Default sensitivity values retuned for v5.0.0:**
  - `BASE_XY_SENSITIVITY`: `6.4` → `9.6`
  - `MACOS_TO_PC_SCALE`: `20.0` → `30.0`
  - `GYRO_MULTIPLIER`: `100.0` → `150.0`
  - `GYRO_SENSE`: `0.001` → `0.0015`
- **GCController product spoof** — Virtual controller now reports `"DualSense"` / `"DualSense Wireless Controller"` (was `"DualShock 4"`). Fortnite enables L3/R3 and additional input features for DualSense.
- **`elevateThreadToRealTime()` moved to `globals.m`** — Shared by all hot paths (gyro hook, HID callback, tap callback, scroll monitor). Uses 0.1 ms time-constraint slices + Core Affinity tag 1 for P-core pinning.
- **`recookVCtrlRemappings()`** — Now also fills `g_vctrlCustomMap` and `g_vctrlSuppressionMap` bitmask arrays in addition to `vctrlCookedRemappings`, making all virtual-remap lookups O(1).
- **`saveControllerMappings()`** — Only persists button mappings that differ from `getControllerDefaultMapping()`; zero-value and default-value entries are omitted from storage, reducing bloat.
- **`loadControllerMappings()`** — Now pre-fills `controllerMappingArray` with defaults from `getControllerDefaultMapping()` before applying saved overrides. First launch now has sensible bindings out of the box.
- **`GCMouseInput setMouseMovedHandler:`** — Mouse deltas are now accumulated into the dual atomic buffer (`mouseAccumBufferX/Y[activeBufferIdx]`) instead of the old single `mouseAccumX/Y`. In `isGCMouseDirectActive` mode, all four buffer slots are atomically zeroed to prevent ghost gyro movement.
- **`_isMouseButtonSuppressed`** — Primary lookup now uses `g_vctrlSuppressionMap[code]` bitmask (O(1)); linear `controllerMappingArray` scan removed.
- **`GCVirtualControllerConfiguration.elements`** — Now includes `GCInputLeftShoulder`, `GCInputRightShoulder`, `GCInputLeftTrigger`, `GCInputRightTrigger` in addition to face buttons and thumbsticks, enabling L1/R1/L2/R2 synthesis.
- **Makefile SDK target** — `TARGET` updated to `iphone:clang:latest:26.0` for macOS 26 / iOS 26 SDK compatibility.
- **CGEvent mouse type constants corrected** — `kCGEventRightMouseDown` fixed from 5 → 3; `kCGEventRightMouseUp` from 6 → 4; `kCGEventLeftMouseDragged` from 3 → 6; `kCGEventMouseMoved` added as 5.
- **`_CGEventSetType`, `_CGEventCreateMouseEvent`, `_CGEventGetTimestamp`** — Three new CoreGraphics function pointers resolved at runtime and used by the mouse event synthesizer.
- **`GCControllerDirectionPad setValueChangedHandler:`** — Scroll suppression now also checks `g_vctrlCustomMap` bitmask for controller-mapped scroll directions, preventing raw scroll from firing alongside a controller button dispatch.
- **`IMP` caching in `ue_reflect_button_press/release`** — Class-level IMP for `_setValue:` is resolved once via `class_getInstanceMethod` and cached, removing the per-call `objc_msgSend` lookup overhead.
- **`_updateVStick` diagonal normalization** — Pre-computed `0.7071` constant (was `sqrtf`), eliminating one `sqrtf` call per direction update.

---

### 🐛 Fixed

- **Duplicate `kKeyRemapKey` macro in `globals.h`** — The `#define kKeyRemapKey` was declared twice; duplicate removed.
- **Duplicate `isPopupVisible` extern in `globals.h`** — Appeared twice; deduplicated.
- **Duplicate `POPUP_KEY` extern in `globals.h`** — Appeared twice; deduplicated.
- **Duplicate `loadFortniteKeybinds` declaration in `globals.h`** — Appeared twice; deduplicated.
- **Missing setting-key macros in `globals.h`** — Added `kSettingsKey`, `kBaseXYKey`, `kLookXKey`, `kLookYKey`, `kScopeXKey`, `kScopeYKey`, `kScaleKey` which were referenced in `globals.m` but not declared in the header (4.0.0 would fail to compile with strict includes).
- **Gyro double-counting between push and pull paths** — The Quantum Counter (`g_quantumPushedX/Y`) tracks deltas already delivered via the Quartz push path; the gyro pull path subtracts these before computing velocity. Prevents the "acceleration spike" on fast mouse flicks.
- **Controller state not cleared on app switch** — `UIApplicationWillResignActiveNotification` → `resetControllerState()` ensures no virtual buttons remain held when Fortnite loses window focus.
- **L3/R3 buttons not recognized by Fortnite** — `FnInjectedButton` (`%subclass GCControllerButtonInput`) provides a concrete subclass with working `isPressed`/`value`/`_setValue:` backed by associated objects. The `%hook GCExtendedGamepad` now also intercepts the private `_leftThumbstickButton` / `_rightThumbstickButton` selectors.
- **GCMouse direct-mode ghost gyro** — When `isGCMouseDirectActive` is toggled off, `resetControllerState()` is called and all four accumulator slots are atomically zeroed, preventing residual gyro velocity.
- **Scroll controller-remap double-fire** — The `GCControllerDirectionPad` wrapped handler now checks `g_vctrlCustomMap` (virtual remap) in addition to `controllerMappingArray` (hardware remap) before passing raw scroll to the game.

---

### ⚡ Performance

- **O(1) bitmask dispatch everywhere** — All keyboard, mouse button, scroll, and modifier key hot paths now use `__builtin_ctz` bitmask loops over `g_vctrlReverseMap | g_vctrlCustomMap` instead of linear `for` loops over `controllerMappingArray` (25 iterations) or `vctrlRemappings` (N iterations).
- **IMP caching in `ue_reflect_thumbstick`** — The private `_setValueX:Y:` IMP is resolved once via `class_getInstanceMethod` and called directly, eliminating `objc_msgSend` overhead on every frame.
- **Zero-alloc `FnControllerGhostCache` dispatch** — `ue_reflect_button_dispatch()` resolves `GCControllerButtonInput *` pointers from a pre-cached struct with a single `switch`, replacing per-call `elementForName:` / `respondsToSelector:` chains.
- **1000 Hz HID-clock stick polling** — Stick states are re-asserted from the IOHID callback thread rather than waiting for the next 120 Hz DisplayLink tick. Movement latency floor drops from ~8 ms to ~1 ms.
- **Eliminated per-event `NSInvocation` in display-link tick** — The `FnInputPulse` display-link calls `_updateVStick` and `dispatchControllerButton` directly; no `NSInvocation` or `performSelector:` overhead.

---

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
