#import "./views/popupViewController.h"
#import "./views/welcomeViewController.h"
#import "./globals.h"

#import "../lib/fishhook.h"
#import <sys/sysctl.h>

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

// Pre-calculated sensitivity multipliers (computed once at startup via recalculateSensitivities())
// Formula: (BASE_XY_SENSITIVITY / 100) × (Look% / 100) × MACOS_TO_PC_SCALE

void updateBorderlessMode() {

    @try {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        
        Class nsAppClass = NSClassFromString(@"NSApplication");
        if (!nsAppClass) { return; }
        
        id sharedApp = [nsAppClass performSelector:NSSelectorFromString(@"sharedApplication")];
        NSArray *windows = [sharedApp performSelector:NSSelectorFromString(@"windows")];
        Class nsWindowClass = NSClassFromString(@"NSWindow");

        for (id window in windows) {
            // Safety: Only touch actual NSWindow instances
            if (!nsWindowClass || ![window isKindOfClass:nsWindowClass]) continue;
            
            // 1. Style Mask (NSWindowStyleMaskFullSizeContentView = 1 << 15)
            NSUInteger currentMask = [[window valueForKey:@"styleMask"] unsignedIntegerValue];
            NSUInteger fullSizeMask = (1ULL << 15);
            NSUInteger newMask = isBorderlessModeEnabled ? (currentMask | fullSizeMask) : (currentMask & ~fullSizeMask);
            
            if (currentMask != newMask) {
                [window setValue:@(newMask) forKey:@"styleMask"];
            }

            // 2. Title Bar Transparency & Visibility
            if ([window respondsToSelector:NSSelectorFromString(@"setTitlebarAppearsTransparent:")]) {
                [window setValue:@(isBorderlessModeEnabled) forKey:@"titlebarAppearsTransparent"];
            }
            if ([window respondsToSelector:NSSelectorFromString(@"setTitleVisibility:")]) {
                [window setValue:@(isBorderlessModeEnabled ? 1 : 0) forKey:@"titleVisibility"];
            }
            
            // 3. Traffic Lights (Explicit Button Hiding)
            SEL buttonSel = NSSelectorFromString(@"standardWindowButton:");
            if ([window respondsToSelector:buttonSel]) {
                for (NSInteger i = 0; i <= 2; i++) { // 0=Close, 1=Min, 2=Zoom
                    // Use objc_msgSend for the specific type (NSWindowButton is NSInteger)
                    typedef id (*ButtonFunc)(id, SEL, NSInteger);
                    ButtonFunc getButton = (ButtonFunc)objc_msgSend;
                    id btn = getButton(window, buttonSel, i);

                    if (btn && [btn respondsToSelector:NSSelectorFromString(@"setHidden:")]) {
                        [btn setValue:@(isBorderlessModeEnabled) forKey:@"hidden"];
                    }
                }

                // Titlebar Container (Super-view of close button)
                typedef id (*ButtonFunc)(id, SEL, NSInteger);
                id closeBtn = ((ButtonFunc)objc_msgSend)(window, buttonSel, 0);
                if (closeBtn) {
                    id container = [closeBtn valueForKey:@"superview"];
                    if (container && [container respondsToSelector:NSSelectorFromString(@"setHidden:")]) {
                        [container setValue:@(isBorderlessModeEnabled) forKey:@"hidden"];
                    }
                }
            }

            // 4. Positioning
                if (isBorderlessModeEnabled) {
                    // Borderless: Manual center using visibleFrame (excludes macOS menu bar).
                    // [NSWindow center] uses the full screen frame which causes a vertical
                    // offset because macOS has a bottom-left origin and the menu bar eats
                    // into the top. We also wait 100ms (up from 50ms) so the title bar
                    // hide animation fully settles before we read the window's final size.
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        id screen = [window valueForKey:@"screen"];
                        if (screen) {
                            NSValue *visibleFrameVal = [screen valueForKey:@"visibleFrame"];
                            CGRect visibleFrame = visibleFrameVal ? [visibleFrameVal CGRectValue] : CGRectZero;
                            CGRect windowFrame = [[window valueForKey:@"frame"] CGRectValue];

                            if (!CGRectIsEmpty(visibleFrame) && !CGRectIsEmpty(windowFrame)) {
                                CGRect targetFrame = windowFrame;
                                targetFrame.origin.x = visibleFrame.origin.x + (visibleFrame.size.width  - windowFrame.size.width)  / 2.0;
                                targetFrame.origin.y = visibleFrame.origin.y + (visibleFrame.size.height - windowFrame.size.height) / 2.0;

                                NSMethodSignature *sig = [window methodSignatureForSelector:NSSelectorFromString(@"setFrame:display:")];
                                if (sig) {
                                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                                    [inv setSelector:NSSelectorFromString(@"setFrame:display:")];
                                    [inv setTarget:window];
                                    [inv setArgument:&targetFrame atIndex:2];
                                    BOOL display = YES;
                                    [inv setArgument:&display atIndex:3];
                                    [inv invoke];
                                }
                            }
                        }
                    });
                } else {
                    // Bordered: Top-Aligned Centering
                    id screen = [window valueForKey:@"screen"];
                    if (screen) {
                        CGRect screenFrame = [[screen valueForKey:@"frame"] CGRectValue];
                        CGRect windowFrame = [[window valueForKey:@"frame"] CGRectValue];
                        
                        CGRect targetFrame = windowFrame;
                        targetFrame.origin.x = screenFrame.origin.x + (screenFrame.size.width - windowFrame.size.width) / 2.0;
                        targetFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - windowFrame.size.height;

                        NSMethodSignature *sig = [window methodSignatureForSelector:NSSelectorFromString(@"setFrame:display:")];
                        if (sig) {
                            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                            [inv setSelector:NSSelectorFromString(@"setFrame:display:")];
                            [inv setTarget:window];
                            [inv setArgument:&targetFrame atIndex:2];
                            BOOL display = YES;
                            [inv setArgument:&display atIndex:3];
                            [inv invoke];
                        }
                    }
                }

            if ([window respondsToSelector:NSSelectorFromString(@"setMovableByWindowBackground:")]) {
                [window setValue:@YES forKey:@"movableByWindowBackground"];
            }
        }
        
        // UIKit Override: Kill safe areas
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *uiWin in [[UIApplication sharedApplication] windows]) {
        #pragma clang diagnostic pop
            UIView *rootView = uiWin.rootViewController.view;
            if (rootView && [rootView respondsToSelector:@selector(setInsetsLayoutMarginsFromSafeArea:)]) {
                typedef void (*SetInsetsFunc)(id, SEL, BOOL);
                ((SetInsetsFunc)objc_msgSend)(rootView, @selector(setInsetsLayoutMarginsFromSafeArea:), !isBorderlessModeEnabled);
            }
        }
        #pragma clang diagnostic pop
    } @catch (NSException *exception) {
    }
}

