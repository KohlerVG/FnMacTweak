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

float BASE_XY_SENSITIVITY = 6.4f;
float LOOK_SENSITIVITY_X  = 50.0f;
float LOOK_SENSITIVITY_Y  = 50.0f;
float SCOPE_SENSITIVITY_X = 50.0f;
float SCOPE_SENSITIVITY_Y = 50.0f;
float MACOS_TO_PC_SCALE   = 20.0f;
float GYRO_MULTIPLIER     = 100.0f;
double GYRO_SENSE         = 0.001;
BOOL isGCMouseDirectActive = NO;
GCKeyCode GCMOUSE_DIRECT_KEY = 53; // Default to Backtick (GC 53)

double hipSensitivityX = 0.0;
double hipSensitivityY = 0.0;
double adsSensitivityX = 0.0;
double adsSensitivityY = 0.0;

// --- GLOBAL INPUT STATE ---
BOOL isMouseLocked = NO;
double mouseAccumX = 0.0;
double mouseAccumY = 0.0;
BOOL leftButtonIsPressed = NO;
BOOL rightButtonIsPressed = NO;
BOOL middleButtonIsPressed = NO;
double g_lastGyroPollTime = 0.0;
id g_virtualController = nil;
BOOL isControllerModeEnabled = YES;
BOOL isTypingModeEnabled = NO;

id storedKeyboardInput = nil;
void (^storedKeyboardHandler)(id, id, GCKeyCode, BOOL) = nil;
BOOL wasADSInitialized = NO;
id g_capturedMouseInput = nil;
int ignoreNextLeftClickCount = 0;

int controllerMappingArray[FnCtrlButtonCount] = {0};

// --- REMAPPING STORAGE ---
NSMutableDictionary<NSNumber *, NSNumber *> *keyRemappings = nil;
NSMutableArray<NSDictionary *> *vctrlRemappings = nil;
NSDictionary<NSNumber *, NSSet<NSNumber *> *> *vctrlCookedRemappings = nil;
GCKeyCode keyRemapArray[512] = {0};
GCKeyCode fortniteRemapArray[10200] = {0};
GCKeyCode fortniteReverseMap[10200] = {0};
uint8_t fortniteBlockedDefaults[10200] = {0};

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

void loadKeyRemappings() {
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
    NSDictionary *saved = [tweakDefaults() dictionaryForKey:kControllerMappingKey];
    if (saved) {
        for (NSString *idxStr in saved) {
            int btnIdx = [idxStr intValue];
            if (btnIdx >= 0 && btnIdx < FnCtrlButtonCount) controllerMappingArray[btnIdx] = [[saved objectForKey:idxStr] intValue];
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
}

void saveControllerMappings(void) {
    // Controller Mode is now always enabled
    
    // Save controller hardware mappings
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        if (controllerMappingArray[i] != 0) out[[NSString stringWithFormat:@"%d", i]] = @(controllerMappingArray[i]);
    }
    [tweakDefaults() setObject:out forKey:kControllerMappingKey];

    // Save virtual controller remaps
    [tweakDefaults() setObject:vctrlRemappings forKey:kVCtrlRemapKey];

    [tweakDefaults() synchronize];
    recookVCtrlRemappings();
}

void recookVCtrlRemappings(void) {
    NSMutableDictionary *cooked = [NSMutableDictionary dictionary];
    for (NSDictionary *remap in vctrlRemappings) {
        NSNumber *src = remap[@"src"];
        NSNumber *dst = remap[@"dst"];
        if (src && dst && [src intValue] >= 0) {
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
