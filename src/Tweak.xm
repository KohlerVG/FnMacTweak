#import "./views/popupViewController.h"
#import "./views/welcomeViewController.h"
#import "./globals.h"

#import "../lib/fishhook.h"
#import <sys/sysctl.h>

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <math.h>

// Pre-calculated sensitivity multipliers (computed once at startup via recalculateSensitivities())
// Formula: (BASE_XY_SENSITIVITY / 100) × (Look% / 100) × MACOS_TO_PC_SCALE

// --------- MOUSE FRACTIONAL ACCUMULATION ---------
static double mouseAccumX = 0.0;
static double mouseAccumY = 0.0;
static BOOL wasADS = NO;
static BOOL wasADSInitialized = NO;

// --------- BUILD MODE MOUSE POSITION TRACKING ---------
static CGPoint lastMousePosition = CGPointZero;
static BOOL leftButtonIsPressed = NO;
static BOOL rightButtonIsPressed = NO;
static BOOL leftClickSentToGame = NO;

// Store the left button's game handler for triggering from right-click handler
static GCControllerButtonValueChangedHandler leftButtonGameHandler = nil;
static GCControllerButtonInput* leftButtonInput = nil;

// Tracks whether Left Option is currently held, and whether a lock gesture
// (Option + Left Click) was consumed during that hold.
static BOOL isTriggerHeld = NO;
// Set when Option+Click consumed a click to LOCK — suppresses that click's release
static BOOL lockClickConsumed = NO;
// Set when Option is pressed while already locked — signals unlock-while-firing path
static BOOL unlockingWhileFiring = NO;

// Cache for UITouch view hierarchy checks (performance optimization)
static UIView* lastCheckedView = nil;
static BOOL lastViewWasUIElement = NO;

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

    // Version-based initialization for clean updates
    // Version is written to NSUserDefaults by the postinst script from the control file.
    // This means bumping the control file version is the single source of truth —
    // no need to update anything in code.
    NSString* currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.version"];
    NSString* lastVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.lastSeenVersion"];

    if (!lastVersion || ![lastVersion isEqualToString:currentVersion]) {
        // New install or version update detected
        // CLEAR custom keybinds (advanced remaps) for clean slate
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kKeyRemapKey];
        // Clear welcome flag so popup re-appears for this new version
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSeenVersion"];
        // Record this version as seen so we don't repeat until next bump
        [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"fnmactweak.lastSeenVersion"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Load BUILD mode setting (default: NO = ZERO BUILD mode)
    isBuildModeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kBuildModeKey];

    // Restore folder access
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

    // Initialize key bindings
    TRIGGER_KEY = GCKeyCodeLeftAlt;
    POPUP_KEY = GCKeyCodeKeyP;
    
    // OPTIMIZATION: Pre-calculate sensitivities once at startup
    recalculateSensitivities();
    
    // Load key remappings (Advanced Custom Remaps)
    loadKeyRemappings();
    
    // Load Fortnite keybinds into fast array
    loadFortniteKeybinds();

    // Show welcome screen on first launch (safe — uses FnOverlayWindow,
    // never steals key window, no dispatch_after race with GCMouse)
    showWelcomePopupIfNeeded();
}

// --------- HELPER FUNCTIONS ---------

// Helper to align coordinates to pixel boundaries
static inline CGFloat PixelAlign(CGFloat value) {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    UIScreen *screen = scene.screen;
    CGFloat scale = screen.scale;
    return round(value * scale) / scale;
}

// Initialize the popup window
static void createPopup() {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    popupWindow = [[UIWindow alloc] initWithWindowScene:scene];

    CGFloat popupW = PixelAlign(330.0);
    CGFloat popupH = PixelAlign(600.0);
    CGRect screen = scene ? scene.effectiveGeometry.coordinateSpace.bounds : CGRectMake(0, 0, 390, 844);
    CGFloat centeredY = PixelAlign((screen.size.height - popupH) / 2.0);

    popupWindow.frame = CGRectMake(
        PixelAlign(100.0),
        centeredY,
        popupW,
        popupH
    );
    
    popupWindow.windowLevel = UIWindowLevelAlert + 1;
    popupWindow.backgroundColor = [UIColor clearColor];  // Make window transparent
    // Don't set corner radius on window - let the view controller handle it
    
    popupViewController *popupVC = [popupViewController new];
    popupWindow.rootViewController = popupVC;
}