// --------- MOUSE FRACTIONAL ACCUMULATION ---------
static double mouseAccumX = 0.0;
static double mouseAccumY = 0.0;
static BOOL wasADS = NO;
static BOOL wasADSInitialized = NO;

// --------- SCROLL ACCUMULATION ---------
// macOS delivers integer deltas with acceleration per scroll event.
// We clamp to 1 tick per event and reset GCKit's cache after each one
// so consecutive same-direction ticks always fire.

// --------- KEYBOARD HANDLER REFERENCE ---------
// Stored once when GCKeyboardInput hook fires — used to synthesize key events
// from mouse buttons and scroll wheel remaps.
static GCKeyboardInput *storedKeyboardInput = nil;
static GCKeyboardValueChangedHandler storedKeyboardHandler = nil;

// --------- DEVICE SPOOFING ---------
// Intercepts sysctl/sysctlbyname to report DEVICE_MODEL and OEM_ID,
// making Fortnite treat this Mac as a supported iOS device.
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;

static int pt_sysctl(int *name, u_int namelen, void *buf, size_t *size, void *arg0, size_t arg1) {
    if (name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_PRODUCT)) {
        if (buf == NULL) {
            *size = strlen(DEVICE_MODEL) + 1;
        } else {
            if (*size > strlen(DEVICE_MODEL)) {
                strcpy((char *)buf, DEVICE_MODEL);
            } else {
                return ENOMEM;
            }
        }
        return 0;
    } else if (name[0] == CTL_HW && name[1] == HW_TARGET) {
        if (buf == NULL) {
            *size = strlen(OEM_ID) + 1;
        } else {
            if (*size > strlen(OEM_ID)) {
                strcpy((char *)buf, OEM_ID);
            } else {
                return ENOMEM;
            }
        }
        return 0;
    }
    return orig_sysctl(name, namelen, buf, size, arg0, arg1);
}

