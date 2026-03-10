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
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

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

static void preloadChickenGIF(void);
static void showChickenDinner(void);
static void dismissChickenDinner(void);
static void showDestroyGIF(void);

%ctor {
    // Fishhook for device spoofing
    struct rebinding rebindings[] = {
        {"sysctl", (void *)pt_sysctl, (void **)&orig_sysctl},
        {"sysctlbyname", (void *)pt_sysctlbyname, (void **)&orig_sysctlbyname}
    };
    rebind_symbols(rebindings, 2);

    NSString* currentVersion = @"3.0.1";
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

    preloadChickenGIF(); // 🐔 fetch in background so first open is instant
    [[NSNotificationCenter defaultCenter]   // 🐔 destroy GIF on close
        addObserverForName:@"FnMacTweakDestroyChicken"
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *_) { showDestroyGIF(); }];
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


// ─────────────────────────────────────────────────────────────────────
// WINNER WINNER CHICKEN DINNER 🐔
// ─────────────────────────────────────────────────────────────────────

// Three open GIFs cycling in order, plus one close GIF
static NSArray<NSString *> *_openGIFURLs(void) {
    return @[
        @"https://github.com/KohlerVG/FnMacTweak/releases/download/v3-assets/Winner.Winner.Win.GIF.by.GIPHY.Studios.2021.gif",
        @"https://github.com/KohlerVG/FnMacTweak/releases/download/v3-assets/hate.you.shut.up.GIF.by.happydog.gif",
        @"https://github.com/KohlerVG/FnMacTweak/releases/download/v3-assets/Angry.Chicken.GIF.by.happydog.gif",
    ];
}
static NSString *_closeGIFURL(void) {
    return @"https://github.com/KohlerVG/FnMacTweak/releases/download/v3-assets/chicken.destroy.GIF.by.happydog.gif";
}

static NSMutableDictionary<NSString *, NSData *> *_gifCache = nil;
static NSInteger _openGIFIndex = 0;
static UIWindow *_chickenWindow = nil;
static id _chickenObserver = nil;
static UIImageView *_chickenIV = nil;
static UIView *_chickenCard = nil;
BOOL _destroyPending = NO;
static NSInteger _chickenGeneration = 0; // bump to cancel all in-flight blocks
static CADisplayLink *_chickenSyncLink = nil; // frame-sync display link, invalidated on destroy

// Fetch all GIFs in background at startup
static void preloadChickenGIF() {
    if (!_gifCache) _gifCache = [NSMutableDictionary dictionary];
    NSMutableArray *allURLs = [NSMutableArray arrayWithArray:_openGIFURLs()];
    [allURLs addObject:_closeGIFURL()];
    for (NSString *url in allURLs) {
        if (_gifCache[url]) continue;
        NSString *urlCopy = url;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlCopy]];
            if (data) {
                dispatch_async(dispatch_get_main_queue(), ^{ _gifCache[urlCopy] = data; });
            }
        });
    }
}

// Build UIImage animated from cached NSData using real per-frame GIF delays
static UIImage *_buildAnimatedImage(NSData *gifData) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)gifData, NULL);
    if (!source) return nil;
    size_t count = CGImageSourceGetCount(source);
    NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval totalDuration = 0;
    for (size_t i = 0; i < count; i++) {
        CGImageRef cgImg = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!cgImg) continue;
        [frames addObject:[UIImage imageWithCGImage:cgImg]];
        CGImageRelease(cgImg);
        // Read actual per-frame delay from GIF metadata
        NSTimeInterval delay = 0.1;
        NSDictionary *props = (__bridge_transfer NSDictionary *)
            CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        NSDictionary *gifProps = props[(NSString *)kCGImagePropertyGIFDictionary];
        if (gifProps) {
            NSNumber *d = gifProps[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
            if (!d || d.doubleValue < 0.01)
                d = gifProps[(NSString *)kCGImagePropertyGIFDelayTime];
            if (d && d.doubleValue >= 0.01) delay = d.doubleValue;
        }
        totalDuration += delay;
    }
    CFRelease(source);
    if (!frames.count) return nil;
    return [UIImage animatedImageWithImages:frames duration:totalDuration];
}

static void showChickenDinner() {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
    if (!keyWindow) return;

    // Pick next open GIF in rotation
    NSArray *urls = _openGIFURLs();
    NSString *url = urls[_openGIFIndex % urls.count];
    _openGIFIndex++;

    if (!_gifCache || !_gifCache[url]) {
        // Not cached yet — fetch and skip this open
        preloadChickenGIF();
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *gifData = _gifCache[url];
        if (!gifData) return;
        UIImage *animatedImage = _buildAnimatedImage(gifData);
        if (!animatedImage) return;
        dispatch_async(dispatch_get_main_queue(), ^{

            // Create a dedicated UIWindow sitting above popupWindow so the card
            // is never clipped by the root view's masksToBounds and always on top.
            // We mirror popupWindow's frame so the card coordinates match 1:1 and
            // the window moves with the pane when dragged.
            UIWindowScene *wScene = popupWindow.windowScene;
            _chickenWindow = [[UIWindow alloc] initWithWindowScene:wScene];
            UIWindow *chickenWindow = _chickenWindow;
            chickenWindow.frame = popupWindow.frame;
            chickenWindow.windowLevel = popupWindow.windowLevel + 1;
            chickenWindow.backgroundColor = [UIColor clearColor];
            chickenWindow.userInteractionEnabled = NO;
            chickenWindow.hidden = NO;

            // Dismiss instantly if popup is closed mid-animation
            // Remove any stale observer first
            if (_chickenObserver) {
                [[NSNotificationCenter defaultCenter] removeObserver:_chickenObserver];
                _chickenObserver = nil;
            }
            _chickenObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:@"FnMacTweakDismissChicken"
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *_) {
                // Stop open animation in place — showDestroyGIF will take over
                if (_chickenWindow) [_chickenWindow.layer removeAllAnimations];
                if (_chickenObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:_chickenObserver];
                    _chickenObserver = nil;
                }
            }];

            UIViewController *dummyVC = [UIViewController new];
            dummyVC.view.backgroundColor = [UIColor clearColor];
            chickenWindow.rootViewController = dummyVC;

            CGFloat paneW = popupWindow.bounds.size.width;
            CGFloat paneH = popupWindow.bounds.size.height;

            UIView *overlay = [[UIView alloc] initWithFrame:CGRectMake(0, 0, paneW, paneH)];
            overlay.backgroundColor = [UIColor clearColor];
            overlay.userInteractionEnabled = NO;

            CGFloat margin = 16.0;
            CGFloat cardW = paneW - margin * 2;
            CGFloat cardX = margin;
            CGFloat cardY = floor((paneH - cardW) / 2.0);
            UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardW, cardW)];
            card.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
            card.layer.cornerRadius = 12;
            card.layer.borderWidth = 0.5;
            card.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
            card.layer.masksToBounds = YES;

            CGFloat padding = 12;
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(
                padding, padding, cardW - padding * 2, cardW - padding * 2)];
            iv.image = animatedImage;
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = 8;
            iv.layer.masksToBounds = YES;
            _chickenIV = iv;
            _chickenCard = card;
            [card addSubview:iv];
            [overlay addSubview:card];
            [dummyVC.view addSubview:overlay];

            // Keep chickenWindow frame in sync while it's visible by polling
            // popupWindow.frame on every display frame using a CADisplayLink.
            __block UIWindow *_cw = chickenWindow;
            __block UIWindow *_pw = popupWindow;
            CADisplayLink *__block link = [CADisplayLink
                displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{
                    if (_cw && _pw) _cw.frame = _pw.frame;
                }]
                selector:@selector(main)];
            [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            _chickenSyncLink = link;
            __block CADisplayLink *syncLink = link;

            // Capture generation so all completion blocks can bail if cancelled
            NSInteger myGen = _chickenGeneration;

            // Bounce in from scale 0
            overlay.alpha = 0;
            card.transform = CGAffineTransformMakeScale(0.1, 0.1);
            [UIView animateWithDuration:0.5
                                  delay:0
                 usingSpringWithDamping:0.5
                  initialSpringVelocity:0.8
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                overlay.alpha = 1;
                card.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                if (_chickenGeneration != myGen) return;
                // Phase 1 — hold 1.8s then shrink to 50%
                [UIView animateWithDuration:0.7
                                      delay:1.8
                                    options:UIViewAnimationOptionCurveEaseIn
                                 animations:^{
                    card.transform = CGAffineTransformMakeScale(0.5, 0.5);
                } completion:^(BOOL s1) {
                    if (_chickenGeneration != myGen) return;

                    // Phase 2 — look around randomly (3-4 spots)
                    int totalSearches = 3 + arc4random_uniform(2);
                    __block int searchCount = 0;
                    __block CGFloat lastTx = 0, lastTy = 0;

                    // Recursive block for chained async animations
                    __block void (^doSearch)(void);
                    __weak __block void (^weakDoSearch)(void);
                    weakDoSearch = nil; // set after assignment below
                    doSearch = [^{
                    __strong void (^strongDoSearch)(void) = weakDoSearch;
                        if (_chickenGeneration != myGen) return;
                        if (searchCount >= totalSearches) {
                            // Settle back to center with spring
                            [UIView animateWithDuration:0.5
                                                  delay:0
                                 usingSpringWithDamping:0.5
                                  initialSpringVelocity:0.3
                                                options:UIViewAnimationOptionCurveEaseOut
                                             animations:^{
                                card.transform = CGAffineTransformMakeScale(0.5, 0.5);
                            } completion:^(BOOL settled) {
                                // Phase 3 — iris close using CAAnimationGroup so
                                // both scale and cornerRadius animate reliably together
                                card.layer.cornerRadius = 12;
                                card.layer.masksToBounds = YES;

                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                    (int64_t)(0.45 * NSEC_PER_SEC)),
                                    dispatch_get_main_queue(), ^{
                                    if (_chickenGeneration != myGen) return;

                                    CGFloat halfW = card.bounds.size.width / 2.0;
                                    CGFloat halfIv = iv.bounds.size.width / 2.0;
                                    NSTimeInterval dur = 1.5;

                                    CABasicAnimation *scaleAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
                                    scaleAnim.fromValue = @(0.5);
                                    scaleAnim.toValue   = @(0.0);

                                    CABasicAnimation *radiusAnim = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
                                    radiusAnim.fromValue = @(12.0);
                                    radiusAnim.toValue   = @(halfW);

                                    CAAnimationGroup *group = [CAAnimationGroup animation];
                                    group.animations  = @[scaleAnim, radiusAnim];
                                    group.duration    = dur;
                                    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
                                    group.fillMode    = kCAFillModeForwards;
                                    group.removedOnCompletion = NO;

                                    [card.layer addAnimation:group forKey:@"irisClose"];

                                    // iv gets same cornerRadius animation in sync
                                    CABasicAnimation *ivRadiusAnim = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
                                    ivRadiusAnim.fromValue = @(8.0);
                                    ivRadiusAnim.toValue   = @(halfIv);
                                    ivRadiusAnim.duration  = dur;
                                    ivRadiusAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
                                    ivRadiusAnim.fillMode  = kCAFillModeForwards;
                                    ivRadiusAnim.removedOnCompletion = NO;

                                    [iv.layer addAnimation:ivRadiusAnim forKey:@"irisCloseIv"];

                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                        (int64_t)((dur + 0.05) * NSEC_PER_SEC)),
                                        dispatch_get_main_queue(), ^{
                                        if (_chickenGeneration != myGen) return;
                                        [syncLink invalidate];
                                        _chickenSyncLink = nil;
                                        if (_chickenObserver) {
                                            [[NSNotificationCenter defaultCenter] removeObserver:_chickenObserver];
                                            _chickenObserver = nil;
                                        }
                                        // Hide window but keep hierarchy intact so
                                        // showDestroyGIF can reuse it if user closes after
                                        chickenWindow.hidden = YES;
                                        overlay.hidden = YES;
                                    });
                                });
                            }];
                            return;
                        }
                        searchCount++;

                        // Random position within pane — 35 to 90pt from center
                        CGFloat angle = ((CGFloat)arc4random_uniform(3600)) / 3600.0 * M_PI * 2.0;
                        CGFloat dist  = 35.0 + ((CGFloat)arc4random_uniform(5500)) / 100.0;
                        CGFloat tx = roundf(cosf(angle) * dist);
                        CGFloat ty = roundf(sinf(angle) * dist);

                        // Distance-based duration so far moves feel proportional
                        CGFloat dx = tx - lastTx, dy = ty - lastTy;
                        CGFloat moveDist = sqrtf(dx*dx + dy*dy);
                        NSTimeInterval moveDur = (165.0 + moveDist * 4.1) / 1000.0;
                        NSTimeInterval pauseDur = (90.0 + ((CGFloat)arc4random_uniform(10500)) / 100.0) / 1000.0;
                        lastTx = tx; lastTy = ty;

                        [UIView animateWithDuration:moveDur
                                              delay:0
                                            options:UIViewAnimationOptionCurveEaseInOut
                                         animations:^{
                            card.transform = CGAffineTransformConcat(
                                CGAffineTransformMakeScale(0.5, 0.5),
                                CGAffineTransformMakeTranslation(tx, ty));
                        } completion:^(BOOL moved) {
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                (int64_t)(pauseDur * NSEC_PER_SEC)),
                                dispatch_get_main_queue(), strongDoSearch);
                        }];
                    } copy];
                    weakDoSearch = doSearch;

                    doSearch();
                }];
            }];
        });
    });
}

