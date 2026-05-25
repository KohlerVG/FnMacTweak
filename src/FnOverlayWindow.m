// =============================================================================
//  FnOverlayWindow.m — FnMacTweak
// =============================================================================

#import "FnOverlayWindow.h"
#import <UIKit/UIKit.h>

@implementation FnOverlayWindow

static FnOverlayWindow *_sharedOverlay = nil;

+ (instancetype)sharedInstance {
    return _sharedOverlay;
}

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene {
    self = [super initWithWindowScene:windowScene];
    if (self) {
        _sharedOverlay = self;
    }
    return self;
}

- (void)setOverlayVisible:(BOOL)visible {
    // LEVEL 17: GPU Render-Guard
    // When hidden, we set the 'hidden' property to YES.
    // This tells the Metal compositor to completely bypass this window.
    self.hidden = !visible;
    if (visible) {
        [self makeKeyAndVisible];
    }
}

- (BOOL)canBecomeKeyWindow {
    extern BOOL isPopupVisible;
    return isPopupVisible;  // Allow keyboard input when popup is open
}

// Belt-and-suspenders: if UIKit somehow asks our VC anyway, say NO
- (BOOL)prefersPointerLocked {
    return NO;
}

- (void)becomeKeyWindow {
    extern BOOL isPopupVisible;
    if (isPopupVisible) {
        [super becomeKeyWindow];
        return;
    }
    
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
- (void)resignKeyWindow {
    [super resignKeyWindow];
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
