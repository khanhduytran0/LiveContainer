ARCHS := arm64
TARGET := iphone:clang:latest:14.0
PACKAGE_FORMAT = ipa
INSTALL_TARGET_PROCESSES = LiveContainer
include $(THEOS)/makefiles/common.mk

# Build the UI library
LIBRARY_NAME = LiveContainerUI
LiveContainerUI_FILES = LCAppDelegate.m LCRootViewController.m MBRoundProgressView.m unarchive.m AppInfo.m
LiveContainerUI_CFLAGS = -fobjc-arc
LiveContainerUI_FRAMEWORKS = CoreGraphics QuartzCore UIKit UniformTypeIdentifiers
LiveContainerUI_LIBRARIES = archive
LiveContainerUI_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks
include $(THEOS_MAKE_PATH)/library.mk

# Build the app
APPLICATION_NAME = LiveContainer
$(APPLICATION_NAME)_FILES = dyld_bypass_validation.m main.m utils.m FixCydiaSubstrate.c fishhook/fishhook.c
$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.xml
$(APPLICATION_NAME)_CFLAGS = -fobjc-arc
$(APPLICATION_NAME)_LDFLAGS = -e_LiveContainerMain -rpath @loader_path/Frameworks
$(APPLICATION_NAME)_FRAMEWORKS = UIKit
#$(APPLICATION_NAME)_INSTALL_PATH = /Applications/LiveContainer.app
include $(THEOS_MAKE_PATH)/application.mk

# Make the executable name longer so we have space to overwrite it with the guest app's name
before-package::
	@mv .theos/_/Applications/LiveContainer.app/LiveContainer .theos/_/Applications/LiveContainer.app/LiveContainer_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou
