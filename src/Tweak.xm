#import "./views/popupViewController.h"
#import "./views/welcomeViewController.h"
#import "./globals.h"

#import "../lib/fishhook.h"
#import "./ue_reflection.h"
#import <sys/sysctl.h>

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <dlfcn.h>

// Forward declarations for controller helpers
static void _updateVStick(BOOL isRight);
static void resetControllerState();
static void dispatchControllerButton(NSInteger idx, BOOL pressed);
static void _setVirtualFaceButton(NSString *element, BOOL pressed);
static void _setVirtualNamedButton(SEL propSel, BOOL pressed);

static char kButtonCodeKey;


static void updateGCMouseDirectState(int code, BOOL pressed) {
    if (code != 0 && (GCKeyCode)code == GCMOUSE_DIRECT_KEY) {
        isGCMouseDirectActive = pressed;
    }
}

#ifndef kCGHIDEventTap
#define kCGHIDEventTap 0
#endif

typedef uint64_t CGEventFlags;
typedef struct __CGEvent *CGEventRef;

static CGEventRef (*_CGEventCreateKeyboardEvent)(void *source, uint16_t virtualKey, bool keyDown) = NULL;
static void (*_CGEventSetFlags)(CGEventRef event, CGEventFlags flags) = NULL;
static CGEventFlags (*_CGEventGetFlags)(CGEventRef event) = NULL;
static void (*_CGEventPost)(int tap, CGEventRef event) = NULL;

typedef uint16_t UniChar;
typedef unsigned long UniCharCount;
static void (*_CGEventKeyboardGetUnicodeString)(CGEventRef event, UniCharCount maxStringLength, UniCharCount *actualStringLength, UniChar unicodeString[]) = NULL;
static void (*_CGEventKeyboardSetUnicodeString)(CGEventRef event, UniCharCount stringLength, const UniChar unicodeString[]) = NULL;

#define kCGEventFlagMaskAlphaShift 0x00010000
#define kCGEventFlagMaskShift      0x00020000

// CGEventTap Types and Prototypes
typedef uint32_t CGEventTapProxy;
typedef uint32_t CGEventType; 
typedef int CGEventTapPlacement;
typedef int CGEventTapOptions;
typedef CGEventRef (*CGEventTapCallBack)(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);

static CFMachPortRef (*_CGEventTapCreate)(int tap, CGEventTapPlacement place, CGEventTapOptions options, uint64_t eventsOfInterest, CGEventTapCallBack callback, void *refcon) = NULL;
static void (*_CGEventTapEnable)(CFMachPortRef tap, bool enable) = NULL;

extern "C" {
    #define kCGEventLeftMouseDown 1
    #define kCGEventLeftMouseUp 2
    #define kCGEventLeftMouseDragged 3
    #define kCGEventRightMouseDown 5
    #define kCGEventRightMouseUp 6
    #define kCGEventRightMouseDragged 7
    #define kCGEventOtherMouseDown 25
    #define kCGEventOtherMouseUp 26
    #define kCGEventOtherMouseDragged 8
    #define kCGMouseEventButtonNumber 3
    #define kCGHeadInsertEventTap 0
    #define kCGEventTapOptionDefault 0
}
static void (*_CGEventSetIntegerValueField)(CGEventRef event, int field, int64_t value) = NULL;
static int64_t (*_CGEventGetIntegerValueField)(CGEventRef event, int field) = NULL;

static CGEventRef mouseButtonTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);
static BOOL _isMouseButtonSuppressed(int code);

#define kCGEventSourceUserData 42

@interface UITouch (Private)
- (void)_setType:(int)type;
- (void)setType:(int)type;
- (void)_setPathIndex:(int)index;
- (void)_setPathIdentity:(int)identity;
- (void)setWindow:(UIWindow *)window;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setIsTap:(BOOL)isTap;
- (void)_setIsFirstTouchForView:(BOOL)firstTouch;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
@end

@interface UITouchesEvent : UIEvent
- (id)_init;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayedDelivery;
@property (nonatomic, assign) int singleAllowableExternalTouchPathIndex;
@end

// Pre-calculated sensitivity multipliers (computed once at startup via recalculateSensitivities())
@interface GCPhysicalInputProfile (FnTweak)
- (id)elementForName:(NSString *)name;
@end

// Formula: (BASE_XY_SENSITIVITY / 100) × (Look% / 100) × MACOS_TO_PC_SCALE

// macOS VK → GCKeyCode map (USB HID)
static const uint16_t nsVKToGC[128] = {
    [0]=4,  [1]=22, [2]=7,  [3]=9,  [4]=11, [5]=10, [6]=29, [7]=27,
    [8]=6,  [9]=25, [10]=0, [11]=5, [12]=20,[13]=26,[14]=8, [15]=21,
    [16]=28,[17]=23,
    [18]=30,[19]=31,[20]=32,[21]=33,[22]=35,[23]=34,
    [24]=46,[25]=38,[26]=36,[27]=45,[28]=37,[29]=39,
    [30]=48,[31]=18,[32]=24,[33]=47,[34]=12,[35]=19,
    [36]=40,[37]=15,[38]=13,[39]=52,[40]=14,[41]=51,
    [42]=49,[43]=54,[44]=56,[45]=17,[46]=16,[47]=55,
    [48]=43,[49]=44,[50]=53,[51]=42,[52]=0, [53]=41,
    [54]=231,[55]=227,[56]=225,[57]=57,
    [58]=226,[59]=224,[60]=229,[61]=230,[62]=228,[63]=0,[64]=0,
    [65]=99,[66]=0, [67]=85,[69]=83,[70]=0, [71]=71,[72]=0,
    [75]=84,[76]=88,[77]=0, [78]=87,[79]=79,[80]=80,[81]=81,
    [82]=82,[83]=98,[84]=89,[85]=90,[86]=91,[87]=92,[88]=93,
    [89]=94,[90]=95,[91]=96,[92]=97,[96]=62,[97]=63,[98]=64,
    [99]=65,[100]=66,[101]=67,[102]=68,[103]=69,[104]=70,
    [105]=71,[106]=77,[107]=86,[108]=0, [109]=78,[110]=76,
    [111]=69,[112]=0, [113]=0, [114]=73,[115]=74,[116]=75,
    [117]=76,[118]=61,[119]=77,[120]=59,[121]=78,[122]=58,
    [123]=80,[124]=79,[125]=81,[126]=82,
};
static uint16_t gcToNSVK[256];

