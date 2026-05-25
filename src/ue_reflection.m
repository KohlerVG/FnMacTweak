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
void ue_reset_gyro_context(void) {
    atomic_store(&g_lastGyroPollTime, 0);
    atomic_store(&mouseAccumBufferX[0], 0);
    atomic_store(&mouseAccumBufferX[1], 0);
    atomic_store(&mouseAccumBufferY[0], 0);
    atomic_store(&mouseAccumBufferY[1], 0);
    atomic_store(&activeBufferIdx, 0);
    atomic_store(&mouseHardwareTimestamp[0], 0);
    atomic_store(&mouseHardwareTimestamp[1], 0);
}

// ---------------------------------------------------------------------------
// CoreMotion Hooking (Method Swizzling)
// ---------------------------------------------------------------------------

static CMRotationRate (*orig_rotationRate)(id, SEL) = NULL;

static CMRotationRate hooked_rotationRate(id self, SEL _cmd) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ elevateThreadToRealTime(); });

    // LEVEL 23: Mach-Time Pulse Alignment
    uint64_t now_ticks = mach_absolute_time();
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) mach_timebase_info(&timebase);
    
    static uint64_t last_ticks = 0;
    if (last_ticks == 0) last_ticks = now_ticks;
    uint64_t delta_ticks = now_ticks - last_ticks;
    last_ticks = now_ticks;

    double dt = (double)delta_ticks * (double)timebase.numer / (double)timebase.denom / 1000000000.0;

    CMRotationRate rate;
    if (isGCMouseDirectActive) {
        rate.x = rate.y = rate.z = 0;
        return rate;
    }

    // LEVEL 23: Motion-Flux (Jitter-Buster Engine)
    if (dt > 0.0001) {
        int oldIdx = atomic_load(&activeBufferIdx);
        int newIdx = 1 - oldIdx;
        atomic_store(&activeBufferIdx, newIdx);
        
        double accX = atomic_exchange(&mouseAccumBufferX[oldIdx], 0.0);
        double accY = atomic_exchange(&mouseAccumBufferY[oldIdx], 0.0);

        // LEVEL 24: Temporal Balancer (Absolute 0 Nullification)
        // Subtract the amount we already 'pre-shot' into the mouse handler.
        double pushedX = atomic_exchange(&g_quantumPushedX, 0.0);
        double pushedY = atomic_exchange(&g_quantumPushedY, 0.0);
        
        // The 'Pull' amount is the remainder (Acc - Pushed)
        // This ensures math stays 1:1 even with 100% instant push.
        double balancedX = accX - pushedX;
        double balancedY = accY - pushedY;

        // Instant velocity using sub-millisecond precision
        double rawVx = (balancedX * GYRO_SENSE * (GYRO_MULTIPLIER / 100.0)) / dt;
        double rawVy = (balancedY * GYRO_SENSE * (GYRO_MULTIPLIER / 100.0)) / dt;
        
        // LEVEL 25: Apex-Raw (No Filtering)
        rate.x = rawVx;
        rate.y = rawVy;
    } else {
        rate.x = rate.y = 0;
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

// LEVEL 27: God-Mode (Quantum Trajectory Predictor)
// This implements a 0.2ms look-ahead to negate USB/OS bus latency.
BOOL hooked_GetControllerOrientationAndPosition(int controllerId, FQuat *outOrientation, FVector *outPosition) {
    if (!atomic_load(&g_godReflex.enabled)) return NO;
    
    // Harvest from the cache-aligned L1 block (globals.h)
    float p = atomic_load(&g_godReflex.pitch);
    float y = atomic_load(&g_godReflex.yaw);
    float r = atomic_load(&g_godReflex.roll);
    
    // Quantum Trajectory: Predict where the mouse WILL be in 0.2ms.
    // This cancels out the physical travel time through the OS/USB stack.
    float lastP = atomic_load(&g_godReflex.lastPitch);
    float lastY = atomic_load(&g_godReflex.lastYaw);
    uint64_t lastT = atomic_load(&g_godReflex.lastTimestamp);
    uint64_t nowT = mach_absolute_time();
    
    // Convert Mach-Ticks to float-seconds for velocity slope
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) mach_timebase_info(&timebase);
    float dt = (float)(nowT - lastT) * (float)timebase.numer / (float)timebase.denom / 1e9f;
    
    if (dt > 0.0001f) {
        float velocityP = (p - lastP) / dt;
        float velocityY = (y - lastY) / dt;
        
        // Predict 0.2ms into the future (Quantum Shift)
        p += (velocityP * 0.0002f);
        y += (velocityY * 0.0002f);
    }
    
    // Euler to Quaternion (Pre-Shifted Trajectory)
    float sp = sinf(p * 0.5f); float cp = cosf(p * 0.5f);
    float sy = sinf(y * 0.5f); float cy = cosf(y * 0.5f);
    float sr = sinf(r * 0.5f); float cr = cosf(r * 0.5f);
    
    outOrientation->X = sr * cp * cy - cr * sp * sy;
    outOrientation->Y = cr * sp * cy + sr * cp * sy;
    outOrientation->Z = cr * cp * sy - sr * sp * cy;
    outOrientation->W = cr * cp * cy + sr * sp * sy;
    
    return YES;
}

/**
 * ue_init_gyro_hooks
 * 
 * Sets up the swizzles for GCMotion and CMMotionManager.
 * Hooking GCMotion is critical for modern UE/GameController parity.
 */
#include "../lib/fishhook.h"

void ue_init_gyro_hooks(void) {
    // 1. Hook GCMotion (The Source of Truth for Virtual Controllers - Legacy Safety)
    Class gcMotionCls = NSClassFromString(@"GCMotion");
    if (gcMotionCls) {
        Method m0 = class_getInstanceMethod(gcMotionCls, @selector(rotationRate));
        if (m0) {
            method_setImplementation(m0, (IMP)hooked_rotationRate);
            NSLog(@"[FnMacTweak] Motion-Flux Activated: GCMotion Hooked (L23)");
        }
    }
    
    // 2. LEVEL 27: Activate God-Mode (Quantum-Reflex Binary Hook)
    // We interpose the Unreal Engine's Motion Controller implementation.
    struct rebinding rebindings[] = {
        {"_ZN21FAppleControllerDevice32GetControllerOrientationAndPositionEiR5FQuatR7FVector", 
         (void *)hooked_GetControllerOrientationAndPosition, 
         NULL}
    };
    
    if (rebind_symbols(rebindings, 1) == 0) {
        atomic_store(&g_godReflex.enabled, YES);
        NSLog(@"[FnMacTweak] God-Mode Activated: Quantum-Reflex Engaged! (L27)");
    } else {
        atomic_store(&g_godReflex.enabled, NO);
        NSLog(@"[FnMacTweak] God-Mode Warning: Final Singularity failed, falling back to legacy reflex.");
    }

    Class mgrCls = NSClassFromString(@"CMMotionManager");
    if (mgrCls) {
        // 2. Hook CMMotionManager.rotationRate (Polling raw)
        Method m1 = class_getInstanceMethod(mgrCls, @selector(rotationRate));
        if (m1) {
            orig_rotationRate = (CMRotationRate (*)(id, SEL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hooked_rotationRate);
        }

        // 3. Hook CMMotionManager async start
        Method m2 = class_getInstanceMethod(mgrCls, @selector(startDeviceMotionUpdatesToQueue:withHandler:));
        if (m2) {
            orig_startDeviceMotion = (void (*)(id, SEL, NSOperationQueue*, CMDeviceMotionHandler))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hooked_startDeviceMotion);
        }
    }

    Class dmCls = NSClassFromString(@"CMDeviceMotion");
    if (dmCls) {
        // 4. Hook CMDeviceMotion.rotationRate (Polling fused)
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
