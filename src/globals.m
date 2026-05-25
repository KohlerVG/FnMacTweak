#import "./globals.h"
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <string.h>

GCKeyCode TRIGGER_KEY;
GCKeyCode POPUP_KEY;

__attribute__((constructor))
static void initialize_global_keys() {
    TRIGGER_KEY = 226; // Left Alt / Option
    POPUP_KEY = GCKeyCodeF1;
}

float BASE_XY_SENSITIVITY = 9.6f;
float LOOK_SENSITIVITY_X  = 50.0f;
float LOOK_SENSITIVITY_Y  = 50.0f;
float SCOPE_SENSITIVITY_X = 50.0f;
float SCOPE_SENSITIVITY_Y = 50.0f;
float MACOS_TO_PC_SCALE   = 30.0f;
float GYRO_MULTIPLIER     = 150.0f;
double GYRO_SENSE         = 0.0015;
BOOL isGCMouseDirectActive = NO;
GCKeyCode GCMOUSE_DIRECT_KEY = 53; // Default to Backtick (GC 53)

double hipSensitivityX = 0.0;
double hipSensitivityY = 0.0;
double adsSensitivityX = 0.0;
double adsSensitivityY = 0.0;

// --- GLOBAL INPUT STATE ---
#include <stdatomic.h>
BOOL isMouseLocked = NO;
_Atomic double mouseAccumBufferX[2] = {0, 0};
_Atomic double mouseAccumBufferY[2] = {0, 0};
_Atomic uint64_t mouseHardwareTimestamp[2] = {0, 0};
_Atomic int activeBufferIdx = 0;

// LEVEL 24: Quantum Counters (Absolute 0 Tracking)
_Atomic double g_quantumPushedX = 0;
_Atomic double g_quantumPushedY = 0;

_Atomic uint64_t g_lastGyroPollTime = 0;

// LEVEL 27: God-Mode (Cache-Aligned State)
FnGodModeState g_godReflex = {0};

BOOL leftButtonIsPressed = NO;
BOOL rightButtonIsPressed = NO;
BOOL middleButtonIsPressed = NO;
id g_virtualController = nil;
BOOL isControllerModeEnabled = YES;
FnGCMouseMovedHandler g_originalMouseHandler = nil;
BOOL isTypingModeEnabled = NO;

id storedKeyboardInput = nil;
void (^storedKeyboardHandler)(id, id, GCKeyCode, BOOL) = nil;
BOOL wasADSInitialized = NO;
id g_capturedMouseInput = nil;
int ignoreNextLeftClickCount = 0;

int controllerMappingArray[FnCtrlButtonCount] = {0};
uint32_t g_vctrlReverseMap[10240] = {0};
uint32_t g_vctrlCustomMap[10240] = {0};
uint32_t g_vctrlSuppressionMap[10240] = {0};

void updateVCtrlReverseMap(void) {
    memset(g_vctrlReverseMap, 0, sizeof(g_vctrlReverseMap));
    memset(g_vctrlSuppressionMap, 0, sizeof(g_vctrlSuppressionMap));
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        int code = controllerMappingArray[i];
        if (code > 0 && code < 10240) {
            g_vctrlReverseMap[code] |= (1 << i);
            g_vctrlSuppressionMap[code] = 1; // Mark as suppressed
        }
    }
}

// --- REMAPPING STORAGE ---
NSMutableDictionary<NSNumber *, NSNumber *> *keyRemappings = nil;
NSMutableArray<NSDictionary *> *vctrlRemappings = nil;
NSDictionary<NSNumber *, NSSet<NSNumber *> *> *vctrlCookedRemappings = nil;
GCKeyCode keyRemapArray[512] = {0};
GCKeyCode fortniteRemapArray[10200] = {0};
GCKeyCode fortniteReverseMap[10200] = {0};
uint8_t fortniteBlockedDefaults[10200] = {0};
dispatch_queue_t g_vctrl_queue = nil;

GCKeyCode mouseButtonRemapArray[MOUSE_REMAP_COUNT] = {0};
GCKeyCode mouseFortniteArray[MOUSE_REMAP_COUNT] = {0};
GCKeyCode mouseScrollRemapArray[MOUSE_SCROLL_COUNT] = {0};
GCKeyCode mouseScrollFortniteArray[MOUSE_SCROLL_COUNT] = {0};