static void preloadChickenGIF(void);
static void showChickenDinner(void);
static void dismissChickenDinner(void);
static void showDestroyGIF(void);

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
                    __block void (^doSearch)(void) = nil;
                    __weak __block void (^weakDoSearch)(void) = nil;
                    
                    doSearch = [^{
                        // Redefine as __strong inside to avoid retain cycle
                        void (^strongDoSearch)(void) = weakDoSearch;
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
            // Keep window frame in sync during destroy GIF
            if (cw && popupWindow) cw.frame = popupWindow.frame;

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
        void (^__block poll)(void) = nil;
        __weak __block void (^weakPoll)(void) = nil;
        
        poll = [^{
            void (^strongPoll)(void) = weakPoll;
            if (frameIdx >= frameCount) {
                [destroyLink invalidate];
                destroyLink = nil;
                iv.image = frames[frameCount - 1]; // last frame, no loop
                cw.hidden = YES;
                isPopupVisible = NO;
                popupWindow.hidden = YES;
                updateBlueDotVisibility();
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

// --------- MOUSE ADS STATE ---------
static GCMouseMoved g_originalMouseHandler = nil;
// mouseAccum, wasADS, wasADSInitialized moved to globals.h/m

// --------- FORWARD DECLARATIONS ---------
// Needed by the NSEvent kbMonitor block inside %ctor, which compiles before
// the definitions that appear later in the file.
static BOOL isTriggerHeld        = NO;
static BOOL remappedKeysState[512] = {NO};
static BOOL remappedMouseButtonsState[MOUSE_REMAP_COUNT] = {NO};
static void createPopup(void);
static void updateMouseLock(BOOL value, CGPoint warpPos);


@interface FnInputPulse : NSObject
- (void)onDisplayTick:(CADisplayLink *)sender;
@end

static BOOL wasLocked = YES;
static id g_virtualGamepad = nil; // Cached for zero-latency access
static id g_vctrl_cached_ls = nil; // Cached Left Stick
static id g_vctrl_cached_rs = nil; // Cached Right Stick

// Sticky input tracking: remember the intended state of every virtual button
static BOOL g_vctrlButtonTargetStates[FnCtrlButtonCount] = {NO};

@implementation FnInputPulse
- (void)onDisplayTick:(CADisplayLink *)sender {
    // ENFORCE BLUE DOT VISIBILITY: Always hide if settings pane is closed
    if (!isPopupVisible && blueDotIndicator && !blueDotIndicator.hidden) {
        blueDotIndicator.hidden = YES;
    }

    // Only reset if truly idle (unlocked AND not holding Option trigger)
    if ((!isMouseLocked && !isTriggerHeld) || isPopupVisible) {
        // IMPORTANT: Reset gyro velocity and virtual controller state when unlocked
        // so it doesn't keep moving in the last direction forever.
        ue_apply_gyro_velocity(0, 0);
        if (wasLocked) { resetControllerState(); wasLocked = NO; }
        return;
    }
    wasLocked = YES;
    
    // ── Zero-Latency Gyro-Mouse Proxy (Demand-Driven) ──
    // The actual calculation now happens in the reflection layer polling hook (ue_reflection.m).
    // mouseAccumX/Y are consumed directly by the game engine's request.
    
    // --- Latch Virtual Gamepad ---
    if (!g_virtualGamepad && g_virtualController) {
        g_virtualGamepad   = ue_get_extended_gamepad(g_virtualController);
        g_vctrl_cached_ls  = (g_virtualGamepad) ? [g_virtualGamepad leftThumbstick] : nil;
        g_vctrl_cached_rs  = (g_virtualGamepad) ? [g_virtualGamepad rightThumbstick] : nil;
    }
    
    // --- Gyro Suppression (Direct Mouse active) ---
    if (isGCMouseDirectActive) {
        ue_apply_gyro_velocity(0, 0);
    }

    // --- Sticky Buttons (Option Mode) ---
    // If holding Option, the game might try to reset inputs during mode switches.
    // We re-assert every pressed button to keep movement/actions continuous.
    if (isTriggerHeld) {
        for (int i = 0; i < FnCtrlButtonCount; i++) {
            if (g_vctrlButtonTargetStates[i]) {
                dispatchControllerButton(i, YES);
            }
        }
    }

    // --- Constant Stick Polling ---
    // Update sticks every frame to ensure smooth movement even during transitions.
    _updateVStick(NO);
    _updateVStick(YES);
}
@end

// inputPulseHelper singleton moved to global scope
static FnInputPulse *g_inputPulseHelper = nil;

// --------- VIRTUAL CONTROLLER DISPATCH ---------
// Uses ue_reflection.h so values propagate into UE's input subsystem.
// ue_reflect_button_press/release: calls _setValue: on GCControllerButtonInput
//   — updates the ivar AND fires valueChangedHandler that UE polls.
// ue_reflect_thumbstick: calls _setValueX:Y: (or per-axis fallback) on the
//   GCControllerDirectionPad — drives the actual extendedGamepad axes UE reads.
// setPosition:forDirectionPadElement: (public API) only updates the virtual
//   controller's internal mirror and never reaches extendedGamepad — that's
//   why the old approach produced no movement.

// Digital stick state arrays
static BOOL dpadState[4]   = {}; // up/down/left/right
static BOOL lstickState[4] = {};
static BOOL rstickState[4] = {};

// Drive a face button (A/B/X/Y) — triple-fire: valueChangedHandler + pressedChangedHandler + _setValue:
static void _setVirtualFaceButton(NSString *element, BOOL pressed) {
    float val = pressed ? 1.0f : 0.0f;
    for (GCController *ctrl in GCController.controllers) {
        GCExtendedGamepad *eg = ctrl.extendedGamepad;
        if (!eg) continue;

        GCControllerButtonInput *btn = nil;

        // 1. Try elementForName: (Modern and robust fallback for non-selector buttons)
        if (element && [eg respondsToSelector:@selector(elementForName:)]) {
            btn = (GCControllerButtonInput *)[(id)eg elementForName:element];
        }

        // 2. Fallback to selectors if elementForName failed or is unavailable
        if (!btn || ![btn isKindOfClass:GCControllerButtonInput.class]) {
            SEL propSel = nil;
            if      ([element isEqualToString:@"Button A"])       propSel = @selector(buttonA);
            else if ([element isEqualToString:@"Button B"])       propSel = @selector(buttonB);
            else if ([element isEqualToString:@"Button X"])       propSel = @selector(buttonX);
            else if ([element isEqualToString:@"Button Y"])       propSel = @selector(buttonY);
            else if ([element isEqualToString:@"Menu"])           propSel = @selector(buttonMenu);
            else if ([element isEqualToString:@"Options"])        propSel = @selector(buttonOptions);
            else if ([element isEqualToString:@"Home"])           propSel = @selector(buttonHome);
            
            // Check for GameController constants just in case they are available
            if (!propSel) {
                if ([element isEqualToString:@"Button A"]) propSel = @selector(buttonA);
                // ... (simplified literal checks above are better)
            }

            if (propSel && [eg respondsToSelector:propSel]) {
                btn = ((id(*)(id,SEL))objc_msgSend)(eg, propSel);
            }
        }

        if (!btn || ![btn isKindOfClass:GCControllerButtonInput.class]) continue;

        if (btn.valueChangedHandler)   btn.valueChangedHandler(btn, val, pressed);
        if (btn.pressedChangedHandler) btn.pressedChangedHandler(btn, val, pressed);
        if ([btn respondsToSelector:@selector(_setValue:)]) {
            NSMethodSignature *sig = [btn methodSignatureForSelector:@selector(_setValue:)];
            if (sig && strcmp([sig getArgumentTypeAtIndex:2], "f") == 0) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:@selector(_setValue:)];
                [inv setTarget:btn];
                [inv setArgument:&val atIndex:2];
                [inv invoke];
            }
        }
    }
}

// Drive a thumbstick from a digital direction state array
// Iterates GCController.controllers and fires _setValueX:Y: / fallback on each
static void _updateVStick(BOOL isRight) {
    id dpad = isRight ? g_vctrl_cached_rs : g_vctrl_cached_ls;
    if (!dpad) {
        // Fallback: try to latch if missing (rare case)
        if (!g_virtualGamepad && g_virtualController) {
            g_virtualGamepad = ue_get_extended_gamepad(g_virtualController);
            g_vctrl_cached_ls = [g_virtualGamepad leftThumbstick];
            g_vctrl_cached_rs = [g_virtualGamepad rightThumbstick];
        }
        dpad = isRight ? g_vctrl_cached_rs : g_vctrl_cached_ls;
        if (!dpad) return;
    }
    
    BOOL *state = isRight ? rstickState : lstickState;
    float dx = 0, dy = 0;
    if (state[0]) dy += 1.0f; // Up
    if (state[1]) dy -= 1.0f; // Down
    if (state[2]) dx -= 1.0f; // Left
    if (state[3]) dx += 1.0f; // Right
    
    float len = sqrtf(dx*dx + dy*dy);
    if (len > 1.0f) { dx /= len; dy /= len; }
    
    ue_reflect_thumbstick(dpad, dx, dy);
}

// Re-assert every currently pressed input to override game engine internal resets
static void reassertAllInputs() {
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        if (g_vctrlButtonTargetStates[i]) {
            dispatchControllerButton(i, YES);
        }
    }
    _updateVStick(NO);
    _updateVStick(YES);
}

static void resetControllerState() {
    // 1. Reset digital states
    for (int i=0; i<4; i++) {
        dpadState[i] = NO;
        lstickState[i] = NO;
        rstickState[i] = NO;
    }
    
    // 2. Force thumbsticks to neutral
    _updateVStick(NO);
    _updateVStick(YES);
    
    // 3. Reset all face and shoulder buttons
    _setVirtualFaceButton((NSString *)GCInputButtonA, NO);
    _setVirtualFaceButton((NSString *)GCInputButtonB, NO);
    _setVirtualFaceButton((NSString *)GCInputButtonX, NO);
    _setVirtualFaceButton((NSString *)GCInputButtonY, NO);
    
    _setVirtualNamedButton(NSSelectorFromString(@"leftShoulder"), NO);
    _setVirtualNamedButton(NSSelectorFromString(@"rightShoulder"), NO);
    _setVirtualNamedButton(NSSelectorFromString(@"leftTrigger"), NO);
    _setVirtualNamedButton(NSSelectorFromString(@"rightTrigger"), NO);
    _setVirtualFaceButton(@"Options", NO);
    _setVirtualFaceButton(@"Menu", NO);
    _setVirtualFaceButton(@"Home", NO);

    dispatchControllerButton(FnCtrlL3, NO);
    dispatchControllerButton(FnCtrlR3, NO);
}

// Drive a shoulder or trigger button by its extendedGamepad property selector.
// Uses the proven triple-fire approach: valueChangedHandler + pressedChangedHandler + _setValue:
static void _setVirtualNamedButton(SEL propSel, BOOL pressed) {
    float val = pressed ? 1.0f : 0.0f;
    for (GCController *ctrl in GCController.controllers) {
        GCExtendedGamepad *eg = ctrl.extendedGamepad;
        if (!eg) continue;

        GCControllerButtonInput *btn = nil;
        
        // 1. Try selector if provided
        if (propSel && [eg respondsToSelector:propSel]) {
            btn = ((id(*)(id,SEL))objc_msgSend)(eg, propSel);
        }
        
        // 2. Fallback to elementForName if we can derive a name (e.g. for triggers/shoulders)
        if (!btn && [eg respondsToSelector:@selector(elementForName:)]) {
            NSString *selStr = NSStringFromSelector(propSel);
            if ([selStr isEqualToString:@"leftShoulder"])  btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Left Shoulder"];
            if ([selStr isEqualToString:@"rightShoulder"]) btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Right Shoulder"];
            if ([selStr isEqualToString:@"leftTrigger"])   btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Left Trigger"];
            if ([selStr isEqualToString:@"rightTrigger"])  btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Right Trigger"];
        }

        if (!btn || ![btn isKindOfClass:GCControllerButtonInput.class]) continue;
        
        if (btn.valueChangedHandler)   btn.valueChangedHandler(btn, val, pressed);
        if (btn.pressedChangedHandler) btn.pressedChangedHandler(btn, val, pressed);
        if ([btn respondsToSelector:@selector(_setValue:)]) {
            NSMethodSignature *sig = [btn methodSignatureForSelector:@selector(_setValue:)];
            if (sig && strcmp([sig getArgumentTypeAtIndex:2], "f") == 0) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:@selector(_setValue:)];
                [inv setTarget:btn];
                [inv setArgument:&val atIndex:2];
                [inv invoke];
            }
        }
    }
}

// Synthesise a keyboard key event through storedKeyboardHandler.
// Attempts to get the actual button object for the target keyCode.
static void _sendKeyEvent(GCKeyCode kc, BOOL pressed) {
    if (!storedKeyboardHandler) return;
    
    // Attempt dynamic retrieval if stored pointer is missing
    if (!storedKeyboardInput) {
        if (@available(iOS 14, *)) {
            GCKeyboard *kb = [GCKeyboard coalescedKeyboard];
            if (kb) storedKeyboardInput = kb.keyboardInput;
        }
    }
    
    if (!storedKeyboardInput) return;

    // Attempt to get the actual button for this key
    GCControllerButtonInput *btn = nil;
    if ([storedKeyboardInput respondsToSelector:@selector(buttonForKeyCode:)]) {
        btn = [storedKeyboardInput buttonForKeyCode:kc];
    }
    
    if (!btn) {
        // Fallback to "Key A" as a dummy carrier if the target button is nil
        btn = [storedKeyboardInput buttonForKeyCode:GCKeyCodeKeyA];
    }
    
    if (btn) {
        storedKeyboardHandler(storedKeyboardInput, btn, kc, pressed);
    }
}

// Dual Injection: Framework-level (MFi) + System-level (CGEvent)
static void _sendDualKeyEvent(GCKeyCode kc, BOOL pressed) {
    // 0. Direct Mouse Toggle
    if (kc != 0 && kc == GCMOUSE_DIRECT_KEY) {
        updateGCMouseDirectState((int)kc, pressed);
        // pass through to game
    }

    // 1. Mouse Action Support removed (as requested: GC clicks should NEVER fire)

    // 2. Framework-level injection
    _sendKeyEvent(kc, pressed);
    
    // 3. System-level injection (if it's a standard key)
    if ((int)kc < 256) {
        uint16_t rv = gcToNSVK[(uint8_t)kc];
        if (rv > 0 || (int)kc == 4) {
            if (_CGEventCreateKeyboardEvent && _CGEventPost) {
                CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, rv, pressed);
                if (ev) {
                    _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337);
                    _CGEventPost(kCGHIDEventTap, ev);
                    CFRelease(ev);
                }
            }
        }
    }
}

// ── L3/R3 Injection Helper ──────────────────────────────────────────────────
static id getInjectedButton(GCExtendedGamepad *gamepad, NSString *key) {
    if (!gamepad) return nil;
    static char const * const kInjectedButtonsKey = "kInjectedButtonsKey";
    NSMutableDictionary *dict = objc_getAssociatedObject(gamepad, kInjectedButtonsKey);
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(gamepad, kInjectedButtonsKey, dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id btn = dict[key];
    if (!btn) {
        // Use the Logos-defined subclass to avoid instantiation crashes
        btn = [[NSClassFromString(@"FnInjectedButton") alloc] init];
        if (btn) dict[key] = btn;
    }
    return btn;
}

// ── Logos Subclass for Safe Mocking ──────────────────────────────────────────
@interface FnInjectedButton : GCControllerButtonInput
- (BOOL)isPressed;
- (BOOL)pressed;
- (float)value;
- (void)_setValue:(float)v;
@end

%subclass FnInjectedButton : GCControllerButtonInput

- (BOOL)isPressed { 
    return [objc_getAssociatedObject(self, @selector(isPressed)) boolValue]; 
}

- (BOOL)pressed { return [self isPressed]; }

- (float)value { 
    return [objc_getAssociatedObject(self, @selector(value)) floatValue]; 
}

- (void)_setValue:(float)v { 
    BOOL pressed = (v > 0.5);
    
    // Fire KVO for all possible polling patterns
    [self willChangeValueForKey:@"value"];
    [self willChangeValueForKey:@"isPressed"];
    [self willChangeValueForKey:@"pressed"];
    
    objc_setAssociatedObject(self, @selector(value), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, @selector(isPressed), @(pressed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [self didChangeValueForKey:@"value"];
    [self didChangeValueForKey:@"isPressed"];
    [self didChangeValueForKey:@"pressed"];

    // Trigger ALL possible registered blocks
    if (self.valueChangedHandler)   self.valueChangedHandler(self, v, pressed);
    if (self.pressedChangedHandler) self.pressedChangedHandler(self, v, pressed);
}
%end

// Master dispatcher — routes FnControllerButton index to the right mechanism
static void dispatchControllerButton(NSInteger idx, BOOL pressed) {
    // Update sticky tracker
    if (idx >= 0 && idx < FnCtrlButtonCount) g_vctrlButtonTargetStates[idx] = pressed;

    if (!g_virtualGamepad) {
        if (g_virtualController) g_virtualGamepad = ue_get_extended_gamepad(g_virtualController);
        if (!g_virtualGamepad) return;
    }

    switch (idx) {
        // ── Sticks via ue_reflect_thumbstick ──────────────────────────────
        case FnCtrlLeftStickUp:    lstickState[0] = pressed; _updateVStick(NO);  break;
        case FnCtrlLeftStickDown:  lstickState[1] = pressed; _updateVStick(NO);  break;
        case FnCtrlLeftStickLeft:  lstickState[2] = pressed; _updateVStick(NO);  break;
        case FnCtrlLeftStickRight: lstickState[3] = pressed; _updateVStick(NO);  break;

        case FnCtrlRightStickUp:    rstickState[0] = pressed; _updateVStick(YES); break;
        case FnCtrlRightStickDown:  rstickState[1] = pressed; _updateVStick(YES); break;
        case FnCtrlRightStickLeft:  rstickState[2] = pressed; _updateVStick(YES); break;
        case FnCtrlRightStickRight: rstickState[3] = pressed; _updateVStick(YES); break;

        // ── D-pad state tracking ──────────────────────────────────────────
        case FnCtrlDpadUp:    dpadState[0] = pressed; break;
        case FnCtrlDpadDown:  dpadState[1] = pressed; break;
        case FnCtrlDpadLeft:  dpadState[2] = pressed; break;
        case FnCtrlDpadRight: dpadState[3] = pressed; break;

        // ── Stick clicks (L3/R3): Hybrid approach (Native/Injected + Keyboard) ──
        case FnCtrlL3:
        case FnCtrlR3: {
            // 1. Try native/injected controller input
            GCControllerButtonInput *btn = (idx == FnCtrlL3) ? [g_virtualGamepad leftThumbstickButton] : [g_virtualGamepad rightThumbstickButton];
            if (btn) {
                float val = pressed ? 1.0f : 0.0f;
                static SEL setValueSel = NULL;
                if (!setValueSel) setValueSel = NSSelectorFromString(@"_setValue:");
                
                if ([btn respondsToSelector:setValueSel]) {
                    typedef void (*SetValueFunc)(id, SEL, float);
                    ((SetValueFunc)objc_msgSend)(btn, setValueSel, val);
                } else {
                    if (btn.valueChangedHandler)   btn.valueChangedHandler(btn, val, pressed);
                    if (btn.pressedChangedHandler) btn.pressedChangedHandler(btn, val, pressed);
                }
            }
            break;
        }
        case FnCtrlOptions: {
            _setVirtualFaceButton(@"Menu", pressed); break;
        }
        case FnCtrlShare: {
            _setVirtualFaceButton(@"Options", pressed); break;
        }
        case FnCtrlHome: {
            _setVirtualFaceButton(@"Home", pressed); break;
        }
        default: break;
    }

    // Removed circular re-injection loop that was causing remapped source keys 
    // (like ESC mapped to Button B) to be re-fired into the game engine.

    // Virtual Gamepad Face Buttons and Shoulders
    switch (idx) {
        case FnCtrlButtonA: _setVirtualFaceButton(GCInputButtonA, pressed); break;
        case FnCtrlButtonB: _setVirtualFaceButton(GCInputButtonB, pressed); break;
        case FnCtrlButtonX: _setVirtualFaceButton(GCInputButtonX, pressed); break;
        case FnCtrlButtonY: _setVirtualFaceButton(GCInputButtonY, pressed); break;
        case FnCtrlL1: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"leftShoulder");
            _setVirtualNamedButton(s, pressed); break;
        }
        case FnCtrlR1: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"rightShoulder");
            _setVirtualNamedButton(s, pressed); break;
        }
        case FnCtrlL2: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"leftTrigger");
            _setVirtualNamedButton(s, pressed); break;
        }
        case FnCtrlR2: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"rightTrigger");
            _setVirtualNamedButton(s, pressed); break;
        }
        default: break;
    }

    // D-pad drive
    if (idx >= FnCtrlDpadUp && idx <= FnCtrlDpadRight) {
        float dx = 0, dy = 0;
        if (dpadState[0]) dy += 1.0f;
        if (dpadState[1]) dy -= 1.0f;
        if (dpadState[2]) dx -= 1.0f;
        if (dpadState[3]) dx += 1.0f;
        for (GCController *ctrl in GCController.controllers) {
            GCExtendedGamepad *eg = ctrl.extendedGamepad;
            if (eg) ue_reflect_thumbstick(eg.dpad, dx, dy);
        }
    }
}


// ── Mapping Helpers ──────────────────────────────────────────────────────────
// (Obsolete functions removed — logic moved to caller loops for multi-bind support)

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


// Category to add pan gesture handling to the blue dot indicator
@interface UIView (BlueDotDragging)
- (void)handleBluePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIView (BlueDotDragging)
- (void)handleBluePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.superview];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        CGRect bounds = self.superview.bounds;
        newCenter.x = MAX(10, MIN(bounds.size.width  - 10, newCenter.x));
        newCenter.y = MAX(10, MIN(bounds.size.height - 10, newCenter.y));
        self.center = newCenter;
        blueDotPosition = newCenter;
        [gesture setTranslation:CGPointZero inView:self.superview];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        NSDictionary *posDict = @{@"x": @(blueDotPosition.x), @"y": @(blueDotPosition.y)};
        [[NSUserDefaults standardUserDefaults] setObject:posDict forKey:kBlueDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}
@end

