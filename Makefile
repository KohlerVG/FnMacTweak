TARGET := iphone:clang:latest:26.0
INSTALL_TARGET_PROCESSES = SpringBoard
ADDITIONAL_TARGETS = postinst

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FnMacTweak

FnMacTweak_FILES = ./src/Tweak.xm ./src/FnOverlayWindow.m ./src/views/popupViewController.m ./src/views/welcomeViewController.m ./src/globals.m ./lib/fishhook.c
FnMacTweak_FRAMEWORKS = UIKit WebKit
FnMacTweak_CFLAGS = -fobjc-arc -O3

DEBUG = 0

include $(THEOS_MAKE_PATH)/tweak.mk
