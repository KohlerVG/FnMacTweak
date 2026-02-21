// =============================================================================
//  welcomeViewController.h — FnMacTweak
//  Public interface for the first-launch welcome / onboarding screen.
//
//  This view controller is presented the first time the user launches Fortnite
//  after installing the tweak. It plays a short tutorial video explaining the
//  basic controls and hotkeys, then offers a "Continue" button that opens the
//  settings panel directly on the Quick Start tab.
//
//  The screen is shown at most once: a flag in NSUserDefaults prevents it from
//  appearing again after the user dismisses it.
//
//  See showWelcomePopupIfNeeded() in Tweak.xm for the display logic.
// =============================================================================

#import <UIKit/UIKit.h>

@interface welcomeViewController : UIViewController

@end

#ifdef __cplusplus
extern "C" {
#endif

void showWelcomePopupIfNeeded(void);

#ifdef __cplusplus
}
#endif
