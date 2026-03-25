#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

// For spoofing device specifications
#define DEVICE_MODEL "iPad17,4"
#define OEM_ID "A3361"

// Isolated UserDefaults suite
#define kTweakSuiteName @"com.fnmactweak.prefs"
#define tweakDefaults() [[NSUserDefaults alloc] initWithSuiteName:kTweakSuiteName]

// Setting keys
#define kSettingsKey @"fnmactweak.settings"
#define kBaseXYKey @"baseXYSensitivity"
#define kLookXKey @"lookSensitivityX"
#define kLookYKey @"lookSensitivityY"
#define kScopeXKey @"scopeSensitivityX"
#define kScopeYKey @"scopeSensitivityY"
#define kScaleKey @"macOSToPCScale"
#define kKeyRemapKey @"keyRemappings"
#define kKeyRemapKey @"keyRemappings"
#define kBlueDotPositionKey @"blueDotPosition"
#define kBorderlessWindowKey @"fnmactweak.borderlessWindowEnabled"
#define kControllerModeKey   @"fnmactweak.controllerModeEnabled"
#define kControllerMappingKey @"fnmactweak.controllerMappings"

#define kGyroMultiplierKey @"gyroMultiplier"
#define kGCMouseDirectKey @"gcmouseDirectKey"

typedef NS_ENUM(NSInteger, FnControllerButton) {
    FnCtrlButtonA        = 0,
    FnCtrlButtonB        = 1,
    FnCtrlButtonX        = 2,
    FnCtrlButtonY        = 3,
    FnCtrlDpadUp         = 4,
    FnCtrlDpadDown       = 5,
    FnCtrlDpadLeft       = 6,
    FnCtrlDpadRight      = 7,
    FnCtrlL1             = 8,
    FnCtrlR1             = 9,
    FnCtrlL2             = 10,
    FnCtrlR2             = 11,
    FnCtrlL3             = 12,
    FnCtrlR3             = 13,
    FnCtrlOptions        = 14,
    FnCtrlShare          = 15,
    FnCtrlHome           = 16,
    FnCtrlLeftStickUp    = 17,
    FnCtrlLeftStickDown  = 18,
    FnCtrlLeftStickLeft  = 19,
    FnCtrlLeftStickRight = 20,
    FnCtrlRightStickUp   = 21,
    FnCtrlRightStickDown = 22,
    FnCtrlRightStickLeft = 23,
    FnCtrlRightStickRight= 24,
    FnCtrlButtonCount    = 25,
};

// --- GLOBAL STATE ---
extern int controllerMappingArray[FnCtrlButtonCount];
extern id g_virtualController;
extern BOOL isControllerModeEnabled;
extern BOOL isTypingModeEnabled;
extern id storedKeyboardInput;
extern void (^storedKeyboardHandler)(id, id, GCKeyCode, BOOL);
extern BOOL wasADSInitialized;
extern id g_capturedMouseInput;
extern int ignoreNextLeftClickCount;

extern BOOL isMouseLocked;
extern double mouseAccumX;
extern double mouseAccumY;
extern BOOL leftButtonIsPressed;
extern BOOL rightButtonIsPressed;
extern BOOL middleButtonIsPressed;
extern double g_lastGyroPollTime;

// --- SENSITIVITY ---
extern float BASE_XY_SENSITIVITY;
extern float LOOK_SENSITIVITY_X;
extern float LOOK_SENSITIVITY_Y;
extern float SCOPE_SENSITIVITY_X;
extern float SCOPE_SENSITIVITY_Y;
extern float MACOS_TO_PC_SCALE;
extern float GYRO_MULTIPLIER;
extern double GYRO_SENSE;
extern BOOL isGCMouseDirectActive;
extern GCKeyCode GCMOUSE_DIRECT_KEY;

extern double hipSensitivityX;
extern double hipSensitivityY;
extern double adsSensitivityX;
extern double adsSensitivityY;

// --- REMAPPING ---
extern NSMutableDictionary<NSNumber *, NSNumber *> *keyRemappings;
extern GCKeyCode keyRemapArray[512];
extern GCKeyCode fortniteRemapArray[10200];
extern uint8_t fortniteBlockedDefaults[10200];
extern GCKeyCode fortniteReverseMap[10200];

#define MOUSE_REMAP_COUNT 60
extern GCKeyCode mouseButtonRemapArray[MOUSE_REMAP_COUNT];
extern GCKeyCode mouseFortniteArray[MOUSE_REMAP_COUNT];

#define MOUSE_SCROLL_COUNT 4
extern GCKeyCode mouseScrollRemapArray[MOUSE_SCROLL_COUNT];
#define kVCtrlRemapKey @"vctrlRemappings"

extern NSMutableArray<NSDictionary *> *vctrlRemappings;
extern NSDictionary<NSNumber *, NSSet<NSNumber *> *> *vctrlCookedRemappings;
extern GCKeyCode mouseScrollFortniteArray[MOUSE_SCROLL_COUNT];

extern GCKeyCode lastLookupKey;
extern GCKeyCode lastRemappedKey;

// --- UI / POPUP ---
extern BOOL isPopupVisible;
extern UIWindow *popupWindow;
extern void (^keyCaptureCallback)(GCKeyCode keyCode);
extern void (^mouseButtonCaptureCallback)(int buttonCode);

// --- INDICATORS ---
extern BOOL isBorderlessModeEnabled;
extern UIView *blueDotIndicator;
extern CGPoint blueDotPosition;

extern GCKeyCode TRIGGER_KEY;
extern GCKeyCode POPUP_KEY;

extern GCKeyCode TRIGGER_KEY;
extern GCKeyCode POPUP_KEY;

// Custom mouse codes
#define MOUSE_BUTTON_MIDDLE 10001
#define MOUSE_BUTTON_AUX_BASE 10002
#define MOUSE_BUTTON_AUX_MAX 10031
#define MOUSE_BUTTON_LEFT  10050
#define MOUSE_BUTTON_RIGHT 10051
#define MOUSE_SCROLL_UP 10100
#define MOUSE_SCROLL_DOWN 10101
#define MOUSE_SCROLL_LEFT 10102
#define MOUSE_SCROLL_RIGHT 10103

#ifdef __cplusplus
extern "C" {
#endif
void recalculateSensitivities(void);
void loadKeyRemappings(void);
void saveKeyRemappings(void);
void loadControllerMappings(void);
void saveControllerMappings(void);
void recookVCtrlRemappings(void);
void loadFortniteKeybinds(void);
void loadFortniteKeybinds(void);
void createBlueDotIndicator(void);
void updateBlueDotVisibility(void);
void resetBlueDotPosition(void);
void showPopupOnQuickStartTab(void);
void updateBorderlessMode(void);
#ifdef __cplusplus
}
#endif

static inline GCKeyCode getRemappedKey(GCKeyCode keyCode, BOOL *isRemapped) {
  extern GCKeyCode lastLookupKey;
  extern GCKeyCode lastRemappedKey;
  extern GCKeyCode keyRemapArray[512];
  if (keyCode == lastLookupKey) {
    if (isRemapped) *isRemapped = (lastRemappedKey != 0);
    return lastRemappedKey != 0 ? lastRemappedKey : keyCode;
  }
  GCKeyCode remapped = (keyCode < 256) ? keyRemapArray[keyCode] : 0;
  lastLookupKey = keyCode;
  lastRemappedKey = remapped;
  if (remapped != 0) {
    if (isRemapped) *isRemapped = YES;
    return remapped;
  } else {
    if (isRemapped) *isRemapped = NO;
    return keyCode;
  }
}