static int pt_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if ((strcmp(name, "hw.machine") == 0) || (strcmp(name, "hw.product") == 0) || (strcmp(name, "hw.model") == 0)) {
        if (oldp == NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (oldlenp && *oldlenp < strlen(DEVICE_MODEL) + 1) {
                *oldlenp = strlen(DEVICE_MODEL) + 1;
            }
            return ret;
        } else if (oldp != NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            const char *machine = DEVICE_MODEL;
            strncpy((char *)oldp, machine, strlen(machine));
            ((char *)oldp)[strlen(machine)] = '\0';
            if (oldlenp) *oldlenp = strlen(machine) + 1;
            return ret;
        }
    } else if (strcmp(name, "hw.target") == 0) {
        if (oldp == NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (oldlenp && *oldlenp < strlen(OEM_ID) + 1) {
                *oldlenp = strlen(OEM_ID) + 1;
            }
            return ret;
        } else if (oldp != NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            const char *machine = OEM_ID;
            strncpy((char *)oldp, machine, strlen(machine));
            ((char *)oldp)[strlen(machine)] = '\0';
            if (oldlenp) *oldlenp = strlen(machine) + 1;
            return ret;
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// --------- CONSTRUCTOR ---------

// Category to add pan gesture handling to the red dot indicator
@interface UIView (RedDotDragging)
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIView (RedDotDragging)
- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        isRedDotDragging = YES;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.superview];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        
        // Keep within screen bounds
        CGRect bounds = self.superview.bounds;
        newCenter.x = MAX(10, MIN(bounds.size.width - 10, newCenter.x));
        newCenter.y = MAX(10, MIN(bounds.size.height - 10, newCenter.y));
        
        self.center = newCenter;
        redDotTargetPosition = newCenter;
        [gesture setTranslation:CGPointZero inView:self.superview];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        isRedDotDragging = NO;
        
        // Save the red dot position to UserDefaults
        NSDictionary *positionDict = @{
            @"x": @(redDotTargetPosition.x),
            @"y": @(redDotTargetPosition.y)
        };
        [[NSUserDefaults standardUserDefaults] setObject:positionDict forKey:kRedDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}
@end

%ctor {
    // Fishhook for device spoofing
    struct rebinding rebindings[] = {
        {"sysctl", (void *)pt_sysctl, (void **)&orig_sysctl},
        {"sysctlbyname", (void *)pt_sysctlbyname, (void **)&orig_sysctlbyname}
    };
    rebind_symbols(rebindings, 2);

    NSString* currentVersion = @"3.0.0";
    NSString* lastVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.lastSeenVersion"];

    if (!lastVersion || ![lastVersion isEqualToString:currentVersion]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kKeyRemapKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSeenVersion"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSuppressed"];
        [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"fnmactweak.lastSeenVersion"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    isBuildModeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kBuildModeKey];

    NSData *bookmark = [[NSUserDefaults standardUserDefaults] dataForKey:@"fnmactweak.datafolder"];
    if (bookmark) {
        BOOL stale = NO;
        NSError *error = nil;
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
                                               options:NSURLBookmarkResolutionWithoutUI
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:&error];
        if (url) {
            [url startAccessingSecurityScopedResource];
        }
    }

    TRIGGER_KEY = GCKeyCodeLeftAlt;
    POPUP_KEY = GCKeyCodeKeyP;
    
    NSDictionary *savedSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSettingsKey];
    if (savedSettings) {
        float v;
        v = [savedSettings[kBaseXYKey] floatValue]; if (v > 0) BASE_XY_SENSITIVITY = v;
        v = [savedSettings[kLookXKey]  floatValue]; if (v > 0) LOOK_SENSITIVITY_X  = v;
        v = [savedSettings[kLookYKey]  floatValue]; if (v > 0) LOOK_SENSITIVITY_Y  = v;
        v = [savedSettings[kScopeXKey] floatValue]; if (v > 0) SCOPE_SENSITIVITY_X = v;
        v = [savedSettings[kScopeYKey] floatValue]; if (v > 0) SCOPE_SENSITIVITY_Y = v;
        v = [savedSettings[kScaleKey]  floatValue]; if (v > 0) MACOS_TO_PC_SCALE   = v;
    }

    recalculateSensitivities();
    loadKeyRemappings();
    loadFortniteKeybinds();

    showWelcomePopupIfNeeded();

    isBorderlessModeEnabled = [tweakDefaults() boolForKey:kBorderlessWindowKey];
    // The NSWindow hook handles styling before the window appears.
    // For positioning, we listen for the window becoming key — this fires once
    // the window is fully on screen and settled, with no race condition.
    // We unregister immediately after the first fire so it never runs again.
    if (isBorderlessModeEnabled) {
        id __block observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSNotificationName(@"NSWindowDidBecomeKeyNotification")
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;
                        updateBorderlessMode();
                    }];
    }

    // ─────────────────────────────────────────────────────────────────────
    // Bypasses GCKit entirely to catch true hardware scroll ticks.
    Class nsEventClass = NSClassFromString(@"NSEvent");
    if (nsEventClass) {
        // Use performSelector since we don't have AppKit headers imported.
        // Equivalent to:
        // [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:...]
        // NSEventMaskScrollWheel = 1ULL << 22
        unsigned long long scrollMask = 1ULL << 22;
        
        // Cache the SEL once — NSSelectorFromString does a string hash lookup,
        // no need to repeat it on every scroll event.
        static SEL scrollingDeltaYSel = NULL;
        if (!scrollingDeltaYSel) scrollingDeltaYSel = NSSelectorFromString(@"scrollingDeltaY");

        id (^handlerBlock)(id) = ^id (id event) {
            // Use objc_msgSend directly — avoids NSInvocation alloc on every scroll tick.
            if (![event respondsToSelector:scrollingDeltaYSel]) return event;
            CGFloat deltaY = ((CGFloat(*)(id, SEL))objc_msgSend)(event, scrollingDeltaYSel);

            if (deltaY == 0) return event;

            // macOS deltaY is positive for UP, negative for DOWN
            int scrollCode = (deltaY > 0) ? MOUSE_SCROLL_UP : MOUSE_SCROLL_DOWN;
            int idx = scrollCode - MOUSE_SCROLL_UP;
            
            GCKeyCode kc = (idx >= 0 && idx < MOUSE_SCROLL_COUNT) ? mouseScrollRemapArray[idx] : 0;
            // Fall back to Fortnite default keybind if no advanced remap is set
            if (kc == 0 && idx >= 0 && idx < MOUSE_SCROLL_COUNT)
                kc = mouseScrollFortniteArray[idx];
            
            // PRIORITY 1: Handle User UI overrides (Capture Mode)
            // Even if the mouse is unlocked (we are in the Tweak Settings Menu),
            // this needs to be able to catch the scroll direction!
            if (mouseButtonCaptureCallback != nil) {
                mouseButtonCaptureCallback(scrollCode);
                return nil;
            }

            // If a keybind is mapped for this scroll direction, ALWAYS consume the
            // hardware event — never let raw scroll reach GCKit even when unlocked.
            // Exception: if the P settings panel is open, let scroll through so the
            // user can scroll inside the popup normally.
            if (kc != 0 && !isPopupVisible) {
                if (isMouseLocked && storedKeyboardHandler && storedKeyboardInput) {
                    GCControllerButtonInput *dummyBtn = [storedKeyboardInput buttonForKeyCode:GCKeyCodeKeyA];
                    storedKeyboardHandler(storedKeyboardInput, dummyBtn, kc, YES);
                    storedKeyboardHandler(storedKeyboardInput, dummyBtn, kc, NO);
                }
                return nil; // consume in all cases — no raw scroll bleed-through
            }

            // No keybind — normal scroll behavior requires lock + handlers
            if (!isMouseLocked || !storedKeyboardHandler || !storedKeyboardInput) return event;

            // PRIORITY 3: Handle Raw Unmapped Game Scroll (Zero Delay)
            // Only reached when kc == 0 for this direction.
            // Check only this direction — don't block the other unbound direction.
            if (idx >= 0 && idx < MOUSE_SCROLL_COUNT) {
                if (mouseScrollRemapArray[idx] != 0 || mouseScrollFortniteArray[idx] != 0) return nil;
            }

            GCMouse *currentMouse = GCMouse.current;
            if (currentMouse && currentMouse.mouseInput) {
                GCControllerDirectionPad *scrollPad = currentMouse.mouseInput.scroll;
                if (scrollPad && scrollPad.valueChangedHandler) {
                    float yVal = (deltaY > 0) ? 1.0f : -1.0f;
                    
                    // Dispatch directly to the game synchronously
                    scrollPad.valueChangedHandler(scrollPad, 0.0f, yVal);
                    
                    // Reset internal state to ensure game logic doesn't drop it internally
                    if ([scrollPad.yAxis respondsToSelector:@selector(setValue:)]) {
                        [scrollPad.yAxis setValue:0.0f];
                    }
                    
                    // Send an immediate center (0.0) tick so the game engine recognizes
                    // it as a distinct discrete toggle rather than a held input.
                    scrollPad.valueChangedHandler(scrollPad, 0.0f, 0.0f);
                }
            }

            // Consume the original GCKit event off the native layer so we don't double-fire
            return nil;
        };
        
        SEL addMonitorSel = NSSelectorFromString(@"addLocalMonitorForEventsMatchingMask:handler:");
        if ([nsEventClass respondsToSelector:addMonitorSel]) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[nsEventClass methodSignatureForSelector:addMonitorSel]];
            [inv setSelector:addMonitorSel];
            [inv setTarget:nsEventClass];
            
            [inv setArgument:&scrollMask atIndex:2];
            
            id blockArg = [handlerBlock copy];
            [inv setArgument:&blockArg atIndex:3];
            
            [inv invoke];
        }
    }
}

// --------- HELPER FUNCTIONS ---------

static inline CGFloat PixelAlign(CGFloat value) {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    CGFloat scale = scene.screen.scale ?: 2.0;
    return round(value * scale) / scale;
}

static void createPopup() {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    popupWindow = [[UIWindow alloc] initWithWindowScene:scene];

    CGFloat popupW = PixelAlign(330.0);
    CGFloat popupH = PixelAlign(600.0);
    CGRect screen = scene ? scene.screen.bounds : CGRectMake(0, 0, 390, 844);
    CGFloat centeredY = PixelAlign((screen.size.height - popupH) / 2.0);

    popupWindow.frame = CGRectMake(PixelAlign(100.0), centeredY, popupW, popupH);
    popupWindow.windowLevel = UIWindowLevelAlert + 1;
    popupWindow.backgroundColor = [UIColor clearColor];
    
    popupViewController *popupVC = [popupViewController new];
    popupWindow.rootViewController = popupVC;
}

void showPopupOnQuickStartTab(void) {
    if (!popupWindow) createPopup();
    isPopupVisible = YES;
    popupWindow.hidden = NO;
    popupViewController *vc = (popupViewController *)popupWindow.rootViewController;
    if ([vc respondsToSelector:@selector(switchToQuickStartTab)]) {
        [vc switchToQuickStartTab];
    }
}

