#import <QuartzCore/QuartzCore.h>
#import <GameController/GameController.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "./globals.h"
#import "./ue_reflection.h"

// ---------------------------------------------------------------------------
// Gyro-Mouse Proxy State
// ---------------------------------------------------------------------------

void ue_apply_gyro_velocity(double vx, double vy) {
    // Latch is bypassed in the zero-latency demand-driven mode, 
    // but kept for API compatibility.
}

#include <stdatomic.h>
#import <os/lock.h>
#import <mach/mach_time.h>

static os_unfair_lock g_gyroContextLock = OS_UNFAIR_LOCK_INIT;
static BOOL g_mouseMotionWasActive = NO;

typedef CMRotationRate (*FnRotationRateIMP)(id, SEL);
static FnRotationRateIMP orig_gc_rotationRate = NULL;
static FnRotationRateIMP orig_manager_rotationRate = NULL;
static FnRotationRateIMP orig_dm_rotationRate = NULL;

// Called with g_gyroContextLock held so reset cannot race a motion sample.
static void resetGyroContextLocked(void) {
    atomic_store(&g_lastGyroPollTime, 0);
    atomic_store(&mouseAccumBufferX[0], 0);
    atomic_store(&mouseAccumBufferX[1], 0);
    atomic_store(&mouseAccumBufferY[0], 0);
    atomic_store(&mouseAccumBufferY[1], 0);
    atomic_store(&activeBufferIdx, 0);
    atomic_store(&mouseHardwareTimestamp[0], 0);
    atomic_store(&mouseHardwareTimestamp[1], 0);
    atomic_store(&g_quantumPushedX, 0);
    atomic_store(&g_quantumPushedY, 0);
}

void ue_reset_gyro_context(void) {
    os_unfair_lock_lock(&g_gyroContextLock);
    resetGyroContextLocked();
    g_mouseMotionWasActive = NO;
    os_unfair_lock_unlock(&g_gyroContextLock);
}

static BOOL mouseMotionSynthesisIsActive(void) {
    os_unfair_lock_lock(&g_gyroContextLock);
    BOOL active = fnShouldSynthesizeMouseMotion();
    if (!active && g_mouseMotionWasActive) {
        resetGyroContextLocked();
        g_mouseMotionWasActive = NO;
    }
    os_unfair_lock_unlock(&g_gyroContextLock);
    return active;
}

static CMRotationRate sampleMouseRotationRate(void) {
    CMRotationRate rate = {0, 0, 0};
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&timebase); });

    os_unfair_lock_lock(&g_gyroContextLock);
    // Recheck after taking the lock: a disconnect or mode transition may have
    // happened between the hook's eligibility check and this sample.
    if (!fnShouldSynthesizeMouseMotion()) {
        resetGyroContextLocked();
        g_mouseMotionWasActive = NO;
        os_unfair_lock_unlock(&g_gyroContextLock);
        return rate;
    }

    uint64_t now = mach_absolute_time();
    if (!g_mouseMotionWasActive) {
        // Establish a fresh interval and discard motion collected while idle.
        resetGyroContextLocked();
        g_mouseMotionWasActive = YES;
        atomic_store(&g_lastGyroPollTime, now);
        os_unfair_lock_unlock(&g_gyroContextLock);
        return rate;
    }

    uint64_t last = atomic_load(&g_lastGyroPollTime);
    double dt = (double)(now - last) * (double)timebase.numer /
                (double)timebase.denom / 1e9;
    if (dt > 0.0001) {
        atomic_store(&g_lastGyroPollTime, now);
        int oldIdx = atomic_load(&activeBufferIdx);
        atomic_store(&activeBufferIdx, 1 - oldIdx);
        double accX = atomic_exchange(&mouseAccumBufferX[oldIdx], 0.0);
        double accY = atomic_exchange(&mouseAccumBufferY[oldIdx], 0.0);
        double pushedX = atomic_exchange(&g_quantumPushedX, 0.0);
        double pushedY = atomic_exchange(&g_quantumPushedY, 0.0);
        double scale = GYRO_SENSE * (GYRO_MULTIPLIER / 100.0);
        rate.x = (accX - pushedX) * scale / dt;
        rate.y = (accY - pushedY) * scale / dt;
    }
    os_unfair_lock_unlock(&g_gyroContextLock);
    return rate;
}

static CMRotationRate originalRotationRate(FnRotationRateIMP original, id object, SEL selector) {
    if (original) return original(object, selector);
    CMRotationRate zero = {0, 0, 0};
    return zero;
}

