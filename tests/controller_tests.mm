#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <cassert>
#include <cstdio>

// Stand-ins for framework devices. Production code is compiled below verbatim.
@interface GCControllerButtonInput : NSObject
@property float value;
@property BOOL isPressed;
@property NSUInteger valueCalls;
@property NSUInteger pressCalls;
@property(copy) void (^valueChangedHandler)(id, float, BOOL);
@property(copy) void (^pressedChangedHandler)(id, float, BOOL);
- (void)_setValue:(float)value;
@end
@implementation GCControllerButtonInput
- (instancetype)init {
    if ((self = [super init])) {
        __weak GCControllerButtonInput *weakSelf = self;
        self.valueChangedHandler = ^(id b, float v, BOOL p) { weakSelf.valueCalls++; };
        self.pressedChangedHandler = ^(id b, float v, BOOL p) { weakSelf.pressCalls++; };
    }
    return self;
}
- (void)_setValue:(float)value {
    BOOL previous = self.isPressed;
    self.value = value;
    self.isPressed = value > .5;
    if (self.valueChangedHandler) self.valueChangedHandler(self, value, self.isPressed);
    if (previous != self.isPressed && self.pressedChangedHandler)
        self.pressedChangedHandler(self, value, self.isPressed);
}
@end

// Some framework versions expose callbacks but no compatible mutable setter.
@interface CallbackOnlyButton : GCControllerButtonInput
@end
@implementation CallbackOnlyButton
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == NSSelectorFromString(@"_setValue:")) return NO;
    return [super respondsToSelector:selector];
}
@end

@interface TestPad : NSObject
@property float x;
@property float y;
@end
@implementation TestPad
@end
@interface GCExtendedGamepad : NSObject
@property(strong) GCControllerButtonInput *buttonA, *buttonB, *buttonX, *buttonY;
@property(strong) GCControllerButtonInput *leftShoulder, *rightShoulder, *leftTrigger, *rightTrigger;
@property(strong) GCControllerButtonInput *leftThumbstickButton, *rightThumbstickButton;
@property(strong) GCControllerButtonInput *buttonMenu, *buttonOptions, *buttonHome;
@property(strong) TestPad *leftThumbstick, *rightThumbstick, *dpad;
@end
@implementation GCExtendedGamepad
- (instancetype)init {
    if ((self = [super init])) {
        for (NSString *key in @[@"buttonA", @"buttonB", @"buttonX", @"buttonY", @"leftShoulder", @"rightShoulder",
                @"leftTrigger", @"rightTrigger", @"leftThumbstickButton", @"rightThumbstickButton",
                @"buttonMenu", @"buttonOptions", @"buttonHome"])
            [self setValue:[GCControllerButtonInput new] forKey:key];
        _leftThumbstick = [TestPad new]; _rightThumbstick = [TestPad new]; _dpad = [TestPad new];
    }
    return self;
}
@end
static NSArray *devices = @[];
static NSString *GCControllerDidConnectNotification = @"Connected";
static NSString *GCControllerDidDisconnectNotification = @"Disconnected";
static NSString *GCControllerDidBecomeCurrentNotification = @"BecameCurrent";
@class GCController;
static void queueGameConnection(GCController *controller, BOOL connected);
static void queueGameSelection(GCController *controller);
@interface GCController : NSObject
@property(strong) GCExtendedGamepad *extendedGamepad;
@property NSInteger gamePlayerIndex;
+ (NSArray *)controllers;
@end
@implementation GCController
+ (NSArray *)controllers { return devices; }
@end
@interface GCVirtualControllerConfiguration : NSObject
@property(copy) NSSet *elements;
@property BOOL hidden;
@end
@implementation GCVirtualControllerConfiguration
@end
@interface GCVirtualController : NSObject
@property(strong) GCController *controller;
@property(copy) void (^reply)(NSError *);
@property NSUInteger connects;
@property NSUInteger disconnects;
+ (instancetype)virtualControllerWithConfiguration:(id)configuration;
- (void)connectWithReplyHandler:(void (^)(NSError *))reply;
- (void)disconnect;
@end
@implementation GCVirtualController
+ (instancetype)virtualControllerWithConfiguration:(id)configuration { return [self new]; }
- (void)connectWithReplyHandler:(void (^)(NSError *))reply { self.connects++; self.reply = reply; }
- (void)disconnect {
    self.disconnects++;
    queueGameConnection(self.controller, NO);
    NSMutableArray *remaining = [devices mutableCopy];
    [remaining removeObject:self.controller]; devices = remaining;
    self.controller = nil;
}
@end

static NSMutableArray *pending;
static void enqueue(dispatch_queue_t queue, dispatch_block_t block) { [pending addObject:[block copy]]; }
#define dispatch_async enqueue
static void drain(void) {
    unsigned count = 0;
    while (pending.count) {
        assert(++count < 100); // Connection failures must not create a retry loop.
        dispatch_block_t block = pending.firstObject; [pending removeObjectAtIndex:0]; block();
    }
}
#include "controller-part-0.inc"
#include "controller-part-1.inc"
static FnVirtualControllerMode g_virtualControllerMode = FnVirtualControllerAuto;
static NSString *g_virtualControllerStatus;
static GCVirtualController *g_virtualController;
static BOOL isControllerModeEnabled, isTypingModeEnabled, isPopupVisible, isGCMouseDirectActive;
static BOOL isMouseLocked, isTriggerHeld;
static BOOL vctrlKeyState[10240];
#define kVirtualControllerModeKey @"virtualControllerMode"
#define FnVirtualControllerStatusDidChangeNotification @"StatusChanged"
static NSUserDefaults *testDefaults;
#define tweakDefaults() testDefaults
#define GCInputButtonA @"A"
#define GCInputButtonB @"B"
#define GCInputButtonX @"X"
#define GCInputButtonY @"Y"
#define GCInputLeftThumbstick @"LS"
#define GCInputRightThumbstick @"RS"
#define GCInputDirectionPad @"Dpad"
#define GCInputLeftShoulder @"LB"
#define GCInputRightShoulder @"RB"
#define GCInputLeftTrigger @"LT"
#define GCInputRightTrigger @"RT"
static void ue_reset_gyro_context(void) {}
static id ue_get_extended_gamepad(GCVirtualController *vc) { return vc.controller.extendedGamepad; }
static void ue_reflect_thumbstick(TestPad *pad, float x, float y) { pad.x = x; pad.y = y; }
static void dispatchControllerButton(NSInteger idx, BOOL pressed, BOOL isSync);
static void _setVirtualNamedButton(SEL selector, BOOL pressed);
#include "controller-part-2.inc"
#include "controller-part-3.inc"
#include "controller-part-4.inc"

static GCController *makeController(void) {
    GCController *controller = [GCController new]; controller.extendedGamepad = [GCExtendedGamepad new];
    return controller;
}
static void finishConnect(BOOL fail) {
    GCVirtualController *vc = g_virtualController;
    if (!fail) {
        vc.controller = makeController(); devices = [devices arrayByAddingObject:vc.controller];
        queueGameConnection(vc.controller, YES);
        queueGameSelection(vc.controller);
    }
    void (^reply)(NSError *) = vc.reply; vc.reply = nil;
    assert(reply);
    reply(fail ? [NSError errorWithDomain:@"fixture" code:1 userInfo:nil] : nil);
    drain();
}