// Open the P settings pane directly on the Quick Start tab.
// Called by the welcome screen's "Continue to Quick Start Guide" button.
void showPopupOnQuickStartTab(void) {
    if (!popupWindow) createPopup();
    isPopupVisible = YES;
    popupWindow.hidden = NO;
    popupViewController *vc = (popupViewController *)popupWindow.rootViewController;
    if ([vc respondsToSelector:@selector(switchToQuickStartTab)]) {
        [vc switchToQuickStartTab];
    }
}

// Create the red dot target indicator for BUILD mode
void createRedDotIndicator() {
    if (redDotIndicator) return; // Already created
    
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    if (!scene) return;
    
    // Create a small red dot (20x20 pixels)
    redDotIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    redDotIndicator.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.8];
    redDotIndicator.layer.cornerRadius = 10; // Make it circular
    redDotIndicator.layer.borderWidth = 2;
    redDotIndicator.layer.borderColor = [UIColor whiteColor].CGColor;
    redDotIndicator.hidden = YES; // Start hidden
    redDotIndicator.userInteractionEnabled = YES;
    
    // Add a pan gesture to make it draggable
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:redDotIndicator action:nil];
    __weak UIView *weakDot = redDotIndicator;
    [panGesture addTarget:weakDot action:@selector(handlePan:)];
    [redDotIndicator addGestureRecognizer:panGesture];
    
    // Get the main game window
    UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
    if (keyWindow) {
        [keyWindow addSubview:redDotIndicator];
        
        // Load saved position from UserDefaults, or use center as default
        CGRect screenBounds = keyWindow.bounds;
        NSDictionary *savedPosition = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kRedDotPositionKey];
        
        if (savedPosition) {
            // Use saved position
            CGFloat x = [savedPosition[@"x"] floatValue];
            CGFloat y = [savedPosition[@"y"] floatValue];
            
            // Validate bounds (in case screen size changed)
            x = MAX(10, MIN(screenBounds.size.width - 10, x));
            y = MAX(10, MIN(screenBounds.size.height - 10, y));
            
            redDotTargetPosition = CGPointMake(x, y);
        } else {
            // Initialize position at center of screen (first time)
            redDotTargetPosition = CGPointMake(screenBounds.size.width / 2, screenBounds.size.height / 2);
        }
        
        redDotIndicator.center = redDotTargetPosition;
    }
}

// Reset red dot position to center of screen
void resetRedDotPosition(void) {
    if (!redDotIndicator) {
        createRedDotIndicator();
    }
    
    if (redDotIndicator && redDotIndicator.superview) {
        // Get screen bounds
        CGRect screenBounds = redDotIndicator.superview.bounds;
        
        // Reset to center
        CGPoint centerPosition = CGPointMake(screenBounds.size.width / 2, screenBounds.size.height / 2);
        redDotTargetPosition = centerPosition;
        redDotIndicator.center = centerPosition;
        
        // Save the reset position
        NSDictionary *positionDict = @{
            @"x": @(centerPosition.x),
            @"y": @(centerPosition.y)
        };
        [[NSUserDefaults standardUserDefaults] setObject:positionDict forKey:kRedDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

// Show or hide the red dot indicator
void updateRedDotVisibility(void) {
    if (!redDotIndicator) {
        createRedDotIndicator();
    }
    
    // Show red dot when: BUILD mode enabled AND settings popup IS visible
    // Hide when popup is closed or build mode is disabled
    BOOL shouldShow = isBuildModeEnabled && isPopupVisible;
    redDotIndicator.hidden = !shouldShow;
}

// Force a pointer lock update
static void updateMouseLock(BOOL value) {
    UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication].connectedScenes allObjects] firstObject];
    if (!scene) return;

    UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
    if (!keyWindow) return;

    UIViewController *mainViewController = keyWindow.rootViewController;
    [mainViewController setNeedsUpdateOfPrefersPointerLocked];

    if (!value) {
        isAlreadyFocused = NO;
        mouseAccumX = 0.0;
        mouseAccumY = 0.0;
        wasADSInitialized = NO;

        // Snapshot refs before clearing state
        GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
        GCControllerButtonInput *gcInput = leftButtonInput;
        BOOL buttonWasDown = leftButtonIsPressed;

        // Reset all button state flags immediately so no re-entrant events slip through
        leftButtonIsPressed  = NO;
        rightButtonIsPressed = NO;
        leftClickSentToGame  = NO;
        lockClickConsumed    = NO;
        unlockingWhileFiring = NO;

        // Dispatch cleanup on next run loop tick — after isMouseLocked is fully
        // committed and prefersPointerLocked has been re-queried — so any
        // re-entrant UITouch or GC events from _cancelAllTouches see a clean state.
        dispatch_async(dispatch_get_main_queue(), ^{
            // Cancel any live UITouches so nothing stays stuck in the UI layer
            UIApplication *app = [UIApplication sharedApplication];
            static IMP cancelAllTouchesIMP = NULL;
            if (!cancelAllTouchesIMP)
                cancelAllTouchesIMP = [app methodForSelector:@selector(_cancelAllTouches)];
            if (cancelAllTouchesIMP)
                ((void (*)(id, SEL))cancelAllTouchesIMP)(app, @selector(_cancelAllTouches));

            // Send GC button-up if left click was physically held — covers both
            // Zero Build (GC path) and Build mode (UITouch path) since either way
            // the game may have a press in-flight.
            if (buttonWasDown && gcHandler && gcInput) {
                gcHandler(gcInput, 0.0, NO);
            }
        });
    }

    // Update red dot visibility based on lock state
    updateRedDotVisibility();
}