static CMRotationRate hooked_gc_rotationRate(id self, SEL _cmd) {
    BOOL active = mouseMotionSynthesisIsActive();
    id controller = nil;
    if (g_virtualController && [g_virtualController respondsToSelector:@selector(controller)]) {
        controller = [g_virtualController controller];
    }
    // Never replace motion supplied by a physical controller.
    if (!active || !controller || self != [controller motion]) {
        return originalRotationRate(orig_gc_rotationRate, self, _cmd);
    }
    return sampleMouseRotationRate();
}

static CMRotationRate hooked_manager_rotationRate(id self, SEL _cmd) {
    if (!mouseMotionSynthesisIsActive()) {
        return originalRotationRate(orig_manager_rotationRate, self, _cmd);
    }
    return sampleMouseRotationRate();
}

static CMRotationRate hooked_dm_rotationRate(id self, SEL _cmd) {
    if (!mouseMotionSynthesisIsActive()) {
        return originalRotationRate(orig_dm_rotationRate, self, _cmd);
    }
    return sampleMouseRotationRate();
}

void ue_init_gyro_hooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The old Unreal orientation interposition did not preserve its original
        // implementation or identify the owned controller. Leave it native.
        atomic_store(&g_godReflex.enabled, NO);

        Method gcMethod = class_getInstanceMethod(NSClassFromString(@"GCMotion"), @selector(rotationRate));
        if (gcMethod) {
            orig_gc_rotationRate = (FnRotationRateIMP)method_getImplementation(gcMethod);
            method_setImplementation(gcMethod, (IMP)hooked_gc_rotationRate);
        }
        Method managerMethod = class_getInstanceMethod(NSClassFromString(@"CMMotionManager"), @selector(rotationRate));
        if (managerMethod) {
            orig_manager_rotationRate = (FnRotationRateIMP)method_getImplementation(managerMethod);
            method_setImplementation(managerMethod, (IMP)hooked_manager_rotationRate);
        }
        Method deviceMethod = class_getInstanceMethod(NSClassFromString(@"CMDeviceMotion"), @selector(rotationRate));
        if (deviceMethod) {
            orig_dm_rotationRate = (FnRotationRateIMP)method_getImplementation(deviceMethod);
            method_setImplementation(deviceMethod, (IMP)hooked_dm_rotationRate);
        }
    });
}

// ---------------------------------------------------------------------------
// Button reflection (Existing)
// ---------------------------------------------------------------------------

void ue_reflect_button_press(id buttonInput) {
    if (!buttonInput) return;
    static void (*cachedSetValue)(id, SEL, float) = NULL;
    static SEL sel = NULL;
    static BOOL tried = NO;
    if (!tried) {
        sel = NSSelectorFromString(@"_setValue:");
        Method m = class_getInstanceMethod(NSClassFromString(@"GCControllerElement"), sel); // Base class
        if (!m) m = class_getInstanceMethod(NSClassFromString(@"GCControllerButtonInput"), sel);
        if (m) cachedSetValue = (void (*)(id, SEL, float))method_getImplementation(m);
        tried = YES;
    }
    float value = 1.0f;
    if (cachedSetValue) {
        cachedSetValue(buttonInput, sel, value);
    } else {
        ((void (*)(id, SEL, float))objc_msgSend)(buttonInput, sel, value);
    }
}

void ue_reflect_button_release(id buttonInput) {
    if (!buttonInput) return;
    static void (*cachedSetValue)(id, SEL, float) = NULL;
    static SEL sel = NULL;
    static BOOL tried = NO;
    if (!tried) {
        sel = NSSelectorFromString(@"_setValue:");
        Method m = class_getInstanceMethod(NSClassFromString(@"GCControllerElement"), sel);
        if (!m) m = class_getInstanceMethod(NSClassFromString(@"GCControllerButtonInput"), sel);
        if (m) cachedSetValue = (void (*)(id, SEL, float))method_getImplementation(m);
        tried = YES;
    }
    float value = 0.0f;
    if (cachedSetValue) {
        cachedSetValue(buttonInput, sel, value);
    } else {
        ((void (*)(id, SEL, float))objc_msgSend)(buttonInput, sel, value);
    }
}

// ---------------------------------------------------------------------------
// Thumbstick reflection (Existing Fallback)
// ---------------------------------------------------------------------------

