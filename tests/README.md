# Controller compatibility checks

On macOS with Xcode command-line tools:

```sh
python3 tests/run_controller_tests.py
python3 tests/run_motion_tests.py
python3 tests/run_responder_tests.py
make -j2 FINALPACKAGE=1
```

The host tests compile the current production dispatch, lifecycle, and motion functions with device fixtures. They exercise owned-device isolation, button callback counts (including setter-less fallback), native motion passthrough, multiple physical devices, hotplug, pending-connection cancellation, unexpected disconnects, failures/retry, mode persistence, motion reset/restart, and concurrent polling/reset. Hotplug cases include notifications preceding device-list updates, stale disconnected entries across repeated refreshes, reconnects using the same or a new controller object, and physical reconnects during a pending virtual connection. The responder suite also verifies that off-main first-responder requests execute exactly once on the main thread and preserve both successful and rejected return values. Framework fixtures do not establish Fortnite compatibility or measure latency.

Auto hands physical input back to local player 0 by posting `GCControllerDidBecomeCurrentNotification` after the original physical connection observers and virtual teardown. It waits for any pending virtual connection to finish, deduplicates the handoff, and cancels it on physical loss or an explicit mode change. It does not change physical inputs, callbacks, or the saved mode. There is no timed virtual-controller recovery pulse.

The game-slot fixture follows the installed arm64 executable (UUID `CC0231F5-9202-3EF0-8559-7EECBBCFC27D`): connection/disconnection/current notifications enqueue distinct events at `0x104d8d710`; their handlers are `0x104d8d080`, `0x104d8d7c0`, and `0x104d8da30`. The current-device handler moves the selected registered device to player 0. Disconnect only removes the matching device. Tests reproduce a physical device stuck at player 1 after virtual removal and verify promotion with its held input intact. Disabling the selection post makes that regression fail. These addresses document the analysis only; the tweak does not patch them or depend on a game version's addresses. Real-game validation is still required.

Before release, test Xbox and PlayStation controllers using Bluetooth and USB where available:

- Confirm startup passes the Epic logo without the `UINSWindowProxyFocusHelper ... Called off the main thread` exception. Check entering/leaving text fields and opening/closing the tweak menu.
- In Auto, connect before launch and again after reaching the lobby. Disconnect/reconnect, including two connected controllers. Verify input without power-cycling the controller.
- Check single LB/RB presses, rapid taps, held buttons, analog trigger ramps, full stick travel, D-pad, and physical gyro. One press must produce one action.
- Hold physical buttons/triggers while opening settings, changing modes, unlocking the cursor, and switching focus. Native holds and releases must remain correct.
- Switch Auto/On/Off during virtual holds and while connection is pending. Check neutral reconnect, updated status, saved mode after relaunch, and saved bindings after disabling virtual input.
- Export/import each mode; import an older backup without the mode and confirm Auto. Confirm applying/resetting mapping rows does not enable virtual input while Off.
- Verify keyboard/mouse bindings, advanced virtual remaps, L3/R3, Option cursor teleport while holding movement, typing mode, and gyro mouse aiming. Off and failed connections must allow native mapped keys through.
- Compare controller responsiveness with an untweaked build at the same frame rate and using the same connection. Use video/input timestamps for latency claims; callback fixture tests cannot measure end-to-end delay.

Known [framework constraint](https://developer.apple.com/documentation/gamecontroller/gcvirtualcontroller/configuration/elements): Apple's virtual-controller configuration chooses the left thumbstick over the D-pad when both are requested. This change keeps left-stick configuration; D-pad injection operates only where the resulting profile exposes it. No physical D-pad is synthesized or modified.