// Model the installed game's separate event queue and four controller slots.
// Connect assigns a free slot; disconnect removes only that device. The current
// event promotes an already registered device to local player 0. Merely removing
// a virtual device does not promote the remaining physical device.
static NSMutableArray *gameSlots, *gameEvents;
static NSUInteger selectionNotifications;
static void queueGameConnection(GCController *controller, BOOL connected) {
    if (!gameEvents || !controller) return;
    [gameEvents addObject:[^{
        if (connected) {
            for (NSUInteger i = 0; i < gameSlots.count; i++) {
                if (gameSlots[i] == NSNull.null) {
                    gameSlots[i] = controller;
                    controller.gamePlayerIndex = i;
                    break;
                }
            }
        } else {
            for (NSUInteger i = 0; i < gameSlots.count; i++) {
                if (gameSlots[i] == controller) gameSlots[i] = NSNull.null;
            }
        }
    } copy]];
}
static void queueGameSelection(GCController *controller) {
    if (!gameEvents || !controller) return;
    [gameEvents addObject:[^{
        NSInteger previousIndex = -1;
        for (id device in gameSlots) {
            if (device == controller) {
                previousIndex = controller.gamePlayerIndex;
                if (previousIndex == 0) return;
                controller.gamePlayerIndex = 0;
            }
        }
        for (id device in gameSlots) {
            if (device != NSNull.null && device != controller && [device gamePlayerIndex] == 0)
                [device setGamePlayerIndex:previousIndex];
        }
    } copy]];
}
static void flushGameEvents(void) {
    NSArray *events = [gameEvents copy]; [gameEvents removeAllObjects];
    for (dispatch_block_t block in events) block();
}
static void deliverPhysicalNotification(GCController *controller, BOOL connected) {
    handleControllerNotification([NSNotification notificationWithName:connected
        ? GCControllerDidConnectNotification : GCControllerDidDisconnectNotification object:controller]);
    // The game's original observer runs before the main-queue handoff block.
    queueGameConnection(controller, connected);
}
static void testGameHandoff(void) {
    fnSetVirtualControllerMode(FnVirtualControllerOff);
    devices = @[];
    gameSlots = [NSMutableArray arrayWithArray:@[NSNull.null, NSNull.null, NSNull.null, NSNull.null]];
    gameEvents = [NSMutableArray new];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidBecomeCurrentNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            selectionNotifications++;
            queueGameSelection(note.object);
        }];
    fnSetVirtualControllerMode(FnVirtualControllerAuto); finishConnect(NO); flushGameEvents();
    GCController *physical = makeController();
    [physical.extendedGamepad.buttonA _setValue:1];
    NSUInteger valueCalls = physical.extendedGamepad.buttonA.valueCalls;
    NSUInteger attempts = g_virtualController.connects;
    deliverPhysicalNotification(physical, YES);
    flushGameEvents();
    assert(physical.gamePlayerIndex == 1); // Reproduces ignored local-player input.
    drain(); flushGameEvents();
    assert(physical.gamePlayerIndex == 0 && physical.extendedGamepad.buttonA.isPressed);
    assert(physical.extendedGamepad.buttonA.valueCalls == valueCalls);
    assert(!isControllerModeEnabled && !g_virtualControllerConnected && !g_virtualGamepad);
    assert(g_virtualController.connects == attempts); // No virtual recovery pulse.
    assert(selectionNotifications == 1);
    assert([testDefaults integerForKey:kVirtualControllerModeKey] == FnVirtualControllerAuto);
    deliverPhysicalNotification(physical, YES); // Duplicate event needs no handoff.
    drain(); flushGameEvents(); assert(selectionNotifications == 1);
    // Reconnect with the same object; a current event arriving before registration
    // cannot select it. The deferred handoff must run after the connection event.
    deliverPhysicalNotification(physical, NO);
    drain(); finishConnect(NO); flushGameEvents();
    queueGameSelection(physical);
    deliverPhysicalNotification(physical, YES);
    drain(); flushGameEvents();
    assert(physical.gamePlayerIndex == 0 && selectionNotifications == 2);
    // Physical arrival while a virtual connection is pending waits for teardown.
    deliverPhysicalNotification(physical, NO); drain(); flushGameEvents();
    assert(g_connectingVirtualController);
    GCController *replacement = makeController();
    deliverPhysicalNotification(replacement, YES); drain(); flushGameEvents();
    assert(selectionNotifications == 2 && g_pendingPhysicalHandoff == replacement);
    finishConnect(NO); flushGameEvents();
    assert(selectionNotifications == 3 && replacement.gamePlayerIndex == 0);
    assert(!g_virtualControllerConnected && !g_pendingPhysicalHandoff);
    // Disconnect before the deferred selection invalidates it.
    deliverPhysicalNotification(replacement, NO); drain(); finishConnect(NO); flushGameEvents();
    deliverPhysicalNotification(replacement, YES);
    dispatch_block_t refresh = pending.firstObject; [pending removeObjectAtIndex:0]; refresh();
    deliverPhysicalNotification(replacement, NO); drain(); finishConnect(NO); flushGameEvents();
    assert(selectionNotifications == 3);
    // An explicit mode change also cancels the queued selection.
    deliverPhysicalNotification(replacement, YES);
    refresh = pending.firstObject; [pending removeObjectAtIndex:0]; refresh();
    fnSetVirtualControllerMode(FnVirtualControllerOff);
    drain(); flushGameEvents(); assert(selectionNotifications == 3);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}
