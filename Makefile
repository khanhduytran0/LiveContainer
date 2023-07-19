ARCHS := arm64
TARGET := iphone:clang:latest:14.0
PACKAGE_FORMAT = ipa
INSTALL_TARGET_PROCESSES = LiveContainer
include $(THEOS)/makefiles/common.mk

# Build the UI library
LIBRARY_NAME = LiveContainerUI
$(LIBRARY_NAME)_FILES = LCAppDelegate.m LCRootViewController.m unarchive.m AppInfo.m
$(LIBRARY_NAME)_CFLAGS = -fobjc-arc
$(LIBRARY_NAME)_FRAMEWORKS = QuartzCore UIKit UniformTypeIdentifiers
$(LIBRARY_NAME)_LIBRARIES = archive
$(LIBRARY_NAME)_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks
include $(THEOS_MAKE_PATH)/library.mk

# Build the app
APPLICATION_NAME = LiveContainer
$(APPLICATION_NAME)_FILES = dyld_bypass_validation.m main.m utils.m
$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.xml
$(APPLICATION_NAME)_CFLAGS = -fobjc-arc
$(APPLICATION_NAME)_LDFLAGS = -e_LiveContainerMain -rpath @loader_path/Frameworks
$(APPLICATION_NAME)_FRAMEWORKS = UIKit
#$(APPLICATION_NAME)_INSTALL_PATH = /Applications/LiveContainer.app
include $(THEOS_MAKE_PATH)/application.mk

# Make the executable name longer so we have space to overwrite it with the guest app's name
before-package::
	@mv .theos/_/Applications/LiveContainer.app/LiveContainer .theos/_/Applications/LiveContainer.app/LiveContainer_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou
