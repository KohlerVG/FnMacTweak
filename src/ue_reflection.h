// =============================================================================
//  ue_reflection.h — FnMacTweak
//
//  Public interface for the Unreal Engine reflection bridge.
//  Import this in Tweak.xm wherever GCVirtualController state needs to be
//  propagated into Fortnite's UE input subsystem.
//
//  See ue_reflection.m for full implementation details.
// =============================================================================

#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Button reflection
// ---------------------------------------------------------------------------

/**
 * Set a GCControllerButtonInput to fully pressed (value = 1.0).
 * Updates the ivar and fires valueChangedHandler so UE polling sees the press.
 */
void ue_reflect_button_press(id buttonInput);

/**
 * Set a GCControllerButtonInput to released (value = 0.0).
 * Always call this on key-up to avoid a stuck button.
 */
void ue_reflect_button_release(id buttonInput);

// ---------------------------------------------------------------------------
// Thumbstick reflection
// ---------------------------------------------------------------------------

/**
 * Drive both axes of a GCControllerDirectionPad (e.g. leftThumbstick).
 * Tries combined setters first (_setValueX:Y: / setValueX:Y:),
 * falls back to per-axis _setValue: on xAxis / yAxis.
 *
 * @param directionPad  The GCControllerDirectionPad to update
 * @param x             Horizontal value in [-1.0, 1.0]
 * @param y             Vertical value in [-1.0, 1.0]
 */
void ue_reflect_thumbstick(id directionPad, float x, float y);

// ---------------------------------------------------------------------------
// Controller / gamepad resolution helpers
// ---------------------------------------------------------------------------

/**
 * Resolve extendedGamepad from a GCVirtualController.
 * Returns nil if the virtual controller is not yet connected.
 */
id ue_get_extended_gamepad(id virtualController);

/**
 * Return the GCControllerButtonInput for a GCInput* constant
 * (GCInputButtonA/B/X/Y) from an extendedGamepad. Returns nil if not found.
 */
id ue_get_button(id gamepad, NSString *element);

/**
 * Return the GCControllerDirectionPad for GCInputLeftThumbstick or
 * GCInputRightThumbstick from an extendedGamepad. Returns nil if not found.
 */
id ue_get_thumbstick(id gamepad, NSString *element);

// ---------------------------------------------------------------------------
// Gyro-Mouse Proxy Injection
// ---------------------------------------------------------------------------

/**
 * Initialize Gyro-Mouse Proxy hooks (Call once at startup)
 */
void ue_init_gyro_hooks(void);

/**
 * ue_apply_gyro_velocity
 * 
 * Sets the current rotational velocity (radians/second).
 * This state is held and returned by the sensors until the next update.
 */
void ue_apply_gyro_velocity(double vx, double vy);

/**
 * ue_reset_gyro_context
 * 
 * Resets the velocity state to zero.
 */
void ue_reset_gyro_context(void);

#ifdef __cplusplus
}
#endif
