// =============================================================================
//  popupViewController.h — FnMacTweak
//  Public interface for the floating settings panel that appears when the
//  user presses P in-game.
//
//  The panel is a UIWindow (popupWindow in globals.h) containing this
//  view controller as its rootViewController. It has five tabs:
//
//    Sensitivity  — Adjust PC-formula sensitivity values
//    Key Remap    — Assign Fortnite action keybinds + advanced custom remaps
//    Build Mode   — Toggle build mode and manage the red dot crosshair
//    Container    — Grant access to the Fortnite data folder
//    Quick Start  — In-app tutorial video with liquid glass player
//
//  CONTRIBUTING: Add new tabs by:
//    1. Adding a case to the PopupTab enum below.
//    2. Creating the tab's UIView in popupViewController.m.
//    3. Adding a tab button to the segmented control.
//    4. Wiring the tab button → switchToTab: in popupViewController.m.
// =============================================================================

#import <UIKit/UIKit.h>

// Enum used to identify which tab is currently active.
// Pass these values to -switchToTab: from external callers.
typedef NS_ENUM(NSInteger, PopupTab) {
    PopupTabSensitivity = 0,   // Sensitivity sliders / input fields
    PopupTabKeyRemap    = 1,   // Keybind assignment (Fortnite actions + custom remaps)
    PopupTabBuildMode   = 2,   // Build Mode toggle and red dot configuration
    PopupTabContainer   = 3,   // Data folder access + settings import/export
    PopupTabQuickStart  = 4,   // Tutorial video popup
};

@interface popupViewController : UIViewController <UITextFieldDelegate, UIDocumentPickerDelegate>

// ── Tab content views ─────────────────────────────────────────────────────────
// Each tab is a plain UIView that is shown/hidden when the user switches tabs.
// All layout is done in code (no Storyboards or Xibs).
@property (nonatomic, strong) UIView *sensitivityTab;
@property (nonatomic, strong) UIView *keyRemapTab;
@property (nonatomic, strong) UIView *buildModeTab;
@property (nonatomic, strong) UIView *containerTab;
@property (nonatomic, strong) UIView *quickStartTab;

// ── Tab bar buttons ───────────────────────────────────────────────────────────
@property (nonatomic, strong) UIButton *sensitivityTabButton;
@property (nonatomic, strong) UIButton *keyRemapTabButton;
@property (nonatomic, strong) UIButton *buildModeTabButton;
@property (nonatomic, strong) UIButton *containerTabButton;
@property (nonatomic, strong) UIButton *quickStartTabButton;

// Sliding indicator beneath the active tab button
@property (nonatomic, strong) UIView *tabIndicator;

// Outer container for the segmented tab bar
@property (nonatomic, strong) UIView *segmentedContainer;

// Tracks which tab is currently visible
@property (nonatomic, assign) PopupTab currentTab;

// ── Staged keybind system ─────────────────────────────────────────────────────
// Keybind changes are collected here and only written to NSUserDefaults when
// the user taps "Apply". This prevents partial saves mid-edit.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *stagedKeybinds;

// ── Action buttons (Key Remap tab) ────────────────────────────────────────────
@property (nonatomic, strong) UIButton *applyChangesButton;      // Commits staged keybinds
@property (nonatomic, strong) UIButton *discardKeybindsButton;   // Discards staged keybinds

// ── Action buttons (Sensitivity tab) ─────────────────────────────────────────
@property (nonatomic, strong) UIButton *discardSensitivityButton;
@property (nonatomic, strong) UIButton *applySensitivityButton;

// ── External navigation ───────────────────────────────────────────────────────

/**
 * Switches the panel to the Quick Start tab.
 * Called from Tweak.xm's showPopupOnQuickStartTab() after the welcome screen's
 * "Continue" button is tapped, landing new users on the tutorial.
 */
- (void)switchToQuickStartTab;

@end