%ctor {
    // Initialize Gyro-Mouse Proxy hooks
    ue_init_gyro_hooks();

    // Fishhook for device spoofing
    struct rebinding rebindings[] = {
        {"sysctl", (void *)pt_sysctl, (void **)&orig_sysctl},
        {"sysctlbyname", (void *)pt_sysctlbyname, (void **)&orig_sysctlbyname}
    };
    rebind_symbols(rebindings, 2);

    NSString* currentVersion = @"4.0.0";
    NSString* lastVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.lastSeenVersion"];

    if (!lastVersion || ![lastVersion isEqualToString:currentVersion]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kKeyRemapKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSeenVersion"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSuppressed"];
        [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"fnmactweak.lastSeenVersion"];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];



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
    // POPUP_KEY = GCKeyCodeKeyP; // Removed as requested
    
    NSDictionary *savedSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSettingsKey];
    if (savedSettings) {
        float v;
        v = [savedSettings[kBaseXYKey] floatValue]; if (v > 0) BASE_XY_SENSITIVITY = v;
        v = [savedSettings[kScaleKey]  floatValue]; if (v > 0) MACOS_TO_PC_SCALE   = v;
        v = [savedSettings[kGyroMultiplierKey] floatValue]; if (v > 0) GYRO_MULTIPLIER = v;
        GCMOUSE_DIRECT_KEY = (GCKeyCode)[savedSettings[kGCMouseDirectKey] intValue];
    }

    recalculateSensitivities();
    loadKeyRemappings();
    loadFortniteKeybinds();
    loadControllerMappings();

    // Install OS-level mouse button tap (Deeper than NSEvent monitor)
    void *cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW);
    if (cgHandle) {
        _CGEventTapCreate = (CFMachPortRef (*)(int, int, int, uint64_t, CGEventTapCallBack, void *))dlsym(cgHandle, "CGEventTapCreate");
        _CGEventTapEnable = (void (*)(CFMachPortRef, bool))dlsym(cgHandle, "CGEventTapEnable");
    }

    if (_CGEventTapCreate && _CGEventTapEnable) {
        uint64_t keyboardMask = (1ULL << 10) | (1ULL << 11) | (1ULL << 12); // KeyDown, KeyUp, FlagsChanged
        uint64_t mouseMask = (1ULL << kCGEventOtherMouseDown) | (1ULL << kCGEventOtherMouseUp) | (1ULL << kCGEventOtherMouseDragged);
        CFMachPortRef eventTap = _CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                                  keyboardMask | mouseMask,
                                                  mouseButtonTapCallback, NULL);
        if (eventTap) {
            CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
            _CGEventTapEnable(eventTap, true);
        }
    }

    // ── GCVirtualController — connect after UIKit is ready ───────────────────
    // Required for controller-mode button/stick/trigger dispatching.
    // cfg.elements must include every button we ever want to drive.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (@available(iOS 15, *)) {
                GCVirtualControllerConfiguration *cfg =
                    [[GCVirtualControllerConfiguration alloc] init];
                // Only include elements GCVirtualController actually supports.
                // Extra elements (shoulders, triggers, dpad, etc.) cause
                // connectWithReplyHandler: to fail and g_virtualController.controller
                // returns nil, breaking _setValue: on every button.
                cfg.elements = [NSSet setWithObjects:
                    GCInputLeftThumbstick,
                    GCInputRightThumbstick,
                    GCInputButtonA, GCInputButtonB,
                    GCInputButtonX, GCInputButtonY,
                    GCInputLeftShoulder,
                    GCInputRightShoulder,
                    GCInputLeftTrigger,
                    GCInputRightTrigger,
                    nil];
                if ([cfg respondsToSelector:@selector(setHidden:)]) cfg.hidden = YES;
                g_virtualController = [GCVirtualController virtualControllerWithConfiguration:cfg];
                
                // --- 120Hz SYNCED INJECTION ---
                g_inputPulseHelper = [[FnInputPulse alloc] init];
                CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:g_inputPulseHelper selector:@selector(onDisplayTick:)];
                [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

                SEL connectSel = NSSelectorFromString(@"connectWithReplyHandler:");
                void (^reply)(NSError *) = ^(NSError *error) {
                    (void)error;
                };
                if ([g_virtualController respondsToSelector:connectSel])
                    ((void(*)(id,SEL,id))objc_msgSend)(g_virtualController, connectSel, reply);
            }
        });
    }];

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
    // Bypasses GCKit entirely to catch true hardware scroll ticks/keys.
    Class nsEventClass = NSClassFromString(@"NSEvent");
    if (nsEventClass) {
        // ── Keyboard/Scroll Remapping Root-Level Support ────────────────────
        if (!_CGEventPost) {
            void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW);
            if (cg) {
                _CGEventCreateKeyboardEvent = (CGEventRef(*)(void*,uint16_t,bool))dlsym(cg, "CGEventCreateKeyboardEvent");
                _CGEventSetFlags = (void(*)(CGEventRef,CGEventFlags))dlsym(cg, "CGEventSetFlags");
                _CGEventGetFlags = (CGEventFlags(*)(CGEventRef))dlsym(cg, "CGEventGetFlags");
                _CGEventPost = (void(*)(int,CGEventRef))dlsym(cg, "CGEventPost");
                _CGEventSetIntegerValueField = (void(*)(CGEventRef,int,int64_t))dlsym(cg, "CGEventSetIntegerValueField");
                _CGEventGetIntegerValueField = (int64_t(*)(CGEventRef,int))dlsym(cg, "CGEventGetIntegerValueField");
                _CGEventKeyboardGetUnicodeString = (void(*)(CGEventRef,UniCharCount,UniCharCount*,UniChar[]))dlsym(cg, "CGEventKeyboardGetUnicodeString");
                _CGEventKeyboardSetUnicodeString = (void(*)(CGEventRef,UniCharCount,const UniChar[]))dlsym(cg, "CGEventKeyboardSetUnicodeString");
            }
        }

        static BOOL gcToNSVKInitialized = NO;
        if (!gcToNSVKInitialized) {
            memset(gcToNSVK, 0, sizeof(gcToNSVK));
            for (int i = 0; i < 128; i++) {
                if (nsVKToGC[i] != 0 && nsVKToGC[i] < 256) gcToNSVK[nsVKToGC[i]] = (uint16_t)i;
            }
            gcToNSVKInitialized = YES;
        }

        static SEL keyCodeSel2  = NULL;
        static SEL modFlagsSel2 = NULL;
        static SEL typeSel3     = NULL;
        if (!keyCodeSel2)  keyCodeSel2  = NSSelectorFromString(@"keyCode");
        if (!modFlagsSel2) modFlagsSel2 = NSSelectorFromString(@"modifierFlags");
        if (!typeSel3)     typeSel3     = NSSelectorFromString(@"type");

        // Added (1ULL << 25) | (1ULL << 26) for OtherMouse events (M3, M4, etc)
        unsigned long long keyMask = (1ULL << 1) | (1ULL << 2) | (1ULL << 3) | (1ULL << 4) | (1ULL << 5) | (1ULL << 6) | (1ULL << 7) | (1ULL << 8) | (1ULL << 10) | (1ULL << 11) | (1ULL << 12) | (1ULL << 25) | (1ULL << 26);

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
            // Safety: Only handle if app is active
            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return event;

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
            
            // Check unified Keybinds tab mappings
            if (kc == 0 && scrollCode < 10200)
                kc = fortniteRemapArray[scrollCode];
            
            // PRIORITY 1: Handle User UI overrides (Capture Mode)
            // Even if the mouse is unlocked (we are in the Tweak Settings Menu),
            // this needs to be able to catch the scroll direction!
            if (mouseButtonCaptureCallback != nil || keyCaptureCallback != nil) {
              if (mouseButtonCaptureCallback) mouseButtonCaptureCallback(scrollCode);
              else if (keyCaptureCallback) keyCaptureCallback((GCKeyCode)scrollCode);
              return nil;
            }

            // PRIORITY 2: TYPING MODE bypass
            if (isTypingModeEnabled) return event;

            // PRIORITY 3: CONTROLLER MODE mapping
            if (isControllerModeEnabled && !isPopupVisible) {
                BOOL isMappedToController = NO;
                
                // A. Custom vctrl remaps
                NSSet *tgts = vctrlCookedRemappings[@(scrollCode)];
                for (NSNumber *tgt in tgts) {
                    int vbtn = [tgt intValue];
                    isMappedToController = YES;
                    if (isMouseLocked || isTriggerHeld) {
                        dispatchControllerButton(vbtn, YES);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.015 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            dispatchControllerButton(vbtn, NO);
                        });
                    }
                }
                
                // B. Hardware controller mapping (Main Tab)
                for (int i = 0; i < FnCtrlButtonCount; i++) {
                    if (controllerMappingArray[i] == scrollCode) {
                        isMappedToController = YES;
                        if (isMouseLocked || isTriggerHeld) {
                            dispatchControllerButton(i, YES);
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.015 * NSEC_PER_SEC)),
                                           dispatch_get_main_queue(), ^{
                                dispatchControllerButton(i, NO);
                            });
                        }
                    }
                }
                
                if (isMappedToController) return nil; // Always consume if remapped to controller
            }

            // PRIORITY 3: KEYBOARD/ACTION mapping
            // If a keybind is mapped for this scroll direction, ALWAYS consume the
            // hardware event — never let raw scroll reach GCKit even when unlocked.
            // Exception: if the P settings panel is open, let scroll through.
            if (kc != 0 && !isPopupVisible) {
                if (isMouseLocked) {
                    // Inject with a small delay to ensure game registers the press (Rapid Fire)
                    _sendDualKeyEvent(kc, YES);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        _sendDualKeyEvent(kc, NO);
                    });
                }
                return nil; // consume remapped scroll
            }

            // No keybind — normal scroll behavior requires lock
            if (!isMouseLocked) return event;

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

        static BOOL prevOptionHeld2 = NO;

        id (^kbMonitor)(id) = ^id(id event) {
            // Safety: Only handle if app is active
            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return event;

            // Avoid recursion from our own injected events
            static SEL cgEventSel = NULL;
            if (!cgEventSel) cgEventSel = NSSelectorFromString(@"CGEvent");
            CGEventRef cgEv = ((CGEventRef(*)(id,SEL))objc_msgSend)(event, cgEventSel);
            if (cgEv && _CGEventGetIntegerValueField(cgEv, kCGEventSourceUserData) == 0x1337) return event;
            NSUInteger evType = ((NSUInteger(*)(id,SEL))objc_msgSend)(event, typeSel3);

            // --- TYPING MODE BYPASS ---
            if (isTypingModeEnabled) return event;


            // ── Mouse Movement (Moved 5, LDrag 6, RDrag 7, ODrag 8) ───────
            if (evType >= 5 && evType <= 8) {
                if (isMouseLocked || isGCMouseDirectActive) {
                    static SEL dxSel = NULL, dySel = NULL;
                    if (!dxSel) dxSel = NSSelectorFromString(@"deltaX");
                    if (!dySel) dySel = NSSelectorFromString(@"deltaY");
                    
                    CGFloat dx = ((CGFloat(*)(id,SEL))objc_msgSend)(event, dxSel);
                    CGFloat dy = -((CGFloat(*)(id,SEL))objc_msgSend)(event, dySel);

                    // ACCUMULATE: Movement is harvested here and sent via CADisplayLink
                    // (Manual re-injection removed in favor of setMouseMovedHandler pass-through)
                    mouseAccumX += (double)dx;
                    mouseAccumY += (double)dy;
                    
                    return nil; // DEEP STEALTH: Prevent Catalyst from seeing move / hitting edge.
                }
                return event;
            }

            // ── Mouse Buttons (L 1/2/6, R 3/4/7, Other 25/26/8) ───────────────────
            if ((evType >= 1 && evType <= 4) || evType == 25 || evType == 26 || (evType >= 6 && evType <= 8)) {
                int currentBtnCode = 0;
                // Press: LDown(1), RDown(3), ODown(25), LDrag(6), RDrag(7), ODrag(8)
                BOOL isPressed = (evType == 1 || evType == 3 || evType == 25 || (evType >= 6 && evType <= 8));
                
                if (evType == 1 || evType == 2 || evType == 6) currentBtnCode = MOUSE_BUTTON_LEFT;
                else if (evType == 3 || evType == 4 || evType == 7) currentBtnCode = MOUSE_BUTTON_RIGHT;
                else if (evType == 25 || evType == 26 || evType == 8) {
                    static SEL btnNumSel = NULL;
                    if (!btnNumSel) btnNumSel = NSSelectorFromString(@"buttonNumber");
                    NSInteger btnNum = ((NSInteger(*)(id,SEL))objc_msgSend)(event, btnNumSel);
                    if (btnNum == 2) currentBtnCode = MOUSE_BUTTON_MIDDLE;
                    else if (btnNum >= 3) currentBtnCode = (int)(MOUSE_BUTTON_AUX_BASE + (btnNum - 3));
                }

                if (isPressed) {
                    if (mouseButtonCaptureCallback != nil || keyCaptureCallback != nil) {
                        if (isPopupVisible) {
                            // 1 left click pass through workaround
                            if (currentBtnCode == MOUSE_BUTTON_LEFT && ignoreNextLeftClickCount > 0) {
                                ignoreNextLeftClickCount--;
                                return event;
                            }

                            typedef CGPoint (*LocationFunc)(id, SEL);
                            LocationFunc getLoc = (LocationFunc)objc_msgSend;
                            CGPoint pt = getLoc(event, NSSelectorFromString(@"locationInWindow"));
                            // Flip bottom-left (NSEvent) to top-left (UIWindow)
                            pt.y = popupWindow.bounds.size.height - pt.y;

                            UIViewController *vc = popupWindow.rootViewController;
                            if (vc) {
                                UIViewController *presented = vc.presentedViewController;
                                if (presented) {
                                    CGPoint alertPt = [popupWindow convertPoint:pt toView:presented.view];
                                    UIView *aHit = [presented.view hitTest:alertPt withEvent:nil];
                                    // If we hit ANYTHING inside the presented view (dialog, buttons, etc), pass it through
                                    if (aHit && aHit != presented.view) {
                                        return event; // Pass through to UI, don't capture
                                    }
                                }
                            }
                            
                            if (mouseButtonCaptureCallback != nil) {
                                mouseButtonCaptureCallback(currentBtnCode);
                                return nil; // swallow
                            }
                            if (keyCaptureCallback != nil) {
                                keyCaptureCallback(currentBtnCode);
                                return nil; // swallow
                            }
                        }
                    }
                }

                if (isPopupVisible) return event;

                if (isMouseLocked || isGCMouseDirectActive) {
                    if (evType == 1) leftButtonIsPressed = YES;
                    if (evType == 2) leftButtonIsPressed = NO;
                    if (evType == 3) rightButtonIsPressed = YES;
                    if (evType == 4) rightButtonIsPressed = NO;
                    if (evType == 25) middleButtonIsPressed = YES;
                    if (evType == 26) middleButtonIsPressed = NO;
                } else if (!isMouseLocked && !isTriggerHeld) {
                    // TRULY UNLOCKED (e.g. Settings Open): Return event to allow Catalyst interaction
                    return event; 
                }

                if (isControllerModeEnabled && !isPopupVisible) {
                    if (currentBtnCode != 0) {
                    updateGCMouseDirectState(currentBtnCode, isPressed);
                        // Hardware controller mapping — fire if locked OR if temporarily unlocked via Option
                        if (isMouseLocked || isTriggerHeld || !isPressed) {
                            for (int i = 0; i < FnCtrlButtonCount; i++) {
                                if (controllerMappingArray[i] == currentBtnCode) {
                                    dispatchControllerButton(i, isPressed);
                                }
                            }
                        }
                        // Custom vctrl remaps — fire if locked OR if temporarily unlocked via Option
                        if (isMouseLocked || isTriggerHeld || !isPressed) {
                            NSSet *tgts = vctrlCookedRemappings[@(currentBtnCode)];
                            for (NSNumber *tgt in tgts) {
                                dispatchControllerButton([tgt intValue], isPressed);
                            }
                        }
                    }
                }

                // ── Advanced Mouse Button Remaps (Unified Keybinds tab & Mouse tab) ──
                int mbIdx = currentBtnCode - MOUSE_BUTTON_MIDDLE;
                if (!isPopupVisible && currentBtnCode != 0) {
                    GCKeyCode mbTarget = 0;
                    
                    // Priority 1: Unified Keybinds Tab (fortniteRemapArray)
                    if (currentBtnCode >= 0 && currentBtnCode < 10200) {
                        mbTarget = fortniteRemapArray[currentBtnCode];
                    }
                    
                    // Priority 2: Advanced Mouse Remaps (mouseButtonRemapArray)
                    if (mbTarget == 0 && mbIdx >= 0 && mbIdx < MOUSE_REMAP_COUNT) {
                        GCKeyCode custom = mouseButtonRemapArray[mbIdx];
                        if (custom == (GCKeyCode)-1) return nil; // explicitly blocked
                        if (custom != 0) mbTarget = custom;
                        else mbTarget = mouseFortniteArray[mbIdx];
                    }

                    if (mbTarget != 0) {
                        if (isPressed) {
                            if (isMouseLocked) {
                                _sendDualKeyEvent(mbTarget, YES);
                                remappedMouseButtonsState[mbIdx] = YES;
                            }
                        } else {
                            if (remappedMouseButtonsState[mbIdx]) {
                                _sendDualKeyEvent(mbTarget, NO);
                                remappedMouseButtonsState[mbIdx] = NO;
                            }
                        }
                        return nil; // SWALLOW remapped click
                    }
                }

                // ── Mandatory suppression check (Blocks double-input and handles unmapped buttons) ──
                if (_isMouseButtonSuppressed(currentBtnCode) && !isPopupVisible) {
                    // BOTH-AT-ONCE: If holding Option, return event to Catalyst even if mapped to controller
                    // so we get UI Dragging + Controller Action simultaneously. Strip Option flag.
                    if (isTriggerHeld) {
                        static SEL setFlagsSel = NULL;
                        if (!setFlagsSel) setFlagsSel = NSSelectorFromString(@"_setModifierFlags:");
                        if (!setFlagsSel) setFlagsSel = NSSelectorFromString(@"setModifierFlags:");
                        NSUInteger currentFlags = ((NSUInteger(*)(id,SEL))objc_msgSend)(event, modFlagsSel2);
                        NSUInteger clearFlags = currentFlags & ~0x80000;
                        if ([event respondsToSelector:setFlagsSel]) {
                            ((void(*)(id,SEL,NSUInteger))objc_msgSend)(event, setFlagsSel, clearFlags);
                        }
                        return event;
                    }
                    return nil; // Standard mapped button suppression
                }

                return event; // Always return event to keep Move events flowing for L/R/M
            }

            // ── FlagsChanged (12): Modifier keys (Shift, Cmd, Caps, Ctrl, etc.) + Option teleport ─
            if (evType == 12) {
                // Determine the GCKeyCode for the modifier that just changed
                unsigned short modVK = ((unsigned short(*)(id,SEL))objc_msgSend)(event, keyCodeSel2);
                GCKeyCode modGC = 0;
                if (modVK == 56) modGC = 225; // Left Shift
                else if (modVK == 60) modGC = 229; // Right Shift
                else if (modVK == 55) modGC = 227; // Left Cmd
                else if (modVK == 54) modGC = 231; // Right Cmd
                else if (modVK == 57) modGC = 57;  // Caps Lock
                else if (modVK == 59) modGC = 224; // Left Ctrl
                else if (modVK == 62) modGC = 228; // Right Ctrl
                else if (modVK == 58) modGC = 226; // Left Option
                else if (modVK == 61) modGC = 230; // Right Option

                // When capture mode is active, deliver modifier to callback
                if (keyCaptureCallback != nil && modGC != 0) {
                    keyCaptureCallback(modGC);
                    return nil;
                }

                // Determine pressed state from flags.
                // Per-key tracking using static previous-flag storage keyed by nsVK.
                // NSEventModifierFlags bits: Shift=0x20000, Ctrl=0x40000, Opt=0x80000,
                //   Cmd=0x100000, CapsLock=0x10000. For L/R distinction we read the
                //   per-key "raw" flag bits from the modifier keycode.
                NSUInteger modFlags = ((NSUInteger(*)(id,SEL))objc_msgSend)(event, modFlagsSel2);
                BOOL modPressed = NO;
                // Use a small static lookup keyed by nsVK to track previous state
                static NSUInteger prevModFlags = 0;
                NSUInteger relevantBit = 0;
                if (modVK == 56 || modVK == 60) relevantBit = 0x20000;  // Shift
                else if (modVK == 55 || modVK == 54) relevantBit = 0x100000; // Cmd
                else if (modVK == 59 || modVK == 62) relevantBit = 0x40000;  // Ctrl
                else if (modVK == 57) relevantBit = 0x10000; // Caps Lock
                else if (modVK == 58 || modVK == 61) relevantBit = 0x80000;  // Option
                if (relevantBit != 0) {
                    BOOL wasPressed = (prevModFlags & relevantBit) != 0;
                    modPressed = (modFlags & relevantBit) != 0;
                    prevModFlags = (modFlags & ~0x80000); // exclude Option (handled separately)
                    if (modPressed == wasPressed && modGC != 57) {
                        // No change for this modifier (another mod changed) — skip
                        goto fnm_option_check;
                    }
                }


                if (modGC != 0 && !isPopupVisible) {
                    // CONTROLLER MODE: check if this modifier is mapped to a controller button
                    if (isControllerModeEnabled && (isMouseLocked || isTriggerHeld || !modPressed)) {
                        BOOL handled = NO;
                        for (int i = 0; i < FnCtrlButtonCount; i++) {
                            if (controllerMappingArray[i] == (int)modGC) {
                                dispatchControllerButton(i, modPressed);
                                handled = YES;
                            }
                        }
                        NSSet *tgts = vctrlCookedRemappings[@((int)modGC)];
                        for (NSNumber *tgt in tgts) {
                            dispatchControllerButton([tgt intValue], modPressed);
                            handled = YES;
                        }
                        if (handled) return nil;
                    }

                    // FORTNITE KEYBIND: check if this modifier is remapped to a default game key
                    if (modGC < 512) {
                        // Check custom remap first
                        GCKeyCode customTarget = keyRemapArray[modGC];
                        GCKeyCode fnTarget = (modGC < 512) ? fortniteRemapArray[modGC] : 0;
                        GCKeyCode target = (customTarget != 0 && customTarget != (GCKeyCode)-1) ? customTarget
                                         : (fnTarget != 0) ? fnTarget : 0;
                                         
                        if (target > 0 && target < 256) {
                            if (modGC == 57) {
                                // Special handling for Caps Lock: make every press a "Tap" (Down+Up)
                                // This bypasses the OS toggle behavior for gaming.
                                _sendDualKeyEvent(target, YES);
                                _sendDualKeyEvent(target, NO);
                                return nil;
                            }

                            uint16_t remappedVK = gcToNSVK[(uint8_t)target];
                            // Inject as modifier-flag CGEvent so game sees it
                            if ((remappedVK > 0 || target == 4) && _CGEventCreateKeyboardEvent && _CGEventPost) {
                                CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, remappedVK, (bool)modPressed);
                                if (ev) {
                                    _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337);
                                    _CGEventPost(kCGHIDEventTap, ev);
                                    CFRelease(ev);
                                }
                            }
                            if (storedKeyboardHandler && storedKeyboardInput) {
                                GCControllerButtonInput *b = [storedKeyboardInput buttonForKeyCode:target];
                                if (b) storedKeyboardHandler(storedKeyboardInput, b, target, modPressed);
                            }
                            return nil; // swallow original modifier
                        }
                    }
                }

                fnm_option_check:;
                NSUInteger flags = modFlags;
                BOOL optNow = (flags & 0x80000) != 0; // NSEventModifierFlagOption
                if (optNow == prevOptionHeld2) return event;
                prevOptionHeld2 = optNow;
                
                if (isPopupVisible) return event;

                if (optNow) {
                    isTriggerHeld = YES;
                    if (isMouseLocked) {
                        // Unlock and warp to Blue Dot
                        if (!blueDotIndicator) createBlueDotIndicator();
                        UIWindowScene *_wsc = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                        UIWindow *_kw = _wsc ? (_wsc.keyWindow ?: _wsc.windows.firstObject) : nil;
                        CGFloat _winX = _kw ? _kw.frame.origin.x : 0;
                        CGFloat _winY = _kw ? _kw.frame.origin.y : 0;
                        CGPoint warpPt = CGPointMake(blueDotPosition.x + _winX, blueDotPosition.y + _winY);
                        isMouseLocked = NO;
                        updateMouseLock(NO, warpPt);
                        
                        // RE-ASSERTION: Force all held inputs back to 'Pressed' after the
                        // mode switch to prevent the game engine from dropping them.
                        reassertAllInputs();
                    }
                } else {
                    isTriggerHeld = NO;
                    if (!isMouseLocked) {
                        // Lock and warp to center
                        isMouseLocked = YES;
                        updateMouseLock(YES, CGPointZero);
                    }
                }
                return event; // pass through
            }

            // ── KeyDown (10) / KeyUp (11) ─────────────────────────────────────
            BOOL pressed = (evType == 10);
            
            // Prevent key repeat flood from lagging the main thread!
            if (pressed) {
                SEL repeatSel = NSSelectorFromString(@"isARepeat");
                if ([event respondsToSelector:repeatSel]) {
                    // BOOL isRepeat = ((BOOL(*)(id,SEL))objc_msgSend)(event, repeatSel);
                    // if (isRepeat) return event;
                }
            }

            unsigned short nsVK = ((unsigned short(*)(id,SEL))objc_msgSend)(event, keyCodeSel2);
            if (nsVK >= 128) return event;

            GCKeyCode gck = nsVKToGC[nsVK];
            if (gck != 0 && gck == GCMOUSE_DIRECT_KEY) {
                updateGCMouseDirectState((int)gck, pressed);
                // pass through
            }

            // ── 'L' keyDown (evType 10) — toggle mouse lock ────
            if (pressed && nsVK == 37) {
                if (isPopupVisible) return event;
                isMouseLocked = !isMouseLocked;
                if (!isMouseLocked) {
                    UIWindowScene *_sc = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                    CGRect _sb = _sc ? _sc.screen.bounds : CGRectMake(0, 0, 1920, 1080);
                    CGPoint _center = CGPointMake(_sb.size.width / 2.0, _sb.size.height / 2.0);
                    updateMouseLock(NO, _center);
                    resetControllerState();
                } else {
                    updateMouseLock(YES, CGPointZero);
                }
                return nil; // consume
            }

            // ── POPUP_KEY (P key, VK 35) — show/hide settings popup ──
            // Using raw NSVirtualKeyCode 35 is proven more reliable on Catalyst.
            if (nsVK == 35) {
                if (pressed) {
                    if (!popupWindow) createPopup();
                    if (isPopupVisible) {
                        popupViewController *vc = (popupViewController *)popupWindow.rootViewController;
                        if ([vc respondsToSelector:@selector(closeButtonTapped)])
                            [vc performSelector:@selector(closeButtonTapped)];
                        else { isPopupVisible = NO; popupWindow.hidden = YES; updateBlueDotVisibility(); }
                    } else {
                        isPopupVisible = YES;
                        popupWindow.hidden = NO;
                        [popupWindow makeKeyAndVisible]; // Ensure it gets focus
                        showChickenDinner(); // 🐔
                    }
                    isMouseLocked = NO;
                    updateMouseLock(NO, CGPointZero);
                    resetControllerState();
                }
                return nil; // consume — don't pass P through to the game
            }

            GCKeyCode keyCode = nsVKToGC[nsVK];
            if (keyCode == 0) return event;

            // ── Hardened Suppression for Controller/Remap ───────────────────
            BOOL isRemappedElsewhere = NO;
            for (int i = 0; i < FnCtrlButtonCount; i++) {
                if (controllerMappingArray[i] == (int)keyCode) {
                    isRemappedElsewhere = YES;
                    break;
                }
            }

            // PRIORITIZE CONTROLLER MODE: dispatch mapped controller button.
            if (isControllerModeEnabled && (isMouseLocked || isTriggerHeld || !pressed) && !isPopupVisible && keyCaptureCallback == nil) {
                BOOL handled = NO;
                for (int i = 0; i < FnCtrlButtonCount; i++) {
                    if (controllerMappingArray[i] == (int)keyCode) {
                        dispatchControllerButton(i, pressed);
                        handled = YES;
                    }
                }
                NSSet *tgts = vctrlCookedRemappings[@((int)keyCode)];
                for (NSNumber *tgt in tgts) {
                    dispatchControllerButton([tgt intValue], pressed);
                    handled = YES;
                }
                if (handled) return nil; // swallow - must not reach game
            }

            // ── Advanced Custom Remaps (tracked state for robust KeyUp) ───
            if (!isPopupVisible && keyCaptureCallback == nil) {
                GCKeyCode target = 0;
                GCKeyCode customTarget = (keyCode < 512) ? keyRemapArray[keyCode] : 0;
                if (customTarget == (GCKeyCode)-1) return nil; 
                if (customTarget != 0) {
                    target = customTarget;
                } else if (keyCode < 512) {
                    GCKeyCode fnTarget = fortniteRemapArray[keyCode];
                    if (fnTarget != 0) {
                        target = fnTarget;
                    } else if (fortniteBlockedDefaults[keyCode] != 0 || isRemappedElsewhere) {
                        return nil; // swallowed (either by Keybind block or Controller map)
                    }
                }

                if (target > 0 && target < 256) {
                    if (pressed) {
                        if (isMouseLocked) {
                            _sendDualKeyEvent(target, YES);
                            remappedKeysState[keyCode] = YES;
                            return nil;
                        }
                    } else {
                        // RELEASE: catch KeyUp even if just unlocked
                        if (remappedKeysState[keyCode]) {
                            _sendDualKeyEvent(target, NO);
                            remappedKeysState[keyCode] = NO;
                            return nil;
                        }
                    }
                }
            }

            // Option key events handled entirely via FlagsChanged above.
            // Allow ESC through when not remapped.
            if (keyCode == TRIGGER_KEY) {
                if (keyCaptureCallback != nil && pressed) {
                    keyCaptureCallback(keyCode);
                    return nil;
                }
                if (keyCaptureCallback == nil) {
                    // Only swallow if it's remapped (already handled above) or being captured.
                    // If no remap exists, allow the physical key to reach the game.
                    if (keyRemapArray[keyCode] == 0 && fortniteRemapArray[keyCode] == 0) return event;
                    return nil;
                }
            }


            // ── Key capture for popup remapping UI — swallow and deliver to callback
            if (keyCaptureCallback != nil && pressed) {
                keyCaptureCallback(keyCode);
                return nil; // Swallow ALL keys (including ESC) to prevent dismissing the alert
            }

            if (keyCaptureCallback != nil && !pressed) {
                return nil; // Swallow KeyUp as well during capture
            }

            return event;
        };

        if ([nsEventClass respondsToSelector:addMonitorSel]) {
            NSInvocation *kbInv = [NSInvocation invocationWithMethodSignature:
                [nsEventClass methodSignatureForSelector:addMonitorSel]];
            [kbInv setSelector:addMonitorSel];
            [kbInv setTarget:nsEventClass];
            [kbInv setArgument:&keyMask atIndex:2];
            id kbBlock = [kbMonitor copy];
            [kbInv setArgument:&kbBlock atIndex:3];
            [kbInv invoke];
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


void createBlueDotIndicator() {
    if (blueDotIndicator) return;
    
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    if (!scene) return;
    
    blueDotIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    blueDotIndicator.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    blueDotIndicator.layer.cornerRadius = 10;
    blueDotIndicator.layer.borderWidth = 2;
    blueDotIndicator.layer.borderColor = [UIColor whiteColor].CGColor;
    blueDotIndicator.hidden = YES;
    blueDotIndicator.userInteractionEnabled = YES;
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:blueDotIndicator action:nil];
    __weak UIView *weakDot = blueDotIndicator;
    [panGesture addTarget:weakDot action:@selector(handleBluePan:)];
    [blueDotIndicator addGestureRecognizer:panGesture];
    
    UIWindow *gameWindow = nil;
    for (UIWindow *w in scene.windows) {
        if (w != popupWindow) { gameWindow = w; break; }
    }
    
    if (gameWindow) {
        [gameWindow addSubview:blueDotIndicator];
        
        CGRect screenBounds = gameWindow.bounds;
        NSDictionary *savedPosition = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kBlueDotPositionKey];
        
        if (savedPosition) {
            CGFloat x = [savedPosition[@"x"] floatValue];
            CGFloat y = [savedPosition[@"y"] floatValue];
            x = MAX(10, MIN(screenBounds.size.width - 10, x));
            y = MAX(10, MIN(screenBounds.size.height - 10, y));
            blueDotPosition = CGPointMake(x, y);
        } else {
            // Default to bottom right area
            blueDotPosition = CGPointMake(screenBounds.size.width * 0.875, screenBounds.size.height * 0.875);
        }
        
        blueDotIndicator.center = blueDotPosition;
    }
}