int main(void) { @autoreleasepool {
    // Preferences are isolated so this test never changes the user's settings.
    NSString *suite = [@"FnControllerTests." stringByAppendingString:NSUUID.UUID.UUIDString];
    testDefaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    pending = [NSMutableArray new];
    g_controllerLifecycleStarted = YES;
    GCController *physical = makeController(); devices = @[physical];
    fnSetVirtualControllerMode((FnVirtualControllerMode)-1);
    assert(g_virtualControllerMode == FnVirtualControllerAuto);
    assert([testDefaults integerForKey:kVirtualControllerModeKey] == FnVirtualControllerAuto);
    assert(!g_virtualController && !isControllerModeEnabled);
    devices = @[]; fnRefreshVirtualController();
    assert(g_connectingVirtualController && !isControllerModeEnabled);
    finishConnect(NO);
    assert(isControllerModeEnabled);
    GCExtendedGamepad *virtualPad = g_virtualGamepad;
    devices = [devices arrayByAddingObject:physical];
    g_virtualControllerMode = FnVirtualControllerOn;
    fnRefreshVirtualController();
    dispatchControllerButton(FnCtrlR1, YES, YES);
    dispatchControllerButton(FnCtrlR1, YES, YES);
    assert(virtualPad.rightShoulder.valueCalls == 1 && virtualPad.rightShoulder.pressCalls == 1);
    assert(physical.extendedGamepad.rightShoulder.valueCalls == 0);
    virtualPad.leftShoulder = [CallbackOnlyButton new];
    dispatchControllerButton(FnCtrlL1, YES, YES);
    dispatchControllerButton(FnCtrlL1, YES, YES);
    dispatchControllerButton(FnCtrlL1, NO, YES);
    assert(virtualPad.leftShoulder.valueCalls == 2 && virtualPad.leftShoulder.pressCalls == 2);
    dispatchControllerButton(FnCtrlDpadUp, YES, YES);
    assert(virtualPad.dpad.y == 1 && physical.extendedGamepad.dpad.y == 0);
    [physical.extendedGamepad.rightShoulder _setValue:1];
    resetControllerState();
    assert(virtualPad.rightShoulder.valueCalls == 2);
    assert(physical.extendedGamepad.rightShoulder.value == 1);
    isMouseLocked = YES;
    assert(!fnShouldSynthesizeMouseMotion()); // Physical motion wins even in On.
    g_virtualControllerMode = FnVirtualControllerAuto; fnRefreshVirtualController();
    assert(!isControllerModeEnabled && !g_virtualGamepad);
    dispatchControllerButton(FnCtrlL1, YES, YES);
    assert(physical.extendedGamepad.leftShoulder.valueCalls == 0);
    // Own expected disconnect notifications cannot create reconnect loops.
    NSUInteger suspendedAttempts = g_virtualController.connects;
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:g_ownedController]);
    drain(); assert(g_virtualController.connects == suspendedAttempts);
    // A disconnect notification is authoritative even if enumeration is stale.
    assert([devices containsObject:physical]);
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:physical]);
    drain(); assert(g_connectingVirtualController && !isControllerModeEnabled);
    finishConnect(NO);
    assert(isControllerModeEnabled && fnShouldSynthesizeMouseMotion());
    // Reconnecting the same object is authoritative before it appears in the list.
    devices = @[g_ownedController];
    NSUInteger handoffAttempts = g_virtualController.connects;
    NSUInteger handoffDisconnects = g_virtualController.disconnects;
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidConnectNotification object:physical]);
    drain(); assert(!isControllerModeEnabled && !g_virtualGamepad && !g_connectingVirtualController);
    assert(g_virtualController.connects == handoffAttempts);
    assert(g_virtualController.disconnects == handoffDisconnects + 1);
    // Duplicate physical notifications must not generate another cycle.
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidConnectNotification object:physical]);
    drain(); assert(!g_connectingVirtualController);
    devices = @[physical];
    // Disconnecting one of multiple controllers keeps Auto suspended, including
    // a new controller whose connect notification precedes enumeration.
    GCController *secondPhysical = makeController();
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidConnectNotification object:secondPhysical]);
    drain();
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:physical]);
    drain(); assert(!isControllerModeEnabled);
    devices = @[physical, secondPhysical];
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:secondPhysical]);
    drain(); finishConnect(NO);
    assert(isControllerModeEnabled && fnShouldSynthesizeMouseMotion());
    // Repeated refreshes must not resurrect disconnected objects in a stale list.
    fnRefreshVirtualController();
    assert(isControllerModeEnabled && fnShouldSynthesizeMouseMotion());
    // Reconnect may expose a fresh GCController instance while the old one lingers.
    GCController *replacementPhysical = makeController();
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidConnectNotification object:replacementPhysical]);
    drain();
    assert(!isControllerModeEnabled);
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:replacementPhysical]);
    drain(); assert(g_connectingVirtualController);
    // Another arrival while virtual connect is pending cancels its completion.
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidConnectNotification object:replacementPhysical]);
    drain(); finishConnect(NO); // Stale connection from before physical arrival.
    assert(!isControllerModeEnabled && !g_virtualGamepad && !g_connectingVirtualController);
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:replacementPhysical]);
    drain(); finishConnect(NO);
    assert(isControllerModeEnabled && fnShouldSynthesizeMouseMotion());
    devices = @[g_ownedController];
    // An unexpected loss of the owned device starts one reconnect with fresh caches.
    GCController *lostController = g_ownedController;
    [g_virtualController disconnect];
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:lostController]);
    drain(); assert(g_connectingVirtualController && !isControllerModeEnabled);
    finishConnect(NO); assert(isControllerModeEnabled);
    isTypingModeEnabled = YES; assert(!fnShouldSynthesizeMouseMotion()); isTypingModeEnabled = NO;
    isPopupVisible = YES; assert(!fnShouldSynthesizeMouseMotion()); isPopupVisible = NO;
    isGCMouseDirectActive = YES; assert(!fnShouldSynthesizeMouseMotion()); isGCMouseDirectActive = NO;
    g_virtualControllerMode = FnVirtualControllerOff; fnRefreshVirtualController();
    assert(!isControllerModeEnabled && !g_virtualGamepad);
    // Off while connecting cancels completion; no stale cache or held state survives.
    g_virtualControllerMode = FnVirtualControllerOn; fnRefreshVirtualController();
    g_virtualControllerMode = FnVirtualControllerOff; fnRefreshVirtualController(); finishConnect(NO);
    assert(!isControllerModeEnabled && !g_virtualGamepad && !g_connectingVirtualController);
    // On/Off/On while connecting waits for stale completion then starts one fresh connection.
    g_virtualControllerMode = FnVirtualControllerOn; fnRefreshVirtualController();
    NSUInteger attempts = g_virtualController.connects;
    g_virtualControllerMode = FnVirtualControllerOff; fnRefreshVirtualController();
    g_virtualControllerMode = FnVirtualControllerOn; fnRefreshVirtualController();
    assert(g_virtualController.connects == attempts);
    finishConnect(NO); assert(g_connectingVirtualController && !isControllerModeEnabled);
    finishConnect(NO); assert(isControllerModeEnabled);
    // Failure exposes no profile, doesn't swallow input, and waits for explicit retry.
    g_virtualControllerMode = FnVirtualControllerOff; fnRefreshVirtualController();
    g_virtualControllerMode = FnVirtualControllerOn; fnRefreshVirtualController(); finishConnect(YES);
    assert(!isControllerModeEnabled && !g_virtualGamepad && !g_connectingVirtualController);
    assert([g_virtualControllerStatus hasPrefix:@"Connection failed:"]);
    NSUInteger failedAttempts = g_virtualController.connects;
    handleControllerNotification([NSNotification notificationWithName:GCControllerDidDisconnectNotification object:g_ownedController]);
    drain(); assert(g_virtualController.connects == failedAttempts);
    fnRefreshVirtualController(); finishConnect(NO); assert(isControllerModeEnabled);
    testGameHandoff();
    [testDefaults removePersistentDomainForName:suite];
    puts("Controller tests passed: isolation, deduplication, native motion policy, hotplug, native handoff, cancellation, failure/retry.");
} }
