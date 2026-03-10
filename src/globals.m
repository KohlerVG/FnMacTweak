#import "./globals.h"

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <string.h> // For memset

// Key for hiding/revealing mouse pointer
GCKeyCode TRIGGER_KEY;
GCKeyCode POPUP_KEY;

// Fortnite PC sensitivity settings
// OPTIMAL CONFIGURATION FOR PERFECT PC MATCH + ZERO INPUT LOSS
// Default: 6.4% base × 50% look/scope × 20.0 scale = balanced sensitivity
// These values provide a good starting point for most users
float BASE_XY_SENSITIVITY =
    6.4f; // X/Y-Axis (base) sensitivity (recommended: 6.4)
float LOOK_SENSITIVITY_X =
    50.0f; // Look Sensitivity X (hip-fire) (recommended: 50%)
float LOOK_SENSITIVITY_Y =
    50.0f; // Look Sensitivity Y (hip-fire) (recommended: 50%)
float SCOPE_SENSITIVITY_X =
    50.0f; // Scope Sensitivity X (ADS) (recommended: 50%)
float SCOPE_SENSITIVITY_Y =
    50.0f; // Scope Sensitivity Y (ADS) (recommended: 50%)

// macOS to PC conversion scale
// This factor converts macOS mouse deltas to match PC input scale
// Based on testing with various mice and DPI settings
// Recommended: 20.0 for balanced feel that matches PC Fortnite
float MACOS_TO_PC_SCALE = 20.0f; // Conversion factor (recommended: 20.0)

// Pre-calculated sensitivities for performance optimization
double hipSensitivityX = 0.0;
double hipSensitivityY = 0.0;
double adsSensitivityX = 0.0;
double adsSensitivityY = 0.0;

// Key remapping storage
NSMutableDictionary<NSNumber *, NSNumber *> *keyRemappings = nil;

// ULTRA-PERFORMANCE KEY REMAPPING - INLINE ARRAY LOOKUP
// Using direct array indexing instead of dictionary/function calls
// Overhead: 0 nanoseconds for non-remapped keys, ~2ns for remapped keys
// This is faster than any hash table or function call

// Direct remapping array - indexed by GCKeyCode
// keyRemapArray[sourceKey] = targetKey (0 = no remap)
extern GCKeyCode keyRemapArray[256];

// Fast cache for last lookup (helps with key repeats)
extern GCKeyCode lastLookupKey;
extern GCKeyCode lastRemappedKey;

// ULTRA-PERFORMANCE KEY REMAPPING - DUAL ARRAY SYSTEM
// Using direct array indexing instead of dictionary/function calls
// Overhead: 0 nanoseconds for non-remapped keys, ~2-3ns for remapped keys
// This is faster than any hash table or function call

// Advanced Custom Remaps array - indexed by GCKeyCode
// keyRemapArray[sourceKey] = targetKey (0 = no remap, -1 = blocked)
GCKeyCode keyRemapArray[256] = {0};

// Fortnite Keybinds array - indexed by GCKeyCode
// fortniteRemapArray[customKey] = defaultKey (0 = no remap)
GCKeyCode fortniteRemapArray[256] = {0};
// Reverse map: fortniteReverseMap[defaultKey] = currentKey (0 = using default)
GCKeyCode fortniteReverseMap[256] = {0};

// Fortnite Blocked Defaults array - tracks which default keys should be blocked
// When you remap "Reload" from R to L, we need to block R
// fortniteBlockedDefaults[defaultKey] = 1 (blocked), 0 (not blocked)
uint8_t fortniteBlockedDefaults[256] = {0};

// Mouse button remap — zero-latency C array.
// Index = buttonCode - MOUSE_BUTTON_MIDDLE  (0=middle, 1=aux0, 2=aux1 ...)
// Value = target GCKeyCode (0 = no remap)
GCKeyCode mouseButtonRemapArray[MOUSE_REMAP_COUNT] = {0}; // Advanced Remaps
GCKeyCode mouseFortniteArray[MOUSE_REMAP_COUNT] = {
    0}; // Fortnite mouse keybinds
GCKeyCode mouseScrollRemapArray[MOUSE_SCROLL_COUNT] = {0};   // Scroll advanced remaps
GCKeyCode mouseScrollFortniteArray[MOUSE_SCROLL_COUNT] = {0}; // Scroll Fortnite keybinds

// Fast cache for last lookup (helps with key repeats)
GCKeyCode lastLookupKey = 0;
GCKeyCode lastRemappedKey = 0;

// Function to recalculate sensitivities (call when settings change)
void recalculateSensitivities() {
  hipSensitivityX = (BASE_XY_SENSITIVITY / 100.0) *
                    (LOOK_SENSITIVITY_X / 100.0) * MACOS_TO_PC_SCALE;
  hipSensitivityY = (BASE_XY_SENSITIVITY / 100.0) *
                    (LOOK_SENSITIVITY_Y / 100.0) * MACOS_TO_PC_SCALE;
  adsSensitivityX = (BASE_XY_SENSITIVITY / 100.0) *
                    (SCOPE_SENSITIVITY_X / 100.0) * MACOS_TO_PC_SCALE;
  adsSensitivityY = (BASE_XY_SENSITIVITY / 100.0) *
                    (SCOPE_SENSITIVITY_Y / 100.0) * MACOS_TO_PC_SCALE;
}

// Load key remappings from persistent storage
void loadKeyRemappings() {
  if (!keyRemappings) {
    keyRemappings = [NSMutableDictionary dictionary];
  }

  // Clear the array first
  memset(keyRemapArray, 0, sizeof(keyRemapArray));
  memset(mouseButtonRemapArray, 0, sizeof(mouseButtonRemapArray));
  memset(mouseScrollRemapArray, 0, sizeof(mouseScrollRemapArray));
  memset(mouseScrollFortniteArray, 0, sizeof(mouseScrollFortniteArray));

  NSDictionary *saved =
      [[NSUserDefaults standardUserDefaults] dictionaryForKey:kKeyRemapKey];
  [keyRemappings removeAllObjects]; // Always clear, even if saved is nil
  if (saved) {

    // Convert string keys back to NSNumber keys and populate array
    for (NSString *keyString in saved) {
      int sourceKey = [keyString intValue];
      NSNumber *targetValue = saved[keyString];
      GCKeyCode targetKey = (GCKeyCode)[targetValue integerValue];

      // Store in dictionary (for UI display)
      NSNumber *key = @(sourceKey);
      keyRemappings[key] = targetValue;

      if (sourceKey < 256) {
        // Keyboard key — fast lookup array
        keyRemapArray[sourceKey] = (targetKey == 0) ? (GCKeyCode)-1 : targetKey;
      } else if (sourceKey >= MOUSE_BUTTON_MIDDLE &&
                 sourceKey < MOUSE_BUTTON_MIDDLE + MOUSE_REMAP_COUNT) {
        // Mouse button — fast lookup array
        int idx = sourceKey - MOUSE_BUTTON_MIDDLE;
        mouseButtonRemapArray[idx] = targetKey;
      } else if (sourceKey >= MOUSE_SCROLL_UP &&
                 sourceKey < MOUSE_SCROLL_UP + MOUSE_SCROLL_COUNT) {
        // Scroll — fast lookup array
        int idx = sourceKey - MOUSE_SCROLL_UP;
        mouseScrollRemapArray[idx] = targetKey;
      }
    }
  }

  // Clear cache when remappings change
  lastLookupKey = 0;
  lastRemappedKey = 0;
}

// Save key remappings to persistent storage
// CRITICAL: This must be called after ANY change to keyRemappings dictionary
// to ensure remappings persist across app restarts
void saveKeyRemappings() {
  // Convert to serializable format
  NSMutableDictionary *serializableDict = [NSMutableDictionary dictionary];

  // Clear the array first
  memset(keyRemapArray, 0, sizeof(keyRemapArray));
  memset(mouseButtonRemapArray, 0, sizeof(mouseButtonRemapArray));
  memset(mouseScrollRemapArray, 0, sizeof(mouseScrollRemapArray));
  memset(mouseScrollFortniteArray, 0, sizeof(mouseScrollFortniteArray));

  for (NSNumber *key in keyRemappings) {
    NSNumber *value = keyRemappings[key];
    NSString *keyString = [key stringValue];
    serializableDict[keyString] = value;

    int sourceKey = [key intValue];
    GCKeyCode targetKey = (GCKeyCode)[value integerValue];

    if (sourceKey < 256) {
      // Keyboard key — fast lookup array
      keyRemapArray[sourceKey] = (targetKey == 0) ? (GCKeyCode)-1 : targetKey;
    } else if (sourceKey >= MOUSE_BUTTON_MIDDLE &&
               sourceKey < MOUSE_BUTTON_MIDDLE + MOUSE_REMAP_COUNT) {
      // Mouse button — fast lookup array
      int idx = sourceKey - MOUSE_BUTTON_MIDDLE;
      mouseButtonRemapArray[idx] = targetKey;
    } else if (sourceKey >= MOUSE_SCROLL_UP &&
               sourceKey < MOUSE_SCROLL_UP + MOUSE_SCROLL_COUNT) {
      // Scroll — fast lookup array
      int idx = sourceKey - MOUSE_SCROLL_UP;
      mouseScrollRemapArray[idx] = targetKey;
    }
  }

  [[NSUserDefaults standardUserDefaults] setObject:serializableDict
                                            forKey:kKeyRemapKey];
  [[NSUserDefaults standardUserDefaults] synchronize]; // Force immediate save

  // Clear cache when remappings change
  lastLookupKey = 0;
  lastRemappedKey = 0;
}