void createRedDotIndicator() {
    if (redDotIndicator) return;
    
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    if (!scene) return;
    
    redDotIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    redDotIndicator.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.8];
    redDotIndicator.layer.cornerRadius = 10;
    redDotIndicator.layer.borderWidth = 2;
    redDotIndicator.layer.borderColor = [UIColor whiteColor].CGColor;
    redDotIndicator.hidden = YES;
    redDotIndicator.userInteractionEnabled = YES;
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:redDotIndicator action:nil];
    __weak UIView *weakDot = redDotIndicator;
    [panGesture addTarget:weakDot action:@selector(handlePan:)];
    [redDotIndicator addGestureRecognizer:panGesture];
    
    UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
    if (keyWindow) {
        [keyWindow addSubview:redDotIndicator];
        
        CGRect screenBounds = keyWindow.bounds;
        NSDictionary *savedPosition = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kRedDotPositionKey];
        
        if (savedPosition) {
            CGFloat x = [savedPosition[@"x"] floatValue];
            CGFloat y = [savedPosition[@"y"] floatValue];
            x = MAX(10, MIN(screenBounds.size.width - 10, x));
            y = MAX(10, MIN(screenBounds.size.height - 10, y));
            redDotTargetPosition = CGPointMake(x, y);
        } else {
            redDotTargetPosition = CGPointMake(screenBounds.size.width / 2, screenBounds.size.height / 2);
        }
        
        redDotIndicator.center = redDotTargetPosition;
    }
}

void resetRedDotPosition(void) {
    if (!redDotIndicator) createRedDotIndicator();
    
    if (redDotIndicator && redDotIndicator.superview) {
        CGRect screenBounds = redDotIndicator.superview.bounds;
        CGPoint centerPosition = CGPointMake(screenBounds.size.width / 2, screenBounds.size.height / 2);
        redDotTargetPosition = centerPosition;
        redDotIndicator.center = centerPosition;
        
        NSDictionary *positionDict = @{@"x": @(centerPosition.x), @"y": @(centerPosition.y)};
        [[NSUserDefaults standardUserDefaults] setObject:positionDict forKey:kRedDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

void updateRedDotVisibility(void) {
    if (!redDotIndicator) createRedDotIndicator();
    BOOL shouldShow = isBuildModeEnabled && isPopupVisible;
    redDotIndicator.hidden = !shouldShow;
}

// --------- BUTTON STATE (must be before updateMouseLock) ---------
static BOOL leftButtonIsPressed  = NO;
static BOOL rightButtonIsPressed = NO;
static BOOL leftClickSentToGame  = NO;
static GCControllerButtonValueChangedHandler leftButtonGameHandler = nil;
static GCControllerButtonValueChangedHandler leftButtonRawHandler  = nil; // raw game handler, never the wrapper
static GCControllerButtonInput *leftButtonInput = nil;
static BOOL isTriggerHeld        = NO;
static BOOL lockClickConsumed    = NO;
static BOOL unlockingWhileFiring = NO;
static UIView  *lastCheckedView     = nil;
static BOOL     lastViewWasUIElement = NO;
static UIWindow *cachedKeyWindow    = nil;

static void updateMouseLock(BOOL value) {
    UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication].connectedScenes allObjects] firstObject];
    if (!scene) return;

    UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
    if (!keyWindow) return;

    UIViewController *mainViewController = keyWindow.rootViewController;
    [mainViewController setNeedsUpdateOfPrefersPointerLocked];

    if (value) {
        // LOCKING — cancel any in-flight click before the lock gesture takes hold.
        // UITouch clicks (leftButtonIsPressed && !leftClickSentToGame) only need
        // _cancelAllTouches — no GC release since no GC press was sent.
        // GC clicks (leftClickSentToGame) need both _cancelAllTouches and GC release.
        BOOL hadGCPress = leftClickSentToGame;  // GC press was actually sent to game
        GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
        GCControllerButtonInput *gcInput = leftButtonInput;

        leftButtonIsPressed  = NO;
        leftClickSentToGame  = NO;
        lastCheckedView      = nil;
        lastViewWasUIElement = NO;

        // Cancel all touches synchronously on the main thread — async dispatch
        // allows new touches from the lock gesture itself to land before cancel runs.
        void (^cancelBlock)(void) = ^{
            UIApplication *app = [UIApplication sharedApplication];
            static IMP cancelAllTouchesIMP = NULL;
            if (!cancelAllTouchesIMP)
                cancelAllTouchesIMP = [app methodForSelector:@selector(_cancelAllTouches)];
            if (cancelAllTouchesIMP)
                ((void (*)(id, SEL))cancelAllTouchesIMP)(app, @selector(_cancelAllTouches));
            // Only send GC release if a GC press was actually sent.
            if (hadGCPress && gcHandler && gcInput)
                gcHandler(gcInput, 0.0, NO);
        };
        if ([NSThread isMainThread]) cancelBlock();
        else dispatch_sync(dispatch_get_main_queue(), cancelBlock);
    } else {
        // UNLOCKING — full state wipe and cancel everything.
        mouseAccumX = 0.0;
        mouseAccumY = 0.0;
        wasADSInitialized = NO;

        GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
        GCControllerButtonInput *gcInput = leftButtonInput;
        BOOL hadUITouch = leftButtonIsPressed;
        BOOL hadGCPress = leftClickSentToGame;

        leftButtonIsPressed  = NO;
        rightButtonIsPressed = NO;
        leftClickSentToGame  = NO;
        lockClickConsumed    = YES; // block any further clicks while Option is still held
        unlockingWhileFiring = NO;
        leftButtonRawHandler = nil;
        cachedKeyWindow      = nil;
        lastCheckedView      = nil;
        lastViewWasUIElement = NO;

        if (hadUITouch || hadGCPress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIApplication *app = [UIApplication sharedApplication];
                static IMP cancelAllTouchesIMP = NULL;
                if (!cancelAllTouchesIMP)
                    cancelAllTouchesIMP = [app methodForSelector:@selector(_cancelAllTouches)];
                if (cancelAllTouchesIMP)
                    ((void (*)(id, SEL))cancelAllTouchesIMP)(app, @selector(_cancelAllTouches));
                // Only send GC release if a GC press was actually sent.
                if (hadGCPress && gcHandler && gcInput)
                    gcHandler(gcInput, 0.0, NO);
            });
        }
    }

    updateRedDotVisibility();
}

// --------- THEOS HOOKS ---------