void resetBlueDotPosition(void) {
    if (!blueDotIndicator) createBlueDotIndicator();
    
    if (blueDotIndicator && blueDotIndicator.superview) {
        CGRect screenBounds = blueDotIndicator.superview.bounds;
        CGPoint defaultPosition = CGPointMake(screenBounds.size.width * 0.875, screenBounds.size.height * 0.875);
        blueDotPosition = defaultPosition;
        blueDotIndicator.center = defaultPosition;
        
        NSDictionary *positionDict = @{@"x": @(defaultPosition.x), @"y": @(defaultPosition.y)};
        [[NSUserDefaults standardUserDefaults] setObject:positionDict forKey:kBlueDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

void updateBlueDotVisibility(void) {
    if (!blueDotIndicator) createBlueDotIndicator();
    blueDotIndicator.hidden = !isPopupVisible;
}

// Button state declarations moved to global scope
static BOOL leftClickSentToGame  = NO;
static GCControllerButtonValueChangedHandler leftButtonGameHandler = nil;
static GCControllerButtonValueChangedHandler leftButtonRawHandler  = nil; // raw game handler, never the wrapper
static GCControllerButtonInput *leftButtonInput = nil;
// isTriggerHeld — declared above as forward decl
static UIView  *lastCheckedView     = nil;
static BOOL     lastViewWasUIElement = NO;
static UIWindow *cachedKeyWindow    = nil;

// CGAssociateMouseAndMouseCursorPosition — absent from iOS SDK headers, resolved at runtime.
typedef CGError (*CGAssociateMouseAndMouseCursorPosition_t)(boolean_t connected);
static CGAssociateMouseAndMouseCursorPosition_t fnCGAssociateMouse = NULL;

// CGWarpMouseCursorPosition — absent from iOS SDK headers, resolved at runtime.
typedef CGError (*CGWarpMouseCursorPosition_t)(CGPoint newCursorPosition);
static CGWarpMouseCursorPosition_t fnCGWarpMouse = NULL;

void clearAllControllerButtons() {
    // Release all mapped virtual controller buttons to prevent stuck inputs (like constant firing or ADS)
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        dispatchControllerButton(i, NO);
    }
}

static void updateMouseLock(BOOL value, CGPoint warpPos) {
    UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication].connectedScenes allObjects] firstObject];
    if (!scene) return;

    // AGGRESSIVE UNLOCK: Notify all view controllers in all windows.
    // Catalyst can be picky about which VC actually owns the lock.
    for (UIWindow *window in scene.windows) {
        UIViewController *root = window.rootViewController;
        if ([root respondsToSelector:NSSelectorFromString(@"setNeedsUpdateOfPrefersPointerLocked")]) {
            ((void (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"setNeedsUpdateOfPrefersPointerLocked"));
        }
    }

    if (value) {
        Class nsCursorClass = NSClassFromString(@"NSCursor");
        if (nsCursorClass) {
            ((void(*)(Class,SEL))objc_msgSend)(nsCursorClass, NSSelectorFromString(@"hide"));
        }

        // Decouple exactly how cursorteleportation did it — freezing the hardware cursor seamlessly.
        if (!fnCGAssociateMouse)
            fnCGAssociateMouse = (CGAssociateMouseAndMouseCursorPosition_t)dlsym(RTLD_DEFAULT, "CGAssociateMouseAndMouseCursorPosition");
        if (fnCGAssociateMouse) fnCGAssociateMouse(0);

        // LOCKING — cancel any in-flight click before the lock gesture takes hold.
        BOOL hadGCPress = leftClickSentToGame;  // GC press was actually sent to game
        GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
        GCControllerButtonInput *gcInput = leftButtonInput;

        leftButtonIsPressed  = NO;
        leftClickSentToGame  = NO;
        lastCheckedView      = nil;
        lastViewWasUIElement = NO;

        void (^cancelBlock)(void) = ^{
            UIApplication *app = [UIApplication sharedApplication];
            static IMP cancelAllTouchesIMP = NULL;
            if (!cancelAllTouchesIMP)
                cancelAllTouchesIMP = [app methodForSelector:@selector(_cancelAllTouches)];
            if (cancelAllTouchesIMP)
                ((void (*)(id, SEL))cancelAllTouchesIMP)(app, @selector(_cancelAllTouches));
            if (hadGCPress && gcHandler && gcInput)
                gcHandler(gcInput, 0.0, NO);
        };
        if ([NSThread isMainThread]) cancelBlock();
        else dispatch_sync(dispatch_get_main_queue(), cancelBlock);
    } else {
        // Unconditionally re-couple mouse movement to the hardware cursor
        if (!fnCGAssociateMouse)
            fnCGAssociateMouse = (CGAssociateMouseAndMouseCursorPosition_t)dlsym(RTLD_DEFAULT, "CGAssociateMouseAndMouseCursorPosition");
        if (fnCGAssociateMouse) fnCGAssociateMouse(1);

        // We briefly decouple to ensure UIKit doesn't fight the warp, then instantly recouple for the specific position.
        if (warpPos.x > 0 || warpPos.y > 0) {
            if (fnCGAssociateMouse) fnCGAssociateMouse(0);
            if (!fnCGWarpMouse)
                fnCGWarpMouse = (CGWarpMouseCursorPosition_t)dlsym(RTLD_DEFAULT, "CGWarpMouseCursorPosition");
            if (fnCGWarpMouse) fnCGWarpMouse(warpPos);
            if (fnCGAssociateMouse) fnCGAssociateMouse(1);
        }

        Class nsCursorClass = NSClassFromString(@"NSCursor");
        if (nsCursorClass) {
            ((void(*)(Class,SEL))objc_msgSend)(nsCursorClass, NSSelectorFromString(@"unhide"));
        }

        // PANIC RELEASE: ensure no remapped keys or mouse buttons stay stuck on unlock
        // EXCEPT: Skip this if we are temporarily unlocking via the Option key (Sticky Mode)
        if (!isTriggerHeld) {
            for (int i = 0; i < 512; i++) {
                if (remappedKeysState[i]) {
                    GCKeyCode target = 0;
                    GCKeyCode customTarget = keyRemapArray[i];
                    if (customTarget != 0 && customTarget != (GCKeyCode)-1) {
                        target = customTarget;
                    } else {
                        target = fortniteRemapArray[i];
                    }
                    
                    if (target > 0 && target < 256) {
                        uint16_t remappedVK = gcToNSVK[(uint8_t)target];
                        if ((remappedVK > 0 || target == 4) && _CGEventCreateKeyboardEvent && _CGEventPost) {
                            CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, remappedVK, false);
                            if (ev) {
                                _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337);
                                _CGEventPost(kCGHIDEventTap, ev);
                                CFRelease(ev);
                            }
                        }
                    }
                    remappedKeysState[i] = NO;
                }
            }
            for (int i = 0; i < FnCtrlButtonCount; i++) {
                dispatchControllerButton(i, NO);
            }
        }

        // UNLOCKING — only purge game inputs if the settings popup is shown.
        // For Option-key 'teleports', we want to allow continuous movement/firing.
        if (isPopupVisible) {
            clearAllControllerButtons();
            wasADSInitialized = NO;

            GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
            GCControllerButtonInput *gcInput = leftButtonInput;
            BOOL hadUITouch = leftButtonIsPressed;
            BOOL hadGCPress = leftClickSentToGame;

            leftButtonIsPressed  = NO;
            rightButtonIsPressed = NO;
            leftClickSentToGame  = NO;
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
                    if (hadGCPress && gcHandler && gcInput)
                        gcHandler(gcInput, 0.0, NO);
                });
            }
        }
    }


    if (!value) isGCMouseDirectActive = NO;
    updateBlueDotVisibility();
}

