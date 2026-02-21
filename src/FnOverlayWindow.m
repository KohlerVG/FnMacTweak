// =============================================================================
//  FnOverlayWindow.m — FnMacTweak
// =============================================================================

#import "FnOverlayWindow.h"
#import <UIKit/UIKit.h>

@implementation FnOverlayWindow

- (BOOL)canBecomeKeyWindow {
    return NO;  // Never steal key window status from the game
}

// Belt-and-suspenders: if UIKit somehow asks our VC anyway, say NO
- (BOOL)prefersPointerLocked {
    return NO;
}

// When this overlay becomes visible or is interacted with, UIKit may try to
// shift window focus. We override becomeKeyWindow to immediately hand it back
// to the game window — finding the lowest-level window (the game) and making
// it key again. This keeps cursor lock attached to the game at all times.
- (void)becomeKeyWindow {
    // Do NOT call [super becomeKeyWindow] — we never want to actually be key.
    // Instead, find the game window (lowest windowLevel, not an FnOverlayWindow)
    // and synchronously restore its key status.
    UIWindowScene *scene = (UIWindowScene *)self.windowScene;
    if (!scene) return;

    UIWindow *gameWindow = nil;
    for (UIWindow *w in scene.windows) {
        if (w == self) continue;
        if (![w isKindOfClass:[FnOverlayWindow class]]) {
            if (!gameWindow || w.windowLevel < gameWindow.windowLevel) {
                gameWindow = w;
            }
        }
    }

    if (gameWindow) {
        // makeKeyWindow must run synchronously so the pointer-lock query
        // from UIKit always hits IOSViewController, never our overlay VC.
        // Dispatch to main queue only if we're somehow off-thread.
        if ([NSThread isMainThread]) {
            [gameWindow makeKeyWindow];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [gameWindow makeKeyWindow];
            });
        }
    }
}

// resignKeyWindow is called when UIKit moves key status away from this window.
// Nothing to do — we never actually held key status, so no cleanup needed.
- (void)resignKeyWindow {
    // Intentionally empty — don't call super so UIKit doesn't log spurious warnings.
}

// hitTest passthrough: if a touch hits a non-interactive area of our overlay
// window, return nil so the event falls through to the game window below.
// This prevents the overlay from swallowing cursor-lock-related hit tests
// that UIKit performs on the key window candidate.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // If the hit view is our own window root (no interactive subview was hit),
    // return nil so input passes through to the game window.
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}

@end