// ─────────────────────────────────────────────────────────────────────
// Mouse movement — PC-accurate sensitivity
// ─────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────
// installMouseButtonHandlers
// Called from setMouseMovedHandler — guaranteed to fire because Fortnite
// always calls it. At this point self is the fully connected GCMouseInput
// and all button objects exist. We use valueChangedHandler on middle and
// all aux buttons — it's a separate property from pressedChangedHandler,
// so Fortnite's own handler setup can never overwrite ours.
// ─────────────────────────────────────────────────────────────────────
static void installMouseButtonHandlers(GCMouseInput *mi) {
    void (^installFor)(GCControllerButtonInput*, int) =
        ^(GCControllerButtonInput *btn, int buttonCode) {
            if (!btn) return;
            btn.valueChangedHandler = ^(GCControllerButtonInput *b, float value, BOOL pressed) {
                if (pressed && mouseButtonCaptureCallback) {
                    mouseButtonCaptureCallback(buttonCode);
                    return;
                }
                if (!isMouseLocked) return;

                int idx = buttonCode - MOUSE_BUTTON_MIDDLE;
                if (idx < 0 || idx >= MOUSE_REMAP_COUNT) return;

                GCKeyCode kc = mouseButtonRemapArray[idx];
                if (kc == 0) return;

                if (storedKeyboardHandler && storedKeyboardInput) {
                    GCControllerButtonInput *dummyBtn = [storedKeyboardInput buttonForKeyCode:GCKeyCodeKeyA];
                    storedKeyboardHandler(storedKeyboardInput, dummyBtn, kc, pressed);
                }
            };
        };

    installFor(mi.middleButton, MOUSE_BUTTON_MIDDLE);
    NSArray<GCControllerButtonInput *> *aux = mi.auxiliaryButtons;
    for (NSInteger i = 0; i < (NSInteger)aux.count; i++) {
        installFor(aux[i], (int)(MOUSE_BUTTON_AUX_BASE + i));
    }
}

// ─────────────────────────────────────────────────────────────────────
// NSWindow hook — apply borderless state the instant the window is about
// to appear on screen, before any pixels are drawn. This eliminates the
// visible shift/flash on launch.
// ─────────────────────────────────────────────────────────────────────
%hook NSWindow

- (void)makeKeyAndOrderFront:(id)sender {
    if (isBorderlessModeEnabled) {
        id win = self;
        NSUInteger currentMask = [[win valueForKey:@"styleMask"] unsignedIntegerValue];
        NSUInteger fullSizeMask = (1ULL << 15);
        [win setValue:@(currentMask | fullSizeMask) forKey:@"styleMask"];
        [win setValue:@YES forKey:@"titlebarAppearsTransparent"];
        [win setValue:@(1) forKey:@"titleVisibility"];

        SEL buttonSel = NSSelectorFromString(@"standardWindowButton:");
        typedef id (*ButtonFunc)(id, SEL, NSInteger);
        for (NSInteger i = 0; i <= 2; i++) {
            id btn = ((ButtonFunc)objc_msgSend)(win, buttonSel, i);
            if (btn) [btn setValue:@YES forKey:@"hidden"];
        }
        id closeBtn = ((ButtonFunc)objc_msgSend)(win, buttonSel, 0);
        if (closeBtn) {
            id container = [closeBtn valueForKey:@"superview"];
            if (container) [container setValue:@YES forKey:@"hidden"];
        }
    }
    %orig;
}

%end

%hook GCMouseInput

- (void)setMouseMovedHandler:(GCMouseMoved)handler {
    if (!handler) { %orig; return; }

    GCMouse *currentMouse = GCMouse.current;
    if (currentMouse && currentMouse.handlerQueue != dispatch_get_main_queue())
        currentMouse.handlerQueue = dispatch_get_main_queue();

    // Install handlers on middle + all aux buttons right now.
    // self IS the GCMouseInput — all buttons are fully constructed at this point.
    installMouseButtonHandlers(self);

    // Fix #2: reset accumulator state whenever the game re-registers its handler
    // (e.g. on respawn, menu transitions). Prevents stale ADS/hip state from
    // injecting a wrong-mode remainder into the first event after re-registration.
    mouseAccumX = 0.0;
    mouseAccumY = 0.0;
    wasADSInitialized = NO;

    GCMouseMoved customHandler = ^(GCMouseInput *eventMouse, float deltaX, float deltaY) {
        if (!isMouseLocked) return;

        BOOL isADS = (eventMouse.rightButton.value == 1.0);
        if (!wasADSInitialized) { wasADS = isADS; wasADSInitialized = YES; }
        if (isADS != wasADS) { mouseAccumX = 0.0; mouseAccumY = 0.0; wasADS = isADS; }

        mouseAccumX += deltaX * (isADS ? adsSensitivityX : hipSensitivityX);
        mouseAccumY += deltaY * (isADS ? adsSensitivityY : hipSensitivityY);

        // Fix #1: use double-precision round() instead of roundf() so the
        // remainder carried back into the double accum is never degraded by
        // a float cast before subtraction. Cast to float only at dispatch.
        double outX = round(mouseAccumX);
        double outY = round(mouseAccumY);
        mouseAccumX -= outX;
        mouseAccumY -= outY;

        if (outX != 0.0 || outY != 0.0) handler(eventMouse, (float)outX, (float)outY);
    };
    %orig(customHandler);
}

%end

// ─────────────────────────────────────────────────────────────────────
// GCMouse hook — ensure callbacks fire on main queue.
// ─────────────────────────────────────────────────────────────────────
%hook GCMouse

- (GCMouseInput *)mouseInput {
    static BOOL handlerQueueSet = NO;
    if (!handlerQueueSet && self.handlerQueue != dispatch_get_main_queue()) {
        self.handlerQueue = dispatch_get_main_queue();
        handlerQueueSet = YES;
    }
    GCMouseInput *mi = %orig;
    if (!mi) return mi;
    // If the aux button array grew since last check, reinstall valueChangedHandlers
    // so any newly-appeared buttons get covered.
    static NSUInteger lastAuxCount = 0;
    NSUInteger currentCount = mi.auxiliaryButtons.count;
    if (currentCount > lastAuxCount) {
        lastAuxCount = currentCount;
        installMouseButtonHandlers(mi);
    }
    return mi;
}

%end

// ─────────────────────────────────────────────────────────────────────
// GCKit Scroll direction pad
// ─────────────────────────────────────────────────────────────────────
// Completely disabled and suppressed. All scroll logic is handled natively 
// by AppKit NSEvent monitor at 0ms latency for perfect 1:1 hardware ticks.
%hook GCControllerDirectionPad

