#import "PerformanceGuard.h"
#import <sys/resource.h>
#import <objc/runtime.h>

@interface PerformanceGuard ()
@property (nonatomic, strong) id <NSObject> activityToken;
@end

@implementation PerformanceGuard

+ (instancetype)sharedInstance {
    static PerformanceGuard *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PerformanceGuard alloc] init];
    });
    return instance;
}

- (void)startHyperPerformanceMode {
    if (self.activityToken) return;

    // LEVEL 16: Fluid Activity Mode (Smart Activity)
    // We request NSActivityUserInitiated which kills App Nap and keeps the process
    // active, but without the extreme NSActivityLatencyCritical that can lead to 
    // hard thermal throttling on some Macs.
    self.activityToken = [[NSProcessInfo processInfo] beginActivityWithOptions:(NSActivityUserInitiated)
                                                                       reason:@"FnMacTweak Extreme Performance Mode (L15)"];
    
    NSLog(@"[FnMacTweak] Hyper-Performance Mode Activated (App Nap Dead)");
}

- (void)elevateProcessPriority {
    // LEVEL 16: High Performance Priority (Niceness -10)
    // -20 was starving the WindowServer. -10 keeps the game prioritized above
    // background tasks but lets the OS display systems run fluidly.
    int result = setpriority(PRIO_PROCESS, 0, -10);
    if (result == 0) {
        NSLog(@"[FnMacTweak] Process priority elevated to -20 (Dominance Mode)");
    } else {
        NSLog(@"[FnMacTweak] Failed to elevate priority (Error: %d). System may have restricted permissions.", errno);
    }
}

- (NSString *)currentThermalState {
    NSProcessInfoThermalState state = [NSProcessInfo processInfo].thermalState;
    switch (state) {
        case NSProcessInfoThermalStateNominal:  return @"Nominal";
        case NSProcessInfoThermalStateFair:     return @"Fair (Warm)";
        case NSProcessInfoThermalStateSerious:  return @"Serious (Throttling imminent)";
        case NSProcessInfoThermalStateCritical: return @"Critical (THROTTLED)";
    }
}

@end
