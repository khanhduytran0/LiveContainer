export ARCHS := arm64
export TARGET := iphone:clang:16.5:14.0
PACKAGE_FORMAT = ipa
INSTALL_TARGET_PROCESSES = LiveContainer
include $(THEOS)/makefiles/common.mk

export CONFIG_TYPE = $(if $(FINALPACKAGE),release,debug)
export CONFIG_BRANCH = $(shell git branch --show-current)
export CONFIG_COMMIT = $(shell git log --oneline | sed '2,10000000d' | cut -b 1-7)

# Build the app
APPLICATION_NAME = LiveContainer

$(APPLICATION_NAME)_FILES = dyld_bypass_validation.m main.m utils.m LCSharedUtils.m NSUserDefaults.m fishhook/fishhook.c
$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.xml
$(APPLICATION_NAME)_CFLAGS = -fobjc-arc
$(APPLICATION_NAME)_LDFLAGS = -e _LiveContainerMain -rpath @loader_path/Frameworks

include $(THEOS_MAKE_PATH)/application.mk

SUBPROJECTS += ZSign TweakLoader TestJITLess LiveContainerSwiftUI AltStoreTweak
include $(THEOS_MAKE_PATH)/aggregate.mk

# Make the executable name longer so we have space to overwrite it with the guest app's name
before-package::
	@/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool compile ./LiveContainerSwiftUI/Localizable.xcstrings --output-directory $(THEOS_STAGING_DIR)/Applications/LiveContainer.app
	@/Applications/Xcode.app/Contents/Developer/usr/bin/actool LiveContainerSwiftUI/Assets.xcassets --compile $(THEOS_STAGING_DIR)/Applications/LiveContainer.app --platform iphoneos  --minimum-deployment-target 14.0
	@mv $(THEOS_STAGING_DIR)/Applications/LiveContainer.app/LiveContainer $(THEOS_STAGING_DIR)/Applications/LiveContainer.app/LiveContainer_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou

before-all::
	@sh ./download_openssl.sh
