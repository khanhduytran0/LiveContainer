TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveContainerSwiftUI

LiveContainerSwiftUI_FILES = \
$(shell find ./ -name '*.swift') \
./LCSwiftBridge.m \
../LiveContainerUI/LCAppInfo.m \
../LiveContainerUI/LCUtils.m \
../LiveContainerUI/LCMachOUtils.m
LiveContainerSwiftUI_SWIFTFLAGS = -I../LiveContainerUI/
LiveContainerSwiftUI_CFLAGS = \
  -fobjc-arc
LiveContainerSwiftUI_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks

include $(THEOS_MAKE_PATH)/framework.mk

all::
	@/Applications/Xcode.app/Contents/Developer/usr/bin/actool Assets.xcassets --compile ../Resources --platform iphoneos  --minimum-deployment-target 14.0