GCKeyCode lastLookupKey = 0;
GCKeyCode lastRemappedKey = 0;

// --- UI / POPUP ---
BOOL isPopupVisible = false;
UIWindow *popupWindow = nil;
void (^keyCaptureCallback)(GCKeyCode keyCode) = nil;
void (^mouseButtonCaptureCallback)(int buttonCode) = nil;
void * g_hidManager = NULL;
float HID_SENSITIVITY_SCALAR = 2.5f;

// --- INDICATORS ---
BOOL isBorderlessModeEnabled = false;
UIView *blueDotIndicator = nil;
CGPoint blueDotPosition = {0, 0};

void recalculateSensitivities() {
  hipSensitivityX = (BASE_XY_SENSITIVITY / 100.0) * (LOOK_SENSITIVITY_X / 100.0) * MACOS_TO_PC_SCALE;
  hipSensitivityY = (BASE_XY_SENSITIVITY / 100.0) * (LOOK_SENSITIVITY_Y / 100.0) * MACOS_TO_PC_SCALE;
  adsSensitivityX = (BASE_XY_SENSITIVITY / 100.0) * (SCOPE_SENSITIVITY_X / 100.0) * MACOS_TO_PC_SCALE;
  adsSensitivityY = (BASE_XY_SENSITIVITY / 100.0) * (SCOPE_SENSITIVITY_Y / 100.0) * MACOS_TO_PC_SCALE;
}

void loadTweakSettings() {
  NSDictionary *savedSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSettingsKey];
  if (savedSettings) {
    float v;
    v = [savedSettings[kBaseXYKey] floatValue]; if (v > 0) BASE_XY_SENSITIVITY = v;
    v = [savedSettings[kScaleKey]  floatValue]; if (v > 0) MACOS_TO_PC_SCALE   = v;
    v = [savedSettings[kGyroMultiplierKey] floatValue]; if (v > 0) GYRO_MULTIPLIER = v;
    
    id directKeyVal = savedSettings[kGCMouseDirectKey];
    if (directKeyVal) {
        GCMOUSE_DIRECT_KEY = (GCKeyCode)[directKeyVal intValue];
    }
  }
}

void loadKeyRemappings() {
  loadTweakSettings();
  if (!keyRemappings) keyRemappings = [NSMutableDictionary dictionary];
  memset(keyRemapArray, 0, sizeof(keyRemapArray));
  memset(mouseButtonRemapArray, 0, sizeof(mouseButtonRemapArray));
  memset(mouseScrollRemapArray, 0, sizeof(mouseScrollRemapArray));
  memset(mouseScrollFortniteArray, 0, sizeof(mouseScrollFortniteArray));
  NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kKeyRemapKey];
  [keyRemappings removeAllObjects];
  if (saved) {
    for (NSString *keyString in saved) {
      int sourceKey = [keyString intValue];
      NSNumber *targetValue = saved[keyString];
      GCKeyCode targetKey = (GCKeyCode)[targetValue integerValue];
      keyRemappings[@(sourceKey)] = targetValue;
      if (sourceKey >= 0 && sourceKey < 10200) {
        keyRemapArray[sourceKey % 512] = (targetKey == 0) ? (GCKeyCode)-1 : targetKey;
      } else if (sourceKey >= MOUSE_BUTTON_MIDDLE && sourceKey < MOUSE_BUTTON_MIDDLE + MOUSE_REMAP_COUNT) {
        mouseButtonRemapArray[sourceKey - MOUSE_BUTTON_MIDDLE] = targetKey;
      } else if (sourceKey >= MOUSE_SCROLL_UP && sourceKey < MOUSE_SCROLL_UP + MOUSE_SCROLL_COUNT) {
        mouseScrollRemapArray[sourceKey - MOUSE_SCROLL_UP] = targetKey;
      }
    }
  }
  lastLookupKey = 0; lastRemappedKey = 0;
}

