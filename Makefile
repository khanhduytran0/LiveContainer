ARCHS := arm64
TARGET := iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = LiveContainer

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LiveContainer

LiveContainer_FILES = main.m LCAppDelegate.m LCRootViewController.m dyld_bypass_validation.m utils.m
LiveContainer_FRAMEWORKS = UIKit
LiveContainer_CFLAGS = -fcommon -fobjc-arc
LiveContainer_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/application.mk