// Load Fortnite keybinds into fast lookup array
void loadFortniteKeybinds() {
  // Clear all arrays
  memset(fortniteRemapArray, 0, sizeof(fortniteRemapArray));
  memset(fortniteBlockedDefaults, 0, sizeof(fortniteBlockedDefaults));
  memset(fortniteReverseMap, 0, sizeof(fortniteReverseMap));
  memset(mouseFortniteArray, 0, sizeof(mouseFortniteArray));

  NSDictionary *fortniteBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"];
  if (!fortniteBindings)
    return;

  // Hardcoded action-to-default-key mappings (MUST match popupViewController.m
  // exactly)
  static NSDictionary *actionDefaults = nil;
  if (!actionDefaults) {
    actionDefaults = @{
      @"Forward" : @(26),
      @"Left" : @(4),
      @"Backward" : @(22),
      @"Right" : @(7),
      @"Sprint" : @(225),
      @"Crouch" : @(224),
      @"Auto Walk" : @(46),
      @"Harvesting Tool" : @(9),
      @"Use" : @(8),
      @"Reload" : @(21),
      @"Weapon Slot 1" : @(30),
      @"Weapon Slot 2" : @(31),
      @"Weapon Slot 3" : @(32),
      @"Weapon Slot 4" : @(33),
      @"Weapon Slot 5" : @(34),
      @"Build" : @(20),
      @"Edit" : @(10),
      @"Wall" : @(29),
      @"Floor" : @(27),
      @"Stairs" : @(6),
      @"Roof" : @(25),
      @"Inventory Toggle" : @(230),
      @"Emote" : @(5),
      @"Chat" : @(40),
      @"Push To Talk" : @(23),
      @"Shake Head" : @(11),
      @"Map" : @(16)
    };
  }

  // Build the fast lookup arrays
  // fortniteRemapArray[customKey] = defaultKey
  // fortniteBlockedDefaults[defaultKey] = 1 (when remapped away)
  for (NSString *action in fortniteBindings) {
    NSNumber *customKey = fortniteBindings[action];
    NSNumber *defaultKey = actionDefaults[action];

    if (customKey && defaultKey && [defaultKey integerValue] != 0) {
      GCKeyCode custom = [customKey integerValue];
      GCKeyCode def = [defaultKey integerValue];

      // Only store if keys are different (actual remap)
      if (custom != def && custom < 256 && def < 256) {
        fortniteRemapArray[custom] = def; // customKey → defaultKey
        fortniteReverseMap[def] = custom; // defaultKey → currentKey (reverse)
        fortniteBlockedDefaults[def] = 1;
      }
    }
  }

  // Load mouse button → Fortnite action bindings (stored separately from
  // keyRemappings) Format: "mouseCode" -> defaultActionKey (both as
  // NSNumber-turned-strings)
  NSDictionary *mouseBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"mouseFortniteBindings"];
  if (mouseBindings) {
    for (NSString *codeString in mouseBindings) {
      int mouseCode = [codeString intValue];
      GCKeyCode defaultKey =
          (GCKeyCode)[[mouseBindings objectForKey:codeString] integerValue];
      int idx = mouseCode - MOUSE_BUTTON_MIDDLE;
      if (idx >= 0 && idx < MOUSE_REMAP_COUNT && defaultKey > 0) {
        mouseFortniteArray[idx] = defaultKey;
      }
      // Also handle scroll codes (MOUSE_SCROLL_UP..MOUSE_SCROLL_RIGHT)
      int scrollIdx = mouseCode - MOUSE_SCROLL_UP;
      if (scrollIdx >= 0 && scrollIdx < MOUSE_SCROLL_COUNT && defaultKey > 0) {
        mouseScrollFortniteArray[scrollIdx] = defaultKey;
      }
    }
  }
}

BOOL isMouseLocked = false;

// BUILD mode setting (default: NO = ZERO BUILD mode)
BOOL isBuildModeEnabled = false;
BOOL isBorderlessModeEnabled = false;

// Red dot target indicator for BUILD mode
UIView *redDotIndicator = nil;
CGPoint redDotTargetPosition = {0, 0};
BOOL isRedDotDragging = false;

// UI and popup stuff
UIWindow *popupWindow = nil;
BOOL isPopupVisible = false;

// Key capture callback for popup
void (^keyCaptureCallback)(GCKeyCode keyCode) = nil;

// Mouse button capture callback for popup
void (^mouseButtonCaptureCallback)(int buttonCode) = nil;