// --------- THEOS HOOKS ---------

// Mouse movement handling with perfect PC sensitivity matching
%hook GCMouseInput

- (void)setMouseMovedHandler:(GCMouseMoved)handler {
    if (!handler) {
        %orig;
        return;
    }
    
    GCMouseMoved customHandler = ^(GCMouseInput * _Nonnull eventMouse, float deltaX, float deltaY) {
        if (!isMouseLocked) return;

        BOOL isADS = (eventMouse.rightButton.value == 1.0);

        if (!wasADSInitialized) {
            wasADS = isADS;
            wasADSInitialized = YES;
        }

        if (isADS != wasADS) {
            mouseAccumX = 0.0;
            mouseAccumY = 0.0;
            wasADS = isADS;
        }

        // BUILD MODE: Update last mouse position for UI hit detection
        if (isBuildModeEnabled) {
            UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
            UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
            if (keyWindow) {
                lastMousePosition.x += deltaX;
                lastMousePosition.y += deltaY;
                
                // Clamp to window bounds
                lastMousePosition.x = MAX(0, MIN(lastMousePosition.x, keyWindow.bounds.size.width));
                lastMousePosition.y = MAX(0, MIN(lastMousePosition.y, keyWindow.bounds.size.height));
            }
        }

        // PC FORTNITE EXACT SENSITIVITY FORMULA - OPTIMIZED
        mouseAccumX += deltaX * (isADS ? adsSensitivityX : hipSensitivityX);
        mouseAccumY += deltaY * (isADS ? adsSensitivityY : hipSensitivityY);

        int outX = (int)mouseAccumX;
        int outY = (int)mouseAccumY;

        mouseAccumX -= (double)outX;
        mouseAccumY -= (double)outY;

        if ((outX | outY) != 0) {
            handler(eventMouse, (float)outX, (float)outY);
        }
    };

    %orig(customHandler);
}

%end

// Handle scroll wheel for remapping
%hook GCMouseInput

- (void)setScrollValueChangedHandler:(void (^)(GCControllerDirectionPad* _Nonnull, float, float))handler {
    if (!handler) {
        %orig;
        return;
    }
    
    void (^customHandler)(GCControllerDirectionPad*, float, float) = ^(GCControllerDirectionPad* scroll, float x, float y) {
        // Detect scroll direction
        if (y > 0.5) {
            // Scroll up detected
            if (mouseButtonCaptureCallback != nil) {
                mouseButtonCaptureCallback(MOUSE_SCROLL_UP);
                return; // Don't pass through when capturing
            } else if (isMouseLocked) {
                handler(scroll, x, y);
            }
        } else if (y < -0.5) {
            // Scroll down detected
            if (mouseButtonCaptureCallback != nil) {
                mouseButtonCaptureCallback(MOUSE_SCROLL_DOWN);
                return; // Don't pass through when capturing
            } else if (isMouseLocked) {
                handler(scroll, x, y);
            }
        } else {
            // Normal scroll or no scroll
            if (isMouseLocked) {
                handler(scroll, x, y);
            }
        }
    };
    
    %orig(customHandler);
}

