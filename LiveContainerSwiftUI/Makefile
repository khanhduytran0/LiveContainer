TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveContainerSwiftUI

LiveContainerSwiftUI_FILES = \
$(shell find ./ -name '*.swift') \
./LCSwiftBridge.m \
../LiveContainerUI/LCAppInfo.m \
../LiveContainerUI/LCUtils.m \
../LiveContainerUI/LCMachOUtils.m \
../LiveContainerUI/unarchive.m
LiveContainerSwiftUI_SWIFTFLAGS = -I../LiveContainerUI
LiveContainerSwiftUI_CFLAGS = \
  -fobjc-arc
LiveContainerSwiftUI_LIBRARIES = archive
LiveContainerSwiftUI_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks

include $(THEOS_MAKE_PATH)/framework.mk