#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <stdint.h>

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
extern uint32_t g_vctrlReverseMap[10240];
extern uint32_t g_vctrlCustomMap[10240];
extern uint32_t g_vctrlSuppressionMap[10240];
extern id g_virtualController;
extern BOOL isControllerModeEnabled;
typedef void (^FnGCMouseMovedHandler)(id mouse, float deltaX, float deltaY);
extern FnGCMouseMovedHandler g_originalMouseHandler;
extern BOOL isTypingModeEnabled;
extern id storedKeyboardInput;
extern void (^storedKeyboardHandler)(id, id, GCKeyCode, BOOL);
extern BOOL wasADSInitialized;
extern id g_capturedMouseInput;
extern int ignoreNextLeftClickCount;

// LEVEL 27: God-Mode (Cache-Aligned Quantum State)
// This ensures that all critical orientation data resides in a single 
// 128-byte L1 Cache Line to eliminate nanosecond memory stalls.
typedef struct __attribute__((aligned(128))) {
    _Atomic float pitch;
    _Atomic float yaw;
    _Atomic float roll;
    
    _Atomic float lastPitch;
    _Atomic float lastYaw;
    _Atomic uint64_t lastTimestamp;
    
    _Atomic BOOL enabled;
} FnGodModeState;

extern FnGodModeState g_godReflex;

extern BOOL isMouseLocked;
extern BOOL isGCMouseDirectActive;
extern BOOL isPopupVisible;

#include <stdatomic.h>
extern _Atomic double mouseAccumBufferX[2];
extern _Atomic double mouseAccumBufferY[2];
extern _Atomic uint64_t mouseHardwareTimestamp[2];
extern _Atomic int activeBufferIdx;
extern _Atomic uint64_t g_lastGyroPollTime;

// LEVEL 24: Quantum Counters (Absolute 0)
extern _Atomic double g_quantumPushedX;
extern _Atomic double g_quantumPushedY;

#ifdef __cplusplus
extern "C" {
#endif
extern void elevateThreadToRealTime();
#ifdef __cplusplus
}
#endif

extern BOOL leftButtonIsPressed;
extern BOOL rightButtonIsPressed;
extern BOOL middleButtonIsPressed;

static inline void atomic_add_double(_Atomic double *var, double val) {
    double old = atomic_load(var);
    while (!atomic_compare_exchange_weak(var, &old, old + val));
}

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
extern void * g_hidManager;
extern float HID_SENSITIVITY_SCALAR;
extern void (^mouseButtonCaptureCallback)(int buttonCode);

// --- INDICATORS ---
extern BOOL isBorderlessModeEnabled;
extern UIView *blueDotIndicator;
extern CGPoint blueDotPosition;

extern GCKeyCode TRIGGER_KEY;
extern GCKeyCode POPUP_KEY;

extern GCKeyCode POPUP_KEY;
extern dispatch_queue_t g_vctrl_queue;

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
void loadTweakSettings(void);
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
int getControllerDefaultMapping(int btnIdx);
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
