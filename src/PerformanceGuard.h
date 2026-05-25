#import <Foundation/Foundation.h>

@interface PerformanceGuard : NSObject

+ (instancetype)sharedInstance;

/// Disables App Nap and all power-saving throttling for the process.
- (void)startHyperPerformanceMode;

/// Elevates the process priority to the highest system level (-20).
- (void)elevateProcessPriority;

/// Returns the current thermal state of the device.
- (NSString *)currentThermalState;

@end