void ue_reflect_thumbstick(id directionPad, float x, float y) {
    if (!directionPad) return;

    // Linearization for stick fallback
    float dz = 0.15f; 
    float len = sqrtf(x*x + y*y);
    if (len > 0.0001f) {
        float newLen = dz + len * (1.0f - dz);
        x = (x / len) * newLen;
        y = (y / len) * newLen;
    } else {
        x = 0;
        y = 0;
    }

    static void (*cachedPrivateSetXY)(id, SEL, float, float) = NULL;
    static SEL privateCombined = NULL;
    static BOOL triedPrivate = NO;
    
    if (!triedPrivate) {
        privateCombined = NSSelectorFromString(@"_setValueX:Y:");
        Method m = class_getInstanceMethod(NSClassFromString(@"GCControllerDirectionPad"), privateCombined);
        if (m) cachedPrivateSetXY = (void (*)(id, SEL, float, float))method_getImplementation(m);
        triedPrivate = YES;
    }

    if (cachedPrivateSetXY) {
        cachedPrivateSetXY(directionPad, privateCombined, x, y);
        return;
    }

    static SEL publicCombined = NULL;
    if (!publicCombined) publicCombined = NSSelectorFromString(@"setValueX:Y:");
    if ([directionPad respondsToSelector:publicCombined]) {
        ((void (*)(id, SEL, float, float))objc_msgSend)(directionPad, publicCombined, x, y);
        return;
    }

    static SEL axisSetValue = NULL;
    if (!axisSetValue) axisSetValue = NSSelectorFromString(@"_setValue:");
    static SEL xAxisSel = NULL;
    static SEL yAxisSel = NULL;
    if (!xAxisSel) xAxisSel = NSSelectorFromString(@"xAxis");
    if (!yAxisSel) yAxisSel = NSSelectorFromString(@"yAxis");

    id xAxis = [directionPad respondsToSelector:xAxisSel] ? ((id (*)(id, SEL))objc_msgSend)(directionPad, xAxisSel) : nil;
    id yAxis = [directionPad respondsToSelector:yAxisSel] ? ((id (*)(id, SEL))objc_msgSend)(directionPad, yAxisSel) : nil;

    if (xAxis && [xAxis respondsToSelector:axisSetValue])
        ((void (*)(id, SEL, float))objc_msgSend)(xAxis, axisSetValue, x);

    if (yAxis && [yAxis respondsToSelector:axisSetValue])
        ((void (*)(id, SEL, float))objc_msgSend)(yAxis, axisSetValue, y);
}

// ---------------------------------------------------------------------------
// Controller helpers (Existing)
// ---------------------------------------------------------------------------

id ue_get_extended_gamepad(id virtualController) {
    if (!virtualController) return nil;
    static SEL controllerSel = NULL;
    static SEL gamepadSel    = NULL;
    if (!controllerSel) controllerSel = NSSelectorFromString(@"controller");
    if (!gamepadSel)    gamepadSel    = NSSelectorFromString(@"extendedGamepad");

    id controller = [virtualController respondsToSelector:controllerSel] ? ((id (*)(id, SEL))objc_msgSend)(virtualController, controllerSel) : nil;
    if (!controller) return nil;

    return [controller respondsToSelector:gamepadSel] ? ((id (*)(id, SEL))objc_msgSend)(controller, gamepadSel) : nil;
}

id ue_get_button(id gamepad, NSString *element) {
    if (!gamepad || !element) return nil;
    SEL sel = nil;
    if ([element isEqualToString:GCInputButtonA]) sel = NSSelectorFromString(@"buttonA");
    else if ([element isEqualToString:GCInputButtonB]) sel = NSSelectorFromString(@"buttonB");
    else if ([element isEqualToString:GCInputButtonX]) sel = NSSelectorFromString(@"buttonX");
    else if ([element isEqualToString:GCInputButtonY]) sel = NSSelectorFromString(@"buttonY");
    if (!sel || ![gamepad respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(gamepad, sel);
}

id ue_get_thumbstick(id gamepad, NSString *element) {
    if (!gamepad || !element) return nil;
    SEL sel = nil;
    if ([element isEqualToString:GCInputLeftThumbstick]) sel = NSSelectorFromString(@"leftThumbstick");
    else if ([element isEqualToString:GCInputRightThumbstick]) sel = NSSelectorFromString(@"rightThumbstick");
    if (!sel || ![gamepad respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(gamepad, sel);
}
