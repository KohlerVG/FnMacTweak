// =============================================================================
//  FnOverlayWindow.h — FnMacTweak
//  A UIWindow subclass that can never become the key window.
//
//  All overlay windows (settings popup, welcome screen, video player) use this
//  instead of plain UIWindow. By returning NO from canBecomeKeyWindow, we
//  guarantee the game window always stays key — so UIKit always queries
//  IOSViewController for prefersPointerLocked, and pointer lock is stable
//  regardless of how many overlays are shown or hidden.
// =============================================================================

#import <UIKit/UIKit.h>

@interface FnOverlayWindow : UIWindow
@end
