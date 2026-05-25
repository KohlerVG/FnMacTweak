TARGET := iphone:clang:latest:26.0
INSTALL_TARGET_PROCESSES = SpringBoard
ADDITIONAL_TARGETS = postinst
export PATH := $(PWD)/tools:$(PATH)
LDID = ldid
FnMacTweak_PACKAGE_FORMAT = gzip

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FnMacTweak

FnMacTweak_FILES = ./src/Tweak.xm ./src/FnOverlayWindow.m ./src/views/popupViewController.m ./src/views/welcomeViewController.m ./src/globals.m ./lib/fishhook.c ./src/ue_reflection.m ./src/PerformanceGuard.m
FnMacTweak_FRAMEWORKS = UIKit WebKit CoreGraphics GameController QuartzCore IOKit
FnMacTweak_CFLAGS = -fobjc-arc -O3 -Wno-c99-designator -Wno-error=c99-designator
FnMacTweak_PACKAGE_FORMAT = gzip

DEBUG = 0

include $(THEOS_MAKE_PATH)/tweak.mk

# LEVEL 16: Pulse-Link Hook (Bulletproof Signing)
# This forces a native macOS signature immediately after the build,
# bypassing the broken 'ldid' tool that exists in some Theos versions.
after-all::
	@echo "Applying Level 16 Pulse-Link Signature..."
	@codesign -f -s - $(THEOS_OBJ_DIR)/$(TWEAK_NAME).dylib