%end

// Handle mouse clicks - DUAL MODE: ZERO BUILD vs BUILD
%hook GCControllerButtonInput

- (void)setPressedChangedHandler:(GCControllerButtonValueChangedHandler)handler {
    if (!handler) {
        %orig;
        return;
    }

    GCMouse *currentMouse = GCMouse.current;
    BOOL isLeftButton = (currentMouse && currentMouse.mouseInput && 
                        currentMouse.mouseInput.leftButton == self);
    BOOL isRightButton = (currentMouse && currentMouse.mouseInput && 
                         currentMouse.mouseInput.rightButton == self);
    BOOL isMiddleButton = (currentMouse && currentMouse.mouseInput && 
                          currentMouse.mouseInput.middleButton == self);
    BOOL isAuxButton1 = (currentMouse && currentMouse.mouseInput &&
                        currentMouse.mouseInput.auxiliaryButtons.count > 0 &&
                        currentMouse.mouseInput.auxiliaryButtons[0] == self);
    BOOL isAuxButton2 = (currentMouse && currentMouse.mouseInput &&
                        currentMouse.mouseInput.auxiliaryButtons.count > 1 &&
                        currentMouse.mouseInput.auxiliaryButtons[1] == self);

    if (isRightButton) {
        // Track right-click state for both Zero Build and Build Mode
        GCControllerButtonValueChangedHandler customHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
            // CRITICAL: Handle UITouch to GC transition (Build Mode only)
            if (isBuildModeEnabled && pressed && !rightButtonIsPressed && leftButtonIsPressed && !leftClickSentToGame) {
                // Transitioning from UITouch mode to GC mode while left is held
                // We need to make the game think left button was just pressed
                
                // Cancel the UITouch first
                UIApplication *app = [UIApplication sharedApplication];
                if ([app respondsToSelector:@selector(_cancelAllTouches)]) {
                    [app performSelector:@selector(_cancelAllTouches)];
                }
                
                // Now trigger the left button handler
                // Get the left mouse button
                GCMouse *currentMouse = [GCMouse current];
                if (currentMouse && currentMouse.mouseInput && currentMouse.mouseInput.leftButton) {
                    // Use the stored game handler to send GC press
                    // dispatch_async provides a small delay (~1-2ms) that allows the game to accept the event
                    // This is the ONLY way to seamlessly transition from UITouch to GC mode
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (leftButtonGameHandler && leftButtonInput) {
                            // Send press event through the game's handler
                            leftButtonGameHandler(leftButtonInput, 1.0, YES);
                        }
                    });
                    
                    leftClickSentToGame = YES;
                }
            }
            
            rightButtonIsPressed = pressed;
            
            // Pass right-click through normally
            if (isMouseLocked) {
                handler(button, value, pressed);
            }
        };
        
        %orig(customHandler);
    } else if (isLeftButton) {
        GCControllerButtonValueChangedHandler customHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
            // Store the handler and button reference for use from right-click handler
            leftButtonGameHandler = handler;
            leftButtonInput = button;

            // ===== LOCK GESTURE: Option+Click while unlocked — suppress entirely =====
            if (isTriggerHeld && !unlockingWhileFiring) {
                if (pressed) {
                    lockClickConsumed = YES;
                    isMouseLocked = YES;
                    updateMouseLock(YES);
                }
                return; // suppress both press and release
            }
            // Suppress the release paired to a consumed lock gesture press
            if (lockClickConsumed && !pressed) {
                lockClickConsumed = NO;
                return;
            }

            if (isMouseLocked) {
                if (!isBuildModeEnabled) {
                    // ===== ZERO BUILD MODE =====
                    if (pressed) {
                        leftButtonIsPressed = YES;
                        leftClickSentToGame = YES;
                    } else {
                        leftButtonIsPressed = NO;
                        leftClickSentToGame = NO;
                    }
                    handler(button, value, pressed);
                } else {
                    // ===== BUILD MODE (new right-click toggle behavior) =====
                    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                    UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
                    
                    if (keyWindow) {
                        // Only check UI position on button press, not release
                        if (pressed) {
                            // Prevent duplicate press events
                            if (leftButtonIsPressed) {
                                return; // Already pressed, ignore duplicate
                            }
                            
                            leftButtonIsPressed = YES;
                            
                            // When right-click is held, always pass left-click as GameController
                            // When right-click is released, left-click is always UITouch
                            if (rightButtonIsPressed) {
                                // Right-click held: left-click is GameController input
                                handler(button, value, pressed);
                                leftClickSentToGame = YES;
                            } else {
                                // Right-click released: left-click is always UITouch
                                leftClickSentToGame = NO;
                                // UITouch hook will handle it at red dot position
                            }
                        } else {
                            // On release
                            if (!leftButtonIsPressed) {
                                return; // Not pressed, ignore stray release
                            }
                            
                            leftButtonIsPressed = NO;
                            
                            // CRITICAL: If we sent the press to the game handler, we MUST send the release
                            // This prevents stuck buttons regardless of right-click state changes
                            if (leftClickSentToGame) {
                                handler(button, value, pressed);
                                leftClickSentToGame = NO;
                            }
                        }
                    } else {
                        // No window, pass through but still track state
                        if (pressed) {
                            leftButtonIsPressed = YES;
                            leftClickSentToGame = YES;
                        } else {
                            leftButtonIsPressed = NO;
                            if (leftClickSentToGame) {
                                leftClickSentToGame = NO;
                            }
                        }
                        handler(button, value, pressed);
                    }
                }
            } else {
                // Mouse not locked - reset BUILD mode state
                leftButtonIsPressed = NO;
                leftClickSentToGame = NO;
            }
        };

        %orig(customHandler);
    } else if (isMiddleButton || isAuxButton1 || isAuxButton2) {
        // Capture mouse button presses for remapping
        GCControllerButtonValueChangedHandler customHandler = ^(GCControllerButtonInput * _Nonnull button, float value, BOOL pressed) {
            if (pressed) {
                // Determine which mouse button was pressed
                int buttonCode = 0;
                if (isMiddleButton) {
                    buttonCode = MOUSE_BUTTON_MIDDLE;
                } else if (isAuxButton1) {
                    buttonCode = MOUSE_BUTTON_SIDE1;
                } else if (isAuxButton2) {
                    buttonCode = MOUSE_BUTTON_SIDE2;
                }
                
                // If we're capturing for the popup, call the callback
                if (mouseButtonCaptureCallback != nil && buttonCode != 0) {
                    mouseButtonCaptureCallback(buttonCode);
                    return; // Don't pass through when capturing
                }
                
                // Pass through mouse buttons normally when mouse is locked
                if (isMouseLocked) {
                    handler(button, value, pressed);
                }
            } else {
                // Button release - always pass through when mouse locked
                if (isMouseLocked) {
                    handler(button, value, pressed);
                }
            }
        };

        %orig(customHandler);
    } else {
        %orig;
    }
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
    
    GCKeyboardValueChangedHandler customHandler = ^(GCKeyboardInput * _Nonnull keyboard, GCControllerButtonInput * _Nonnull key, GCKeyCode keyCode, BOOL pressed) {
        // PRIORITY: Key capture for popup (when adding/changing remappings)
        if (keyCaptureCallback != nil && pressed) {
            keyCaptureCallback(keyCode);
            return; // Don't pass key to game during capture
        }

        // Left Option held+click = LOCK, Left Option tap alone = UNLOCK
        if (keyCode == TRIGGER_KEY) {
            if (isPopupVisible) return;
            if (pressed) {
                isTriggerHeld = YES;
                lockClickConsumed = NO;
                unlockingWhileFiring = isMouseLocked; // already locked = unlock intent
            } else {
                isTriggerHeld = NO;
                unlockingWhileFiring = NO;
                // Only toggle if no click was consumed as a lock gesture
                if (!lockClickConsumed) {
                    isMouseLocked = !isMouseLocked;
                    updateMouseLock(isMouseLocked);
                }
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

    // Suppress touch if this is a lock gesture (Option held while unlocked)
    if (isTriggerHeld && !unlockingWhileFiring) {
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
        
        // Get window and convert red dot position to view's coordinates
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
        if (keyWindow) {
            return [view convertPoint:redDotTargetPosition fromView:keyWindow];
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
        
        // Get window and convert red dot position to view's coordinates
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        UIWindow *keyWindow = scene.keyWindow ?: scene.windows.firstObject;
        if (keyWindow) {
            return [view convertPoint:redDotTargetPosition fromView:keyWindow];
        }
        return redDotTargetPosition;
    }
    
    return originalLocation;
}

%end