void saveKeyRemappings() {
  NSMutableDictionary *serializableDict = [NSMutableDictionary dictionary];
  memset(keyRemapArray, 0, sizeof(keyRemapArray));
  memset(mouseButtonRemapArray, 0, sizeof(mouseButtonRemapArray));
  memset(mouseScrollRemapArray, 0, sizeof(mouseScrollRemapArray));
  memset(mouseScrollFortniteArray, 0, sizeof(mouseScrollFortniteArray));
  for (NSNumber *key in keyRemappings) {
    NSNumber *value = keyRemappings[key];
    serializableDict[[key stringValue]] = value;
    int sourceKey = [key intValue];
    GCKeyCode targetKey = (GCKeyCode)[value integerValue];
    if (sourceKey >= 0 && sourceKey < 10200) {
      keyRemapArray[sourceKey % 512] = (targetKey == 0) ? (GCKeyCode)-1 : targetKey;
    } else if (sourceKey >= MOUSE_BUTTON_MIDDLE && sourceKey < MOUSE_BUTTON_MIDDLE + MOUSE_REMAP_COUNT) {
      mouseButtonRemapArray[sourceKey - MOUSE_BUTTON_MIDDLE] = targetKey;
    } else if (sourceKey >= MOUSE_SCROLL_UP && sourceKey < MOUSE_SCROLL_UP + MOUSE_SCROLL_COUNT) {
      mouseScrollRemapArray[sourceKey - MOUSE_SCROLL_UP] = targetKey;
    }
  }
  [[NSUserDefaults standardUserDefaults] setObject:serializableDict forKey:kKeyRemapKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
  lastLookupKey = 0; lastRemappedKey = 0;
}

void loadFortniteKeybinds() {
  memset(fortniteRemapArray, 0, sizeof(fortniteRemapArray));
  memset(fortniteBlockedDefaults, 0, sizeof(fortniteBlockedDefaults));
  memset(fortniteReverseMap, 0, sizeof(fortniteReverseMap));
  memset(mouseFortniteArray, 0, sizeof(mouseFortniteArray));
  NSDictionary *fortniteBindings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"fortniteKeybinds"];
  if (!fortniteBindings) return;
  static NSDictionary *actionDefaults = nil;
  if (!actionDefaults) {
    actionDefaults = @{
      @"Forward" : @(26), @"Left" : @(4), @"Backward" : @(22), @"Right" : @(7),
      @"Sprint" : @(225), @"Crouch" : @(224), @"Auto Walk" : @(46),
      @"Harvesting Tool" : @(9), @"Use" : @(8), @"Reload" : @(21),
      @"Weapon Slot 1" : @(30), @"Weapon Slot 2" : @(31), @"Weapon Slot 3" : @(32),
      @"Weapon Slot 4" : @(33), @"Weapon Slot 5" : @(34), @"Build" : @(20),
      @"Edit" : @(10), @"Wall" : @(29), @"Floor" : @(27), @"Stairs" : @(6),
      @"Roof" : @(25), @"Inventory Toggle" : @(230), @"Emote" : @(5),
      @"Chat" : @(40), @"Push To Talk" : @(23), @"Shake Head" : @(11), 
      @"Map" : @(16), @"Escape" : @(41)
    };
  }
  for (NSString *action in fortniteBindings) {
    NSNumber *customKey = fortniteBindings[action];
    NSNumber *defaultKey = actionDefaults[action];
    if (customKey && defaultKey && [defaultKey integerValue] != 0) {
      GCKeyCode custom = [customKey integerValue];
      GCKeyCode def = [defaultKey integerValue];
      if (custom != def && custom < 10200 && def < 10200) {
        fortniteRemapArray[custom] = def;
        fortniteReverseMap[def] = custom;
        fortniteBlockedDefaults[def] = 1;
      }
    }
  }
  NSDictionary *mouseBindings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"mouseFortniteBindings"];
  if (mouseBindings) {
    for (NSString *codeString in mouseBindings) {
      int mouseCode = [codeString intValue];
      GCKeyCode defaultKey = (GCKeyCode)[[mouseBindings objectForKey:codeString] integerValue];
      int idx = mouseCode - MOUSE_BUTTON_MIDDLE;
      if (idx >= 0 && idx < MOUSE_REMAP_COUNT && defaultKey > 0) mouseFortniteArray[idx] = defaultKey;
      int scrollIdx = mouseCode - MOUSE_SCROLL_UP;
      if (scrollIdx >= 0 && scrollIdx < MOUSE_SCROLL_COUNT && defaultKey > 0) mouseScrollFortniteArray[scrollIdx] = defaultKey;
    }
  }
}

