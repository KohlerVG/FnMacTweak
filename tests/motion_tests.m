#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <mach/mach_time.h>
#include <stdatomic.h>
#include <assert.h>
#include <math.h>

static _Atomic BOOL testPolicy;
static _Atomic uint64_t testTicks;
static int policyCalls;
static int deactivateOnCall;
BOOL fnShouldSynthesizeMouseMotion(void) {
    if (deactivateOnCall && ++policyCalls == deactivateOnCall) {
        atomic_store(&testPolicy, NO);
    }
    return atomic_load(&testPolicy);
}
static uint64_t testAbsoluteTime(void) { return atomic_load(&testTicks); }
static kern_return_t testTimebase(mach_timebase_info_t info) {
    info->numer = 1;
    info->denom = 1;
    return KERN_SUCCESS;
}
#define mach_absolute_time testAbsoluteTime
#define mach_timebase_info testTimebase

id g_virtualController;
_Atomic uint64_t g_lastGyroPollTime;
_Atomic double mouseAccumBufferX[2], mouseAccumBufferY[2];
_Atomic uint64_t mouseHardwareTimestamp[2];
_Atomic int activeBufferIdx;
_Atomic double g_quantumPushedX, g_quantumPushedY;
static double GYRO_SENSE = 2;
static double GYRO_MULTIPLIER = 100;
static struct { _Atomic BOOL enabled; } g_godReflex;

// This file is generated from the current production implementation by the runner.
#include "motion-under-test.inc"

@interface TestController : NSObject
@property(nonatomic, strong) id motion;
@end
@implementation TestController
@end
@interface TestVirtualController : NSObject
@property(nonatomic, strong) TestController *controller;
@end
@implementation TestVirtualController
@end

static int gcCalls, managerCalls, deviceCalls;
static CMRotationRate nativeGC(id object, SEL selector) {
    gcCalls++;
    return (CMRotationRate){11, 12, 13};
}
static CMRotationRate nativeManager(id object, SEL selector) {
    managerCalls++;
    return (CMRotationRate){21, 22, 23};
}
static CMRotationRate nativeDevice(id object, SEL selector) {
    deviceCalls++;
    return (CMRotationRate){31, 32, 33};
}
static void expectRate(CMRotationRate rate, double x, double y, double z) {
    assert(fabs(rate.x - x) < 0.000001);
    assert(fabs(rate.y - y) < 0.000001);
    assert(fabs(rate.z - z) < 0.000001);
}
static void accumulate(double x, double y) {
    int index = atomic_load(&activeBufferIdx);
    atomic_fetch_add(&mouseAccumBufferX[index], x);
    atomic_fetch_add(&mouseAccumBufferY[index], y);
}

int main(void) {
    @autoreleasepool {
        SEL selector = @selector(rotationRate);
        NSObject *physicalMotion = [NSObject new];
        NSObject *virtualMotion = [NSObject new];
        TestVirtualController *virtual = [TestVirtualController new];
        virtual.controller = [TestController new];
        virtual.controller.motion = virtualMotion;
        g_virtualController = virtual;
        orig_gc_rotationRate = nativeGC;
        orig_manager_rotationRate = nativeManager;
        orig_dm_rotationRate = nativeDevice;

        // Inactive hooks preserve the three distinct native implementations.
        atomic_store(&testPolicy, NO);
        expectRate(hooked_gc_rotationRate(physicalMotion, selector), 11, 12, 13);
        expectRate(hooked_manager_rotationRate(nil, selector), 21, 22, 23);
        expectRate(hooked_dm_rotationRate(nil, selector), 31, 32, 33);
        assert(gcCalls == 1 && managerCalls == 1 && deviceCalls == 1);

        // A physical motion object stays native even during mouse synthesis.
        atomic_store(&testPolicy, YES);
        accumulate(999, 999);
        expectRate(hooked_gc_rotationRate(physicalMotion, selector), 11, 12, 13);
        assert(atomic_load(&mouseAccumBufferX[0]) == 999);
        atomic_store(&testTicks, 1000000);
        expectRate(hooked_gc_rotationRate(virtualMotion, selector), 0, 0, 0);
        assert(atomic_load(&mouseAccumBufferX[0]) == 0); // Idle accumulation discarded.

        // Eligible virtual polling consumes the actual accumulated displacement.
        accumulate(4, 8);
        atomic_store(&testTicks, 2000000);
        expectRate(hooked_gc_rotationRate(virtualMotion, selector), 8000, 16000, 0);
        assert(gcCalls == 2);
        accumulate(3, 5);
        atomic_store(&g_quantumPushedX, 1);
        atomic_store(&g_quantumPushedY, 2);
        atomic_store(&testTicks, 3000000);
        expectRate(hooked_dm_rotationRate(nil, selector), 4000, 6000, 0);

        // Stop resets all buffers, compensation and clock, then returns native data.
        accumulate(10, 20);
        atomic_store(&g_quantumPushedX, 3);
        atomic_store(&g_quantumPushedY, 4);
        atomic_store(&testPolicy, NO);
        expectRate(hooked_manager_rotationRate(nil, selector), 21, 22, 23);
        assert(atomic_load(&g_lastGyroPollTime) == 0);
        assert(atomic_load(&mouseAccumBufferX[0]) == 0);
        assert(atomic_load(&mouseAccumBufferX[1]) == 0);
        assert(atomic_load(&g_quantumPushedX) == 0);
        assert(atomic_load(&g_quantumPushedY) == 0);

        // Restart establishes a fresh time origin instead of releasing stale input.
        accumulate(1000, 1000);
        atomic_store(&testPolicy, YES);
        atomic_store(&testTicks, 4000000);
        expectRate(hooked_manager_rotationRate(nil, selector), 0, 0, 0);
        accumulate(1, 2);
        atomic_store(&testTicks, 4050000);
        expectRate(hooked_manager_rotationRate(nil, selector), 0, 0, 0);
        assert(atomic_load(&g_lastGyroPollTime) == 4000000);
        atomic_store(&testTicks, 4110000);
        expectRate(hooked_manager_rotationRate(nil, selector), 2 / 0.00011, 4 / 0.00011, 0);

        // Policy changing between eligibility and sampling cannot synthesize input.
        accumulate(1, 1);
        policyCalls = 0;
        deactivateOnCall = 2;
        expectRate(hooked_manager_rotationRate(nil, selector), 0, 0, 0);
        assert(!g_mouseMotionWasActive);
        assert(atomic_load(&g_lastGyroPollTime) == 0);
        deactivateOnCall = 0;

        // Exercise reset/poll serialization on concurrent game and lifecycle queues.
        atomic_store(&testPolicy, YES);
        dispatch_apply(2000, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t i) {
            if (i % 2) ue_reset_gyro_context();
            else {
                CMRotationRate rate = hooked_dm_rotationRate(nil, selector);
                assert(isfinite(rate.x) && isfinite(rate.y) && isfinite(rate.z));
            }
        });
        ue_reset_gyro_context();
        assert(!g_mouseMotionWasActive);
        puts("motion regression tests passed");
    }
    return 0;
}