// --------- THEOS HOOKS ---------
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


// ─────────────────────────────────────────────────────────────────────
// GCExtendedGamepad hook — inject L3/R3 properties if they are missing.
// Fortnite (UE) requires these properties to exist on the gamepad object
// to recognize stick clicks. GCVirtualController excludes them by default.
// ─────────────────────────────────────────────────────────────────────
%hook GCExtendedGamepad

- (id)leftThumbstickButton {
    id val = %orig;
    if (val) return val;
    return getInjectedButton(self, @"leftThumbstickButton");
}

- (id)_leftThumbstickButton {
    if ([self respondsToSelector:@selector(leftThumbstickButton)]) {
        return [self leftThumbstickButton];
    }
    return getInjectedButton(self, @"leftThumbstickButton");
}

- (id)rightThumbstickButton {
    id val = %orig;
    if (val) return val;
    return getInjectedButton(self, @"rightThumbstickButton");
}

- (id)_rightThumbstickButton {
    if ([self respondsToSelector:@selector(rightThumbstickButton)]) {
        return [self rightThumbstickButton];
    }
    return getInjectedButton(self, @"rightThumbstickButton");
}

%end

// ─────────────────────────────────────────────────────────────────────
// GCController hook — Spoof the virtual controller as a DualShock 4.
// Fortnite enables L3/R3 and more features for recognized controllers.
// ─────────────────────────────────────────────────────────────────────
%hook GCController