- (void)setValueChangedHandler:(void (^)(GCControllerDirectionPad *, float, float))handler {
    GCMouse *currentMouse = GCMouse.current;
    BOOL isScrollPad = NO;
    if (currentMouse && currentMouse.mouseInput) {
        GCMouseInput *mouseInput = currentMouse.mouseInput;
        if ([mouseInput respondsToSelector:@selector(scroll)]) {
            isScrollPad = ([mouseInput scroll] == self);
        } else {
            isScrollPad = (self.xAxis != nil && self.yAxis != nil &&
                           self.up == nil && self.down == nil &&
                           self.left == nil && self.right == nil);
        }
    }
    
    // If it's a regular D-PAD on a controller, let it through normally
    if (!isScrollPad || !handler) { 
        %orig; 
        return; 
    }

    // Wrap the handler: suppress raw scroll if the specific direction scrolled has
    // a keybind assigned, OR if mouse is unlocked. NSEvent monitor handles key firing.
    void (^wrappedHandler)(GCControllerDirectionPad *, float, float) =
        ^(GCControllerDirectionPad *pad, float xValue, float yValue) {
            // Always suppress if mouse is unlocked — game should not receive scroll
            if (!isMouseLocked) return;

            // Suppress per-direction: if the direction being scrolled has a keybind,
            // the NSEvent monitor already fired the key — don't double-fire raw scroll.
            if (yValue > 0) {
                int idx = MOUSE_SCROLL_UP - MOUSE_SCROLL_UP;
                if (mouseScrollRemapArray[idx] != 0 || mouseScrollFortniteArray[idx] != 0) return;
            } else if (yValue < 0) {
                int idx = MOUSE_SCROLL_DOWN - MOUSE_SCROLL_UP;
                if (mouseScrollRemapArray[idx] != 0 || mouseScrollFortniteArray[idx] != 0) return;
            }

            handler(pad, xValue, yValue);
        };
    %orig(wrappedHandler);

    // Nuke the underlying reporting so GCKit stops sending duplicate events
    if ([self.yAxis respondsToSelector:@selector(setValue:)]) {
        [self.yAxis setValue:0.0f];
    }
}

%end
//
// DESIGN: At hook-registration time (setPressedChangedHandler: call), we check
// self against GCMouse.current.mouseInput to classify this button. If the mouse
// isn't ready yet (nil), we install a universal handler that classifies at
// press-time by scanning all mice. This covers every timing scenario.
// ─────────────────────────────────────────────────────────────────────
%hook GCControllerButtonInput

- (void)setPressedChangedHandler:(GCControllerButtonValueChangedHandler)handler {
    if (!handler) { %orig; return; }

    // ── Classify this button at registration time ─────────────────────
    // Check every connected mouse — not just GCMouse.current, because
    // multiple mice may be connected and current may not be set yet.
    typedef enum { kNotMouse, kLeft, kRight, kMiddleOrAux } ButtonRole;
    ButtonRole role = kNotMouse;

    for (GCMouse *mouse in GCMouse.mice) {
        GCMouseInput *mi = mouse.mouseInput;
        if (!mi) continue;
        if (mi.leftButton  == self) { role = kLeft;  break; }
        if (mi.rightButton == self) { role = kRight; break; }
        if (mi.middleButton == self) { role = kMiddleOrAux; break; }
        for (GCControllerButtonInput *btn in mi.auxiliaryButtons) {
            if (btn == self) { role = kMiddleOrAux; break; }
        }
        if (role != kNotMouse) break;
    }

    // ── Not identified as any mouse button — pass through unchanged ───
    if (role == kNotMouse) {
        %orig;
        return;
    }

    // ── Build the custom handler based on role ────────────────────────
    GCControllerButtonValueChangedHandler customHandler = nil;

    if (role == kLeft) {
        customHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            leftButtonGameHandler = handler; // wrapper — do NOT call from right button
            leftButtonRawHandler  = handler; // raw game handler — safe to call directly
            leftButtonInput = button;

            if (isTriggerHeld) {
                if (!pressed) {
                    // RELEASE while Option held — always clean up any in-flight click
                    // state regardless of lockClickConsumed, so nothing is ever left stuck.
                    BOOL hadGCPress = leftClickSentToGame;
                    leftButtonIsPressed = NO;
                    leftClickSentToGame = NO;
                    if (hadGCPress)
                        handler(button, 0.0, NO); // matched GC release for the prior press
                } else if (!lockClickConsumed) {
                    // PRESS — only act on the first click per Option hold.
                    if (!unlockingWhileFiring) {
                        // Left Option + Left Click while unlocked → LOCK
                        lockClickConsumed = YES; isMouseLocked = YES; updateMouseLock(YES);
                    } else {
                        // Left Option + Left Click while locked → UNLOCK
                        lockClickConsumed = YES; isMouseLocked = NO; updateMouseLock(NO);
                    }
                }
                return;
            }
            if (lockClickConsumed && !pressed) { lockClickConsumed = NO; return; }

            if (isMouseLocked) {
                if (!isBuildModeEnabled) {
                    if (pressed) {
                        leftButtonIsPressed = YES; leftClickSentToGame = YES;
                        handler(button, value, pressed);
                    } else {
                        leftButtonIsPressed = NO;
                        // Only send GC release if we sent the press — never send an
                        // unmatched release (e.g. after lock cleared leftClickSentToGame).
                        if (leftClickSentToGame) { handler(button, value, pressed); leftClickSentToGame = NO; }
                        else { leftClickSentToGame = NO; }
                    }
                } else {
                    if (!cachedKeyWindow) {
                        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                        cachedKeyWindow = scene.keyWindow ?: scene.windows.firstObject;
                    }
                    if (cachedKeyWindow) {
                        if (pressed) {
                            if (leftButtonIsPressed) return;
                            leftButtonIsPressed = YES;
                            // Invalidate view cache on every new press — Fortnite UI can
                            // change between presses so stale cache causes wrong touch type.
                            lastCheckedView = nil;
                            lastViewWasUIElement = NO;
                            if (rightButtonIsPressed) { handler(button, value, pressed); leftClickSentToGame = YES; }
                            else { leftClickSentToGame = NO; }
                        } else {
                            if (!leftButtonIsPressed) return;
                            leftButtonIsPressed = NO;
                            // Always send release if we sent a press — even if state changed
                            // mid-hold (build mode toggle, window change). Prevents stuck clicks.
                            if (leftClickSentToGame) { handler(button, value, pressed); leftClickSentToGame = NO; }
                        }
                    } else {
                        if (pressed) { leftButtonIsPressed = YES; leftClickSentToGame = YES; lastCheckedView = nil; lastViewWasUIElement = NO; }
                        else         { leftButtonIsPressed = NO;  if (leftClickSentToGame) { handler(button, value, pressed); } leftClickSentToGame = NO; }
                    }
                }
            } else {
                leftButtonIsPressed = NO; leftClickSentToGame = NO;
            }
        };

    } else if (role == kRight) {
        customHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed) {
            if (isBuildModeEnabled) {
                if (pressed && !rightButtonIsPressed) {
                    if (leftButtonIsPressed && !leftClickSentToGame) {
                        UIApplication *app = [UIApplication sharedApplication];
                        if ([app respondsToSelector:@selector(_cancelAllTouches)])
                            [app performSelector:@selector(_cancelAllTouches)];
                        leftClickSentToGame = YES;
                        // Call the RAW handler directly — leftButtonGameHandler is the
                        // wrapper and would re-enter with stale state, never reaching
                        // the game. leftButtonRawHandler is the game's own handler.
                        if (leftButtonRawHandler && leftButtonInput)
                            leftButtonRawHandler(leftButtonInput, 1.0, YES);
                    }
                } else if (!pressed && rightButtonIsPressed) {
                    // Right click released — if left is still physically held,
                    // keep the GC left click active (don't cancel it).
                    // leftClickSentToGame stays YES so release fires correctly later.
                    // If left was NOT held, nothing to clean up.
                }
            }
            rightButtonIsPressed = pressed;
            if (isMouseLocked) handler(button, value, pressed);
        };

    } else {
        // Middle or aux — figure out this button's code so we can check for remaps.
        int buttonCode = MOUSE_BUTTON_MIDDLE;
        for (GCMouse *mouse in GCMouse.mice) {
            GCMouseInput *mi = mouse.mouseInput;
            if (!mi) continue;
            if (mi.middleButton == self) { buttonCode = MOUSE_BUTTON_MIDDLE; break; }
            NSArray *aux = mi.auxiliaryButtons;
            for (NSInteger i = 0; i < (NSInteger)aux.count; i++) {
                if (aux[i] == self) { buttonCode = (int)(MOUSE_BUTTON_AUX_BASE + i); break; }
            }
        }
        // Wrap Fortnite's handler: suppress it whenever a remap is assigned for this
        // button, so only our valueChangedHandler fires (sending the remapped key).
        int capturedCode = buttonCode;
        GCControllerButtonValueChangedHandler suppressingHandler =
            ^(GCControllerButtonInput *button, float value, BOOL pressed) {
                // Suppress Fortnite's default action if either array has a binding — zero latency pure C
                int idx = capturedCode - MOUSE_BUTTON_MIDDLE;
                if (idx >= 0 && idx < MOUSE_REMAP_COUNT && mouseButtonRemapArray[idx] != 0) return;
                handler(button, value, pressed);
            };
        %orig(suppressingHandler);
        return;
    }

    %orig(customHandler);
}