void loadControllerMappings(void) {
    isControllerModeEnabled = YES;
    memset(controllerMappingArray, 0, sizeof(controllerMappingArray));
    
    // Initialize with defaults
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        controllerMappingArray[i] = getControllerDefaultMapping(i);
    }

    // Overwrite with custom mappings from UserDefaults
    NSDictionary *saved = [tweakDefaults() dictionaryForKey:kControllerMappingKey];
    if (saved) {
        for (NSString *idxStr in saved) {
            int btnIdx = [idxStr intValue];
            if (btnIdx >= 0 && btnIdx < FnCtrlButtonCount) {
                controllerMappingArray[btnIdx] = [[saved objectForKey:idxStr] intValue];
            }
        }
    }

    // Load Virtual Controller Remaps
    NSArray *vctrlSaved = [tweakDefaults() arrayForKey:kVCtrlRemapKey];
    if (vctrlSaved && [vctrlSaved isKindOfClass:[NSArray class]]) {
        vctrlRemappings = [NSMutableArray arrayWithArray:vctrlSaved];
    } else {
        vctrlRemappings = [NSMutableArray array];
    }
    recookVCtrlRemappings();
    updateVCtrlReverseMap();
}

void saveControllerMappings(void) {
    updateVCtrlReverseMap();
    // Controller Mode is now always enabled
    
    // Save controller hardware mappings
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        int current = controllerMappingArray[i];
        int def = getControllerDefaultMapping(i);
        // Only save if it's not zero AND it's different from the default
        if (current != 0 && current != def) {
            out[[NSString stringWithFormat:@"%d", i]] = @(current);
        }
    }
    [tweakDefaults() setObject:out forKey:kControllerMappingKey];

    // Save virtual controller remaps
    [tweakDefaults() setObject:vctrlRemappings forKey:kVCtrlRemapKey];

    [tweakDefaults() synchronize];
    recookVCtrlRemappings();
}

void recookVCtrlRemappings(void) {
    memset(g_vctrlCustomMap, 0, sizeof(g_vctrlCustomMap));
    NSMutableDictionary *cooked = [NSMutableDictionary dictionary];
    for (NSDictionary *remap in vctrlRemappings) {
        NSNumber *src = remap[@"src"];
        NSNumber *dst = remap[@"dst"];
        if (src && dst && [src intValue] >= 0) {
            int s = [src intValue];
            int d = [dst intValue];
            if (s < 10240 && d < 32) {
                g_vctrlCustomMap[s] |= (1 << d);
                g_vctrlSuppressionMap[s] = 1; // Mark as suppressed
            }
            
            NSMutableSet *set = cooked[src];
            if (!set) {
                set = [NSMutableSet set];
                cooked[src] = set;
            }
            [set addObject:dst];
        }
    }
    vctrlCookedRemappings = [cooked copy];
}

int getControllerDefaultMapping(int btnIdx) {
    switch (btnIdx) {
        case FnCtrlButtonA:        return 44;    // Spacebar
        case FnCtrlButtonB:        return 41;    // ESC
        case FnCtrlButtonX:        return 21;    // R (Reload)
        case FnCtrlButtonY:        return 28;    // Y
        case FnCtrlL2:             return 10051; // Right Click
        case FnCtrlR2:             return 10050; // Left Click
        case FnCtrlR3:             return 10051; // Right Click
        case FnCtrlLeftStickUp:    return 26;    // W
        case FnCtrlLeftStickDown:  return 22;    // S
        case FnCtrlLeftStickLeft:  return 4;     // A
        case FnCtrlLeftStickRight: return 7;     // D
        default:                   return 0;
    }
}
#import <mach/mach.h>
#import <mach/thread_policy.h>

void elevateThreadToRealTime() {
    thread_time_constraint_policy_data_t policy;
    // LEVEL 27: Constraint Hardening (0.1ms Slices)
    policy.period = 100000;      // 0.1ms
    policy.computation = 50000;   // 0.05ms (50% CPU duty cycle)
    policy.constraint = 100000;   // 0.1ms
    policy.preemptible = YES;
    
    thread_policy_set(mach_thread_self(), THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&policy, THREAD_TIME_CONSTRAINT_POLICY_COUNT);

    // LEVEL 20: Core Affinity Pinning
    thread_affinity_policy_data_t affinity;
    affinity.affinity_tag = 1; 
    thread_policy_set(mach_thread_self(), THREAD_AFFINITY_POLICY, (thread_policy_t)&affinity, THREAD_AFFINITY_POLICY_COUNT);
}