static void __attribute__((used)) dismissChickenDinner() {
    if (_chickenObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_chickenObserver];
        _chickenObserver = nil;
    }
    if (_chickenWindow) {
        UIWindow *w = _chickenWindow;
        _chickenWindow = nil;
        _chickenIV = nil;
        _chickenCard = nil;
        _destroyPending = NO;
        _chickenGeneration++;
        if (_chickenSyncLink) { [_chickenSyncLink invalidate]; _chickenSyncLink = nil; }
        [w.layer removeAllAnimations];
        w.hidden = YES;
    }
}

// Show the destroy GIF in-place inside the existing chickenWindow.
// Swaps the iv image instantly, waits one full GIF cycle,
// then hides both the popup pane and the chicken window together.
static void showDestroyGIF() {
    // Guard: only one destroy sequence at a time
    if (_destroyPending) return;
    if (!_gifCache) return;
    NSData *gifData = _gifCache[_closeGIFURL()];
    if (!gifData) return;
    if (!_chickenWindow || !_chickenIV || !_chickenCard) return;

    UIImage *animatedImage = _buildAnimatedImage(gifData);
    if (!animatedImage) return;

    _destroyPending = YES;
    _chickenGeneration++; // cancels all in-flight open animation blocks instantly
    if (_chickenSyncLink) { [_chickenSyncLink invalidate]; _chickenSyncLink = nil; }

    // ── Stop every in-flight animation on the whole chicken window ──
    [_chickenWindow.layer removeAllAnimations];
    [_chickenCard.layer removeAllAnimations];
    [_chickenIV.layer removeAllAnimations];
    for (UIView *sub in _chickenCard.subviews) [sub.layer removeAllAnimations];

    // ── Reset card to initial state (full size, centered, 12pt radius) ──
    _chickenCard.transform   = CGAffineTransformIdentity;
    _chickenCard.alpha        = 1.0;
    _chickenCard.layer.cornerRadius = 12;

    // ── Reset iv to initial state (8pt radius, full frame, AspectFill) ──
    _chickenIV.layer.cornerRadius = 8;
    _chickenIV.layer.transform    = CATransform3DIdentity;
    _chickenIV.alpha               = 1.0;

    // ── Make sure the overlay containing the card is fully visible ──
    // After iris close, overlay was removed from superview — re-add it
    UIView *overlay = _chickenCard.superview;
    UIViewController *rootVC = _chickenWindow.rootViewController;
    if (overlay && overlay.superview == nil && rootVC) {
        [rootVC.view addSubview:overlay];
    }
    if (overlay) { overlay.alpha = 1.0; overlay.hidden = NO; overlay.transform = CGAffineTransformIdentity; }

    // Reset CALayer presentation state (fillMode=forwards may have frozen it at scale 0)
    _chickenCard.layer.transform = CATransform3DIdentity;
    _chickenIV.layer.transform   = CATransform3DIdentity;

    // Unhide window in case open animation already finished and hid it
    _chickenWindow.layer.opacity = 1.0;
    _chickenWindow.hidden = NO;

    // ── Drive frames manually via CADisplayLink so we stop EXACTLY on the last frame ──
    // Never use UIImageView animation for destroy — it loops and we can't stop it precisely.
    NSArray<UIImage *> *frames = animatedImage.images;
    NSUInteger frameCount = frames.count;
    if (!frameCount) return;

    // Build per-frame durations by re-reading GIF metadata
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)gifData, NULL);
    NSMutableArray<NSNumber *> *delays = [NSMutableArray arrayWithCapacity:frameCount];
    for (NSUInteger i = 0; i < frameCount; i++) {
        NSTimeInterval d = 0.1;
        NSDictionary *props = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        NSDictionary *gp = props[(NSString *)kCGImagePropertyGIFDictionary];
        if (gp) {
            NSNumber *n = gp[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
            if (!n || n.doubleValue < 0.01) n = gp[(NSString *)kCGImagePropertyGIFDelayTime];
            if (n && n.doubleValue >= 0.01) d = n.doubleValue;
        }
        [delays addObject:@(d)];
    }
    if (src) CFRelease(src);

    // Show first frame immediately (no animated image — we drive it)
    _chickenIV.image = frames[0];

    __block NSUInteger frameIdx = 0;
    __block NSTimeInterval frameBudget = [delays[0] doubleValue];
    __block CFTimeInterval lastTime = 0;
    UIImageView *iv = _chickenIV;
    UIWindow *cw = _chickenWindow;

    CADisplayLink *dl = [CADisplayLink
        displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{
            CFTimeInterval now = CACurrentMediaTime();
            if (lastTime == 0) { lastTime = now; return; }
            frameBudget -= (now - lastTime);
            lastTime = now;

            if (frameBudget <= 0) {
                frameIdx++;
                if (frameIdx >= frameCount) {
                    // Landed on last frame — freeze and close
                    iv.image = frames[frameCount - 1];
                    // Invalidate on next runloop tick so we're not inside the callback
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // dl captured below
                    });
                    return; // dl will be invalidated by the outer block below
                }
                iv.image = frames[frameIdx];
                frameBudget = [delays[frameIdx] doubleValue];
            }
        }]
        selector:@selector(main)];
    [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    // Watch for frameIdx reaching the end using a polling dispatch
    // (CADisplayLink block can't invalidate itself directly)
    __block CADisplayLink *destroyLink = dl;
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^__block poll)(void);
        __weak __block void (^weakPoll)(void);
        poll = [^{
            __strong void (^strongPoll)(void) = weakPoll;
            if (frameIdx >= frameCount) {
                [destroyLink invalidate];
                destroyLink = nil;
                iv.image = frames[frameCount - 1]; // last frame, no loop
                cw.hidden = YES;
                isPopupVisible = NO;
                popupWindow.hidden = YES;
                updateRedDotVisibility();
                if (_chickenWindow == cw) {
                    _chickenWindow = nil;
                    _chickenIV     = nil;
                    _chickenCard   = nil;
                }
                _destroyPending = NO;
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), strongPoll);
        } copy];
        weakPoll = poll;
        poll();
    });
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
    showChickenDinner(); // 🐔
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
                // Stop the open animation in place, then show destroy GIF in same window
                if (_chickenObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:_chickenObserver];
                    _chickenObserver = nil;
                }
                if (_chickenWindow) [_chickenWindow.layer removeAllAnimations];

                if (_chickenWindow && _chickenIV) {
                    // Destroy GIF will play in the existing window and hide popup when done
                    showDestroyGIF();
                } else {
                    // No chicken window — close normally
                    popupViewController* viewController = (popupViewController*)popupWindow.rootViewController;
                    if (viewController && [viewController respondsToSelector:@selector(closeButtonTapped)]) {
                        [viewController performSelector:@selector(closeButtonTapped)];
                    } else {
                        isPopupVisible = NO;
                        popupWindow.hidden = YES;
                        updateRedDotVisibility();
                    }
                }
            } else {
                // Opening popup - just show it
                isPopupVisible = YES;
                popupWindow.hidden = NO;
                showChickenDinner(); // 🐔
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