%end

// =====================================================================
// KEY REMAPPING SYSTEM - ZERO LATENCY OPTIMIZATION
// =====================================================================
// Intercept keyboard input and remap keys according to user settings
// PERFORMANCE: Using inline cache function for ~5ns overhead (cache hit)
// or ~50ns overhead (cache miss). Non-remapped keys: zero overhead.

%hook GCKeyboardInput

- (void)setKeyChangedHandler:(GCKeyboardValueChangedHandler)handler {
    if (!handler) {
        %orig;
        return;
    }

    // Store the raw handler and keyboard input so mouse buttons / scroll can
    // synthesize keyboard key events without going through buttonForKeyCode.
    storedKeyboardInput = self;
    storedKeyboardHandler = handler;
    
    GCKeyboardValueChangedHandler customHandler = ^(GCKeyboardInput * _Nonnull keyboard, GCControllerButtonInput * _Nonnull key, GCKeyCode keyCode, BOOL pressed) {
        // PRIORITY: Key capture for popup (when adding/changing remappings)
        if (keyCaptureCallback != nil && pressed) {
            keyCaptureCallback(keyCode);
            return; // Don't pass key to game during capture
        }

        // Left Option + Left Click = LOCK or UNLOCK. Bare tap does nothing.
        if (keyCode == TRIGGER_KEY) {
            if (isPopupVisible) return;
            if (pressed) {
                // Cancel ALL active UI touches immediately before anything else —
                // any Direct touch in flight must be cleared before isTriggerHeld
                // changes the UITouch type, or the press is permanently orphaned.
                UIApplication *app = [UIApplication sharedApplication];
                if ([app respondsToSelector:@selector(_cancelAllTouches)])
                    [app performSelector:@selector(_cancelAllTouches)];

                isTriggerHeld = YES;
                lockClickConsumed = NO;
                unlockingWhileFiring = isMouseLocked; // already locked = unlock intent
            } else {
                isTriggerHeld = NO;
                unlockingWhileFiring = NO;
                // Lock/unlock only happens via Left Option + Left Click (lockClickConsumed).
                // A bare Left Option tap is intentionally ignored here.
                lockClickConsumed = NO;
            }
            return;
        }
        
        if (pressed && keyCode == POPUP_KEY) {
            if (!popupWindow) {
                createPopup();
            }
            
            // If trying to close (popup currently visible), use the close button logic
            // to check for unsaved changes
            if (isPopupVisible) {
                // Get the popup view controller and call its close method
                popupViewController* viewController = (popupViewController*)popupWindow.rootViewController;
                if (viewController && [viewController respondsToSelector:@selector(closeButtonTapped)]) {
                    [viewController performSelector:@selector(closeButtonTapped)];
                } else {
                    // Fallback: close directly if view controller not available
                    isPopupVisible = NO;
                    popupWindow.hidden = YES;
                    updateRedDotVisibility();
                }
            } else {
                // Opening popup - just show it
                isPopupVisible = YES;
                popupWindow.hidden = NO;
            }
            
            isMouseLocked = false;
            updateMouseLock(isMouseLocked);
            return;
        }

        // TWO-TIER REMAPPING SYSTEM (ULTRA-FAST):
        // PRIORITY 1: Advanced Custom Remaps - user's explicit overrides (~2ns)
        // PRIORITY 2: Fortnite Keybinds - custom key → default key (~2ns)
        // PRIORITY 3: Block default Fortnite keys when remapped away (~2ns)
        // Total overhead: ~6ns (all are direct array lookups, zero dictionary overhead)
        
        GCKeyCode finalKey = keyCode;
        BOOL wasRemapped = NO;
        
        if (keyCode < 256) {
            // PRIORITY 1: Check Advanced Custom Remaps first (takes precedence)
            GCKeyCode customRemap = keyRemapArray[keyCode];
            if (customRemap == (GCKeyCode)-1) {
                // Special case: key is explicitly blocked (remapped to -1)
                return;
            } else if (customRemap != 0) {
                // Advanced Custom Remap found - use it!
                finalKey = customRemap;
                wasRemapped = YES;
            } else {
                // PRIORITY 2: Check Fortnite keybinds (ultra-fast array lookup)
                GCKeyCode fortniteRemap = fortniteRemapArray[keyCode];
                if (fortniteRemap != 0) {
                    // Fortnite keybind found - use it!
                    finalKey = fortniteRemap;
                    wasRemapped = YES;
                } else {
                    // PRIORITY 3: Check if this is a blocked default Fortnite key
                    // Example: if Reload was changed from R to L, we need to block R
                    if (fortniteBlockedDefaults[keyCode] != 0) {
                        // This default key has been remapped to another key - block it!
                        return;
                    }
                }
            }
        }
        
        // CRITICAL FIX: When a key is remapped, we must SUPPRESS the original key entirely
        // and ONLY send the remapped key. Otherwise both keys will be active.
        if (wasRemapped) {
            // Key was remapped - find the key button for the target key and call handler with it
            // keyboard is already GCKeyboardInput, so call buttonForKeyCode directly
            GCControllerButtonInput* remappedButton = [keyboard buttonForKeyCode:finalKey];
            if (remappedButton) {
                // Call handler with the REMAPPED button, not the original
                handler(keyboard, remappedButton, finalKey, pressed);
                return;
            }
            // Fallback: if we can't get the remapped button, still suppress original
            return;
        }
        
        // No remapping - call handler with original key
        handler(keyboard, key, keyCode, pressed);
    };

    %orig(customHandler);
}

