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

void ue_reset_gyro_context(void) {
    g_lastGyroPollTime = 0;
    mouseAccumX = 0;
    mouseAccumY = 0;
}

// ---------------------------------------------------------------------------
// CoreMotion Hooking (Method Swizzling)
// ---------------------------------------------------------------------------

static CMRotationRate (*orig_rotationRate)(id, SEL) = NULL;

static CMRotationRate hooked_rotationRate(id self, SEL _cmd) {
    double now = CACurrentMediaTime();
    if (g_lastGyroPollTime <= 0) g_lastGyroPollTime = now;
    double dt = now - g_lastGyroPollTime;
    g_lastGyroPollTime = now;

    CMRotationRate rate;
    // Demand-Driven Integration: vx = dX / dt
    if (dt > 0.0001) {
        rate.x = (mouseAccumX * GYRO_SENSE * (GYRO_MULTIPLIER / 100.0)) / dt;
        rate.y = (mouseAccumY * GYRO_SENSE * (GYRO_MULTIPLIER / 100.0)) / dt;
        // Reset accumulation immediately after consumption (Direct 1:1)
        mouseAccumX = 0;
        mouseAccumY = 0;
    } else {
        rate.x = 0;
        rate.y = 0;
    }
    rate.z = 0;
    return rate;
}

// Hook for CMDeviceMotion.rotationRate
static CMRotationRate hooked_dm_rotationRate(id self, SEL _cmd) {
    return hooked_rotationRate(self, _cmd);
}

// Hook for startDeviceMotionUpdatesToQueue:withHandler:
static void (*orig_startDeviceMotion)(id, SEL, NSOperationQueue*, CMDeviceMotionHandler) = NULL;
static void hooked_startDeviceMotion(id self, SEL _cmd, NSOperationQueue* queue, CMDeviceMotionHandler handler) {
    orig_startDeviceMotion(self, _cmd, queue, handler);
}

/**
 * ue_init_gyro_hooks
 * 
 * Sets up the swizzles for CMMotionManager and CMDeviceMotion.
 */
void ue_init_gyro_hooks(void) {
    Class mgrCls = NSClassFromString(@"CMMotionManager");
    if (mgrCls) {
        // 1. Hook CMMotionManager.rotationRate (Polling raw)
        Method m1 = class_getInstanceMethod(mgrCls, @selector(rotationRate));
        if (m1) {
            orig_rotationRate = (CMRotationRate (*)(id, SEL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hooked_rotationRate);
        }

        // 2. Hook CMMotionManager async start
        Method m2 = class_getInstanceMethod(mgrCls, @selector(startDeviceMotionUpdatesToQueue:withHandler:));
        if (m2) {
            orig_startDeviceMotion = (void (*)(id, SEL, NSOperationQueue*, CMDeviceMotionHandler))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hooked_startDeviceMotion);
        }
    }

    Class dmCls = NSClassFromString(@"CMDeviceMotion");
    if (dmCls) {
        // 3. Hook CMDeviceMotion.rotationRate (Polling fused)
        Method m3 = class_getInstanceMethod(dmCls, @selector(rotationRate));
        if (m3) {
            method_setImplementation(m3, (IMP)hooked_dm_rotationRate);
        }
    }
}

// ---------------------------------------------------------------------------
// Button reflection (Existing)
// ---------------------------------------------------------------------------

void ue_reflect_button_press(id buttonInput) {
    if (!buttonInput) return;
    static SEL sel = NULL;
    if (!sel) sel = NSSelectorFromString(@"_setValue:");
    if (![buttonInput respondsToSelector:sel]) return;
    float value = 1.0f;
    ((void (*)(id, SEL, float))objc_msgSend)(buttonInput, sel, value);
}

void ue_reflect_button_release(id buttonInput) {
    if (!buttonInput) return;
    static SEL sel = NULL;
    if (!sel) sel = NSSelectorFromString(@"_setValue:");
    if (![buttonInput respondsToSelector:sel]) return;
    float value = 0.0f;
    ((void (*)(id, SEL, float))objc_msgSend)(buttonInput, sel, value);
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
    }

    static SEL privateCombined = NULL;
    if (!privateCombined) privateCombined = NSSelectorFromString(@"_setValueX:Y:");
    if ([directionPad respondsToSelector:privateCombined]) {
        ((void (*)(id, SEL, float, float))objc_msgSend)(directionPad, privateCombined, x, y);
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
