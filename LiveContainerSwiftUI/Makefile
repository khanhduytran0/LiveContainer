TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveContainerSwiftUI

LiveContainerSwiftUI_FILES = \
$(shell find . -name '*.swift') \
LCSwiftBridge.m \
LCAppInfo.m \
LCAppDelegateSwiftUI.m \
LCVersionInfo.m \
LCUtils.m \
LCMachOUtils.m \
unarchive.m
LiveContainerSwiftUI_SWIFTFLAGS = -I../LiveContainerUI
LiveContainerSwiftUI_CFLAGS = \
  -fobjc-arc \
  -DCONFIG_TYPE=\"$(CONFIG_TYPE)\" \
  -DCONFIG_BRANCH=\"$(CONFIG_BRANCH)\" \
  -DCONFIG_COMMIT=\"$(CONFIG_COMMIT)\"
LiveContainerSwiftUI_LIBRARIES = archive
LiveContainerSwiftUI_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks

include $(THEOS_MAKE_PATH)/framework.mk
