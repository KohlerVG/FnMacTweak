#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

// For spoofing device specifications
#define DEVICE_MODEL "iPad17,4"
#define OEM_ID "A3361"

// Setting keys
#define kSettingsKey @"fnmactweak.settings"
#define kBaseXYKey @"baseXYSensitivity"
#define kLookXKey @"lookSensitivityX"
#define kLookYKey @"lookSensitivityY"
#define kScopeXKey @"scopeSensitivityX"
#define kScopeYKey @"scopeSensitivityY"
#define kScaleKey @"macOSToPCScale"
#define kInvertYKey @"invertYAxis"
#define kKeyRemapKey @"keyRemappings"
#define kBuildModeKey @"buildModeEnabled"
#define kRedDotPositionKey @"redDotPosition"

// Key for hiding/revealing mouse pointer
extern GCKeyCode TRIGGER_KEY;
extern GCKeyCode POPUP_KEY;

// Custom mouse button codes (using high values that won't conflict with GCKeyCode)
// These are our own definitions for mouse buttons
#define MOUSE_BUTTON_MIDDLE    10001
#define MOUSE_BUTTON_SIDE1     10002  // Mouse button 4
#define MOUSE_BUTTON_SIDE2     10003  // Mouse button 5
#define MOUSE_SCROLL_UP        10004
#define MOUSE_SCROLL_DOWN      10005

// Fortnite PC sensitivity settings
// Match your exact PC Fortnite settings here
// Optimal: 6.4% base × 45% look/scope × 34.72 scale = 1.0 effective
extern float BASE_XY_SENSITIVITY;         // X/Y-Axis Sensitivity (standard: 6.4%)
extern float LOOK_SENSITIVITY_X;          // Look Sensitivity X - Hip-fire (standard: 45%)
extern float LOOK_SENSITIVITY_Y;          // Look Sensitivity Y - Hip-fire (standard: 45%)
extern float SCOPE_SENSITIVITY_X;         // Scope Sensitivity X - ADS (standard: 45%)
extern float SCOPE_SENSITIVITY_Y;         // Scope Sensitivity Y - ADS (standard: 45%)
extern BOOL INVERT_Y_AXIS;                // Invert vertical camera look

// macOS to PC conversion scale
extern float MACOS_TO_PC_SCALE;           // Conversion factor (optimal: 34.72 for 1.0 effective)

// Pre-calculated sensitivities for performance optimization
extern double hipSensitivityX;
extern double hipSensitivityY;
extern double adsSensitivityX;
extern double adsSensitivityY;

// Key remapping storage
// Maps GCKeyCode (source) -> GCKeyCode (target)
extern NSMutableDictionary<NSNumber*, NSNumber*>* keyRemappings; // For UI display
extern GCKeyCode keyRemapArray[256]; // Advanced Custom Remaps - ultra-fast lookup (0 = no remap, -1 = blocked)
extern GCKeyCode fortniteRemapArray[256]; // Fortnite Keybinds - ultra-fast lookup (0 = no remap)
extern uint8_t fortniteBlockedDefaults[256]; // Blocked default keys (1 = blocked, 0 = allowed)
extern GCKeyCode lastLookupKey;      // Cache for last remapping lookup
extern GCKeyCode lastRemappedKey;    // Cache for last remapped result

// Keyboard handler
extern GCKeyboardValueChangedHandler keyboardChangedHandler;
extern BOOL isMouseLocked;
extern BOOL isAlreadyFocused;

// BUILD mode setting
extern BOOL isBuildModeEnabled;

// Red dot target indicator for BUILD mode
extern UIView *redDotIndicator;
extern CGPoint redDotTargetPosition;  // Position of the red dot target
extern BOOL isRedDotDragging;

// UI and popup stuff
extern UIWindow *popupWindow;
extern BOOL isPopupVisible;

// Key capture callback for popup
// When popup is waiting for key press, this will be called from Tweak.xm
extern void (^keyCaptureCallback)(GCKeyCode keyCode);

// Mouse button capture callback (uses same type but with our custom codes)
extern void (^mouseButtonCaptureCallback)(int buttonCode);

// Function to recalculate pre-computed sensitivities (call after settings change)
#ifdef __cplusplus
extern "C" {
#endif
void recalculateSensitivities(void);
void loadKeyRemappings(void);
void saveKeyRemappings(void);
void loadFortniteKeybinds(void);  // Load Fortnite keybinds into fast array
void saveFortniteKeybinds(void);   // Persists Fortnite keybinds to NSUserDefaults
void updateRedDotVisibility(void);
void createRedDotIndicator(void);
void resetRedDotPosition(void);
void showPopupOnQuickStartTab(void);
#ifdef __cplusplus
}
#endif

// Ultra-fast inline remapping function
// This is in the header so it can be inlined at the call site for zero overhead
static inline GCKeyCode getRemappedKey(GCKeyCode keyCode, BOOL *isRemapped) {
    extern GCKeyCode lastLookupKey;
    extern GCKeyCode lastRemappedKey;
    extern GCKeyCode keyRemapArray[256];
    
    // Fast path: check cache for repeated key events (key repeats/releases)
    if (keyCode == lastLookupKey) {
        if (isRemapped) *isRemapped = (lastRemappedKey != 0);
        return lastRemappedKey != 0 ? lastRemappedKey : keyCode;
    }
    
    // Direct array lookup - this is the magic
    // Overhead: 1 array access = ~2 nanoseconds
    GCKeyCode remapped = (keyCode < 256) ? keyRemapArray[keyCode] : 0;
    
    // Update cache
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