- (NSString *)productCategory {
    GCVirtualController *vc = (GCVirtualController *)g_virtualController;
    if (vc && self == vc.controller) {
        return @"DualSense";
    }
    return %orig;
}

- (NSString *)vendorName {
    GCVirtualController *vc = (GCVirtualController *)g_virtualController;
    if (vc && self == vc.controller) {
        return @"DualSense Wireless Controller";
    }
    return %orig;
}

%end

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
    g_originalMouseHandler = [handler copy];
    g_capturedMouseInput = self;
    if (self.leftButton) objc_setAssociatedObject(self.leftButton, &kButtonCodeKey, @(MOUSE_BUTTON_LEFT), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.rightButton) objc_setAssociatedObject(self.rightButton, &kButtonCodeKey, @(MOUSE_BUTTON_RIGHT), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.middleButton) objc_setAssociatedObject(self.middleButton, &kButtonCodeKey, @(MOUSE_BUTTON_MIDDLE), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray<GCControllerButtonInput *> *aux = self.auxiliaryButtons;
    for (NSInteger i = 0; i < (NSInteger)aux.count; i++) {
        if (aux[i]) objc_setAssociatedObject(aux[i], &kButtonCodeKey, @(MOUSE_BUTTON_AUX_BASE + i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    GCMouse *currentMouse = GCMouse.current;
    if (currentMouse && currentMouse.handlerQueue != dispatch_get_main_queue())
        currentMouse.handlerQueue = dispatch_get_main_queue();
    GCMouseMoved customHandler = [^(GCMouseInput *eventMouse, float deltaX, float deltaY) {
        if (isMouseLocked) {
            mouseAccumX += (double)deltaX;
            mouseAccumY += (double)deltaY;
        }
        if (isGCMouseDirectActive) {
            handler(eventMouse, deltaX, deltaY);
        }
    } copy];
    %orig(customHandler);
}
%end




// ─────────────────────────────────────────────────────────────────────
// GCMouse hook — ensure callbacks fire on main queue.
// ─────────────────────────────────────────────────────────────────────


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
            int scrollCode = (yValue > 0) ? MOUSE_SCROLL_UP : (yValue < 0 ? MOUSE_SCROLL_DOWN : 0);
            if (scrollCode != 0) {
                int idx = scrollCode - MOUSE_SCROLL_UP;
                // Check keyboard/Fortnite remaps
                if (mouseScrollRemapArray[idx] != 0 || 
                    mouseScrollFortniteArray[idx] != 0 || 
                    fortniteRemapArray[scrollCode] != 0) return;
                
                // [NEW] Check controller remaps — if mapped to controller button, suppress here
                if (isControllerModeEnabled) {
                    for (int i = 0; i < FnCtrlButtonCount; i++) {
                        if (controllerMappingArray[i] == scrollCode) return;
                    }
                }
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


// HELPER: Centralized suppression check for Mouse Buttons (L, R, M, Aux1...)
// Prevents default game listening for M4/M5 and blocks double-input for remapped keys.
static BOOL _isMouseButtonSuppressed(int code) {
    // 1. Keyboard/Mouse Remapping (Unified Keybinds tab)
    if (code >= 0 && code < 10200 && fortniteRemapArray[code] != 0) return YES;
    
    // 2. Keyboard Remapping (Remaps tab)
    if (code >= 0 && code < 512 && keyRemapArray[code] != 0) return YES;
    // Also check higher codes if they map into keyRemapping storage
    if (code >= 0 && code < 10200 && keyRemapArray[code % 512] != 0) {
         // This is a bit loose but keyRemapArray handles the first 512 and modulo thereafter
         // if it was stored via the popup UI which uses % 512.
    }

    // 3. Mouse Tab Remapping (mouseButtonRemapArray & mouseFortniteArray)
    int mbIdx = code - MOUSE_BUTTON_MIDDLE;
    if (mbIdx >= 0 && mbIdx < MOUSE_REMAP_COUNT) {
        if (mouseButtonRemapArray[mbIdx] != 0) return YES;
        if (mouseFortniteArray[mbIdx] != 0) return YES;
    }
    
    // 4. Controller Remapping
    if (isControllerModeEnabled) {
        // Hardware mappings
        for (int i = 0; i < FnCtrlButtonCount; i++) {
            if (controllerMappingArray[i] == code) return YES;
        }
    }
    
    // 5. L/R/M follow the global Direct Mouse toggle
    // If Direct Mouse is ACTIVE, we suppress these three to send clean GC inputs.
    // If INACTIVE, they must pass through (return NO here) so the native mouse works.
    if (code == MOUSE_BUTTON_LEFT || code == MOUSE_BUTTON_RIGHT || code == MOUSE_BUTTON_MIDDLE) {
        if (isGCMouseDirectActive) return YES;
    }
    
    // 6. Direct Mouse Toggle Key (Exclusive)
    if (code != 0 && (GCKeyCode)code == GCMOUSE_DIRECT_KEY) return YES;
    
    return NO;
}

// OS-LEVEL EVENT TAP: Intercepts M4/M5 before they reach ANY system or app layer.
// Providing the "FULL block" requested by the user.
static CGEventRef mouseButtonTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    // ── SAFETY CHECK: GLOBAL INTERFERENCE PREVENTION ──
    // Only process events if our app is actually in the foreground.
    // This prevents neutralizing Caps Lock or OtherMouse buttons for the entire OS.
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return event;
    }

    // A. KEYBOARD EVENTS (System-Level Intervention)
    if (type == 10 || type == 11 || type == 12) { // KeyDown, KeyUp, FlagsChanged
        if (_CGEventGetFlags && _CGEventSetFlags) {
            CGEventFlags flags = _CGEventGetFlags(event);
            
            // 0. Intercept Capture Keys (including ESC and Key A)
            if (keyCaptureCallback != nil) {
                int64_t vk = _CGEventGetIntegerValueField ? _CGEventGetIntegerValueField(event, 9) : 0;
                if (type == 10) { // KeyDown (allow vk == 0 for Key A)
                    keyCaptureCallback(nsVKToGC[vk]);
                }
                return NULL; // SWALLOW ALL KEYS DURING CAPTURE
            }

            // 1. Intercept Caps Lock (VK 57)
            int64_t vk = _CGEventGetIntegerValueField ? _CGEventGetIntegerValueField(event, 9) : 0;
            if (type == 12 && vk == 57) {
                isTypingModeEnabled = (flags & kCGEventFlagMaskAlphaShift) != 0;
                return NULL; // CONSUME AT SYSTEM LEVEL
            }
            
            // 2. Global Caps Lock Stripping & Lowercasing
            if (flags & kCGEventFlagMaskAlphaShift) {
                _CGEventSetFlags(event, flags & ~kCGEventFlagMaskAlphaShift);
                
                // Force lowercase unicode strings if Shift isn't held
                if (type == 10 && !(flags & kCGEventFlagMaskShift) && _CGEventKeyboardGetUnicodeString && _CGEventKeyboardSetUnicodeString) {
                    UniChar unicodeChars[4];
                    UniCharCount actualLen = 0;
                    _CGEventKeyboardGetUnicodeString(event, 4, &actualLen, unicodeChars);
                    if (actualLen > 0) {
                        BOOL changed = NO;
                        for (int i = 0; i < (int)actualLen; i++) {
                            if (unicodeChars[i] >= 'A' && unicodeChars[i] <= 'Z') {
                                unicodeChars[i] += ('a' - 'A');
                                changed = YES;
                            }
                        }
                        if (changed) {
                            _CGEventKeyboardSetUnicodeString(event, actualLen, unicodeChars);
                        }
                    }
                }
            }
        }
    }

    if (isTypingModeEnabled) return event;

    // --- MOUSE BUTTON SUPPRESSION & REMAPPING ---
    if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp || type == kCGEventLeftMouseDragged ||
        type == kCGEventRightMouseDown || type == kCGEventRightMouseUp || type == kCGEventRightMouseDragged ||
        type == kCGEventOtherMouseDown || type == kCGEventOtherMouseUp || type == kCGEventOtherMouseDragged) {
        
        int currentBtnCode = 0;
        if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp || type == kCGEventLeftMouseDragged) {
            currentBtnCode = MOUSE_BUTTON_LEFT;
        } else if (type == kCGEventRightMouseDown || type == kCGEventRightMouseUp || type == kCGEventRightMouseDragged) {
            currentBtnCode = MOUSE_BUTTON_RIGHT;
        } else {
            int64_t btnNum = _CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
            currentBtnCode = (int)(MOUSE_BUTTON_AUX_BASE + (btnNum - 3));
        }

        BOOL isPressed = (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown ||
                          type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged || type == kCGEventOtherMouseDragged);

        if (!isPopupVisible) {
            // 0. Update Direct Mouse Toggle state
            if (currentBtnCode != 0 && (GCKeyCode)currentBtnCode == GCMOUSE_DIRECT_KEY) {
                updateGCMouseDirectState(currentBtnCode, isPressed);
            }

            // Sync physical mouse state removed (GC clicks should NEVER fire)

            // 1. Remapping Logic (from Sensitivity or Remaps tab)
            int mbIdx = currentBtnCode - MOUSE_BUTTON_MIDDLE;
            GCKeyCode mbTarget = 0;
            if (currentBtnCode >= 0 && currentBtnCode < 10200) {
                 mbTarget = fortniteRemapArray[currentBtnCode];
            }
            if (mbTarget == 0 && mbIdx >= 0 && mbIdx < MOUSE_REMAP_COUNT) {
                 mbTarget = mouseButtonRemapArray[mbIdx];
                 if (mbTarget == 0) mbTarget = mouseFortniteArray[mbIdx];
            }
            if (mbTarget == 0 && currentBtnCode >= 0 && currentBtnCode < 512) {
                 mbTarget = keyRemapArray[currentBtnCode];
            }
            // MODULO Fallback for Popup UI
            if (mbTarget == 0 && currentBtnCode >= 0 && currentBtnCode < 10200) {
                 mbTarget = keyRemapArray[currentBtnCode % 512];
            }

            if (mbTarget != 0) {
                static BOOL tapRemapState[64] = {NO}; // Increased for safety
                int tapIdx = (currentBtnCode == MOUSE_BUTTON_LEFT) ? 60 : 
                             (currentBtnCode == MOUSE_BUTTON_RIGHT) ? 61 : 
                             (int)(currentBtnCode - MOUSE_BUTTON_MIDDLE);

                if (tapIdx >= 0 && tapIdx < 64) {
                    if (isPressed) {
                        if (isMouseLocked && !tapRemapState[tapIdx]) {
                            _sendDualKeyEvent(mbTarget, YES);
                            tapRemapState[tapIdx] = YES;
                        }
                    } else if (type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp || type == kCGEventOtherMouseUp) {
                        if (tapRemapState[tapIdx]) {
                            _sendDualKeyEvent(mbTarget, NO);
                            tapRemapState[tapIdx] = NO;
                        }
                    }
                }
            }

            // 2. Controller Mode
            if (isControllerModeEnabled) {
                for (int i = 0; i < FnCtrlButtonCount; i++) {
                    if (controllerMappingArray[i] == currentBtnCode) {
                        if (isMouseLocked || !isPressed) {
                            dispatchControllerButton(i, isPressed);
                        }
                    }
                }
            }

            // 3. SWALLOW IF SUPPRESSED
            if (_isMouseButtonSuppressed(currentBtnCode)) {
                return NULL; 
            }
        }
    }
    return event;
}

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

        // ── Controller mode remap (Key → Controller Button) ───────────
        // We handle this here to suppress the key if it's bound to a controller.
        // kbMonitor dispatches the controller button, so we only need to swallow.
        if (isControllerModeEnabled && !isPopupVisible) {
            for (int i = 0; i < FnCtrlButtonCount; i++) {
                if (controllerMappingArray[i] == (int)keyCode) {
                    return; // Swallow - this key is a controller button
                }
            }
        }

        // TWO-TIER REMAPPING SYSTEM (ULTRA-FAST):
        // PRIORITY 1: Advanced Custom Remaps - user's explicit overrides (~2ns)
        // PRIORITY 2: Fortnite Keybinds - custom key → default key (~2ns)
        // PRIORITY 3: Block default Fortnite keys when remapped away (~2ns)
        // Total overhead: ~6ns (all are direct array lookups, zero dictionary overhead)
        
        GCKeyCode finalKey = keyCode;
        BOOL wasRemapped = NO;
        
        if (keyCode >= 0 && keyCode < 512) {
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
        
        // When a key is remapped, suppress the original and send the target.
        if (wasRemapped) {
            BOOL injected = NO;

            // Path 1: GCKit button — zero-latency, works for letters/F-keys
            GCControllerButtonInput* remappedBtn = [keyboard buttonForKeyCode:finalKey];
            if (remappedBtn) {
                handler(keyboard, remappedBtn, finalKey, pressed);
                injected = YES;
            }

            // Path 2: Root-level CGEventPost — covers modifier keys, number keys,
            // and any key GCKit doesn't expose via buttonForKeyCode.
            if (!injected && finalKey < 256 && _CGEventCreateKeyboardEvent && _CGEventPost) {
                uint16_t targetVK = gcToNSVK[(uint8_t)finalKey];
                // targetVK 0 is only valid for GC code 4 ('A')
                if (targetVK > 0 || finalKey == 4) {
                    CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, targetVK, (bool)pressed);
                    if (ev) {
                        _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337); _CGEventPost(kCGHIDEventTap, ev);
                        CFRelease(ev);
                        injected = YES;
                    }
                }
            }

            // Suppress original regardless — even if injection failed
            return;
        }
        
        // No remapping - call handler with original key
        handler(keyboard, key, keyCode, pressed);
    };

    %orig(customHandler);
}