%end

// Disable pointer "locking" mechanism
%hook IOSViewController

- (BOOL)prefersPointerLocked {
    return isMouseLocked;
}

%end

// Enable 120 FPS on any screen
%hook UIScreen

- (NSInteger)maximumFramesPerSecond {
    return 120;
}

%end

// Trick the game into thinking mouse clicks are touchscreen clicks
%hook UITouch

- (UITouchType)type {
    UITouchType _original = %orig;
    
    // FAST PATH: If not indirect pointer, return immediately
    if (_original != UITouchTypeIndirectPointer) {
        return _original;
    }

    // Suppress touch if this is a lock gesture (Option held while unlocked),
    // BUT only if no left click is already in flight — if it is, we must let
    // the touch complete with the same type it started with to avoid a stuck touch.
    if (isTriggerHeld && !unlockingWhileFiring && !leftButtonIsPressed) {
        return _original;
    }

    // FAST PATH: Mouse unlocked - always convert to direct touch
    if (!isMouseLocked) {
        return UITouchTypeDirect;
    }
    
    // FAST PATH: Build mode disabled OR right-click held - no conversion needed
    if (!isBuildModeEnabled || rightButtonIsPressed) {
        return _original;
    }
    
    // BUILD MODE ONLY: Check if over UI element (only when needed)
    UIView *view = self.view;
    
    // OPTIMIZATION: Cache check for same view (saves ~400ns on repeated touches)
    if (view == lastCheckedView) {
        return lastViewWasUIElement ? UITouchTypeDirect : _original;
    }
    
    // Walk up view hierarchy checking for UI elements
    // Optimized check order: gestureRecognizers (fastest) → UIButton (specific) → UIControl (broad)
    UIView *checkView = view;
    while (checkView != nil) {
        // Check 1: Gesture recognizers (fastest - just array count)
        if ([checkView.gestureRecognizers count] > 0) {
            lastCheckedView = view;
            lastViewWasUIElement = YES;
            return UITouchTypeDirect;
        }
        // Check 2: UIButton (more specific, faster than UIControl)
        if ([checkView isKindOfClass:[UIButton class]]) {
            lastCheckedView = view;
            lastViewWasUIElement = YES;
            return UITouchTypeDirect;
        }
        // Check 3: UIControl (broader check)
        if ([checkView isKindOfClass:[UIControl class]]) {
            lastCheckedView = view;
            lastViewWasUIElement = YES;
            return UITouchTypeDirect;
        }
        checkView = checkView.superview;
    }
    
    // Not a UI element - cache and return
    lastCheckedView = view;
    lastViewWasUIElement = NO;
    return _original;
}

// Override touch location in BUILD mode to use red dot position
- (CGPoint)locationInView:(UIView *)view {
    CGPoint originalLocation = %orig;
    
    // FAST PATH: Early exit if conditions aren't met
    if (!isBuildModeEnabled || !isMouseLocked || rightButtonIsPressed) {
        return originalLocation;
    }
    
    // BUILD MODE ONLY: Check if this touch is over a UI element
    UIView *touchView = self.view;
    
    // OPTIMIZATION: Use cached result if same view (saves ~400ns)
    BOOL isUIElement = NO;
    if (touchView == lastCheckedView) {
        isUIElement = lastViewWasUIElement;
    } else {
        // Walk up view hierarchy with optimized check order
        UIView *checkView = touchView;
        while (checkView != nil) {
            if ([checkView.gestureRecognizers count] > 0 ||
                [checkView isKindOfClass:[UIButton class]] ||
                [checkView isKindOfClass:[UIControl class]]) {
                isUIElement = YES;
                break;
            }
            checkView = checkView.superview;
        }
        // Cache result
        lastCheckedView = touchView;
        lastViewWasUIElement = isUIElement;
    }
    
    if (isUIElement) {
        // Over UI - use red dot position
        if (!view) {
            return redDotTargetPosition;
        }
        
        // Use cached keyWindow — avoids connectedScenes alloc per touch event
        if (!cachedKeyWindow) {
            UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
            cachedKeyWindow = scene.keyWindow ?: scene.windows.firstObject;
        }
        if (cachedKeyWindow) {
            return [view convertPoint:redDotTargetPosition fromView:cachedKeyWindow];
        }
        return redDotTargetPosition;
    }
    
    return originalLocation;
}

- (CGPoint)previousLocationInView:(UIView *)view {
    CGPoint originalLocation = %orig;
    
    // FAST PATH: Early exit if conditions aren't met
    if (!isBuildModeEnabled || !isMouseLocked || rightButtonIsPressed) {
        return originalLocation;
    }
    
    // BUILD MODE ONLY: Check if this touch is over a UI element
    UIView *touchView = self.view;
    
    // OPTIMIZATION: Use cached result (same view means same result)
    BOOL isUIElement = (touchView == lastCheckedView) ? lastViewWasUIElement : NO;
    
    if (!isUIElement) {
        // Need to check - walk hierarchy
        UIView *checkView = touchView;
        while (checkView != nil) {
            if ([checkView.gestureRecognizers count] > 0 ||
                [checkView isKindOfClass:[UIButton class]] ||
                [checkView isKindOfClass:[UIControl class]]) {
                isUIElement = YES;
                break;
            }
            checkView = checkView.superview;
        }
    }
    
    if (isUIElement) {
        // Over UI - use red dot position
        if (!view) {
            return redDotTargetPosition;
        }
        
        // Use cached keyWindow — avoids connectedScenes alloc per touch event
        if (!cachedKeyWindow) {
            UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
            cachedKeyWindow = scene.keyWindow ?: scene.windows.firstObject;
        }
        if (cachedKeyWindow) {
            return [view convertPoint:redDotTargetPosition fromView:cachedKeyWindow];
        }
        return redDotTargetPosition;
    }
    
    return originalLocation;
}

%end