%end

// Disable pointer "locking" mechanism:
// We explicitly disable Apple native pointer lock to prevent Catalyst from rejecting
// the Backtick key press and causing tracking drift bounds clamping. The custom
// `updateMouseLock` state manually leverages `CGAssociateMouse(0)` instead.
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

    // FAST PATH: Mouse unlocked (includes when Option is held) — convert to direct touch
    // so clicks and drags work while the cursor is free.
    if (!isMouseLocked) {
        return UITouchTypeDirect;
    }

    return _original;
}

%end

// =============================================================================
// GLOBAL TOUCH SUPPRESSION
// This fixes the "Circle Spring" by blocking Catalyst's virtual touch emulation
// when we are in raw-aiming mode.
// =============================================================================
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    if (isMouseLocked && event.type == 0) { // UIEventTypeTouches = 0
        NSSet *touches = [event allTouches];
        for (UITouch *touch in touches) {
            // UITouchTypePointer = 3 (Catalyst Mouse-Touch)
            if ((int)touch.type == 3) {
                return; // Swallow! Prevent virtual joystick accumulation.
            }
        }
    }
    %orig;
}
%end


%hook GCControllerButtonInput

- (void)setPressedChangedHandler:(GCControllerButtonValueChangedHandler)handler {
    if (!handler) { %orig; return; }
    GCControllerButtonValueChangedHandler wrapper = ^(GCControllerButtonInput *btn, float val, BOOL pressed) {
        NSNumber *codeNum = objc_getAssociatedObject(btn, &kButtonCodeKey);
        if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) {
             return; 
        }
        handler(btn, val, pressed);
    };
    %orig(wrapper);
}

- (void)setValueChangedHandler:(GCControllerButtonValueChangedHandler)handler {
    if (!handler) { %orig; return; }
    GCControllerButtonValueChangedHandler wrapper = ^(GCControllerButtonInput *btn, float val, BOOL pressed) {
        NSNumber *codeNum = objc_getAssociatedObject(btn, &kButtonCodeKey);
        if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) {
             return; 
        }
        handler(btn, val, pressed);
    };
    %orig(wrapper);
}

- (BOOL)isPressed {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum) {
        int code = [codeNum intValue];
        // 1. Suppression Priority: If this is a mouse button being handled by the tweak,
        // it must ALWAYS return NO to the game's GC frame listeners.
        if (_isMouseButtonSuppressed(code)) return NO;

        // 2. Legacy synthesis check (Fallback)
        if (code == MOUSE_BUTTON_LEFT && leftButtonIsPressed) return NO; // Absolute block
        if (code == MOUSE_BUTTON_RIGHT && rightButtonIsPressed) return NO;
        if (code == MOUSE_BUTTON_MIDDLE && middleButtonIsPressed) return NO;
    }
    return %orig;
}

- (float)value {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum) {
        int code = [codeNum intValue];
        if (_isMouseButtonSuppressed(code)) return 0.0f;
        
        // Absolute block for synthesized states
        if (code == MOUSE_BUTTON_LEFT && leftButtonIsPressed) return 0.0f;
        if (code == MOUSE_BUTTON_RIGHT && rightButtonIsPressed) return 0.0f;
        if (code == MOUSE_BUTTON_MIDDLE && middleButtonIsPressed) return 0.0f;
    }
    return %orig;
}

- (void)setValue:(float)val {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) {
        %orig(0.0f);
        return;
    }
    %orig;
}

- (void)setPressed:(BOOL)pressed {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) {
        %orig(NO);
        return;
    }
    %orig;
}

- (BOOL)pressed {
    return [self isPressed];
}

%end