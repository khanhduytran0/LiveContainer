ARCHS := arm64
TARGET := iphone:clang:16.5:14.0
PACKAGE_FORMAT = ipa
INSTALL_TARGET_PROCESSES = LiveContainer
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = TweakLoader

TweakLoader_FILES = TweakLoader.m UIKit+GuestHooks.m utils.m DocumentPicker.m FBSSerialQueue.m ../Localization.m
TweakLoader_CFLAGS = -objc-arc
TweakLoader_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks
TweakLoader_PRIVATE_FRAMEWORKS = CoreServices FrontBoard RunningBoardServices

include $(THEOS_MAKE_PATH)/library.mk
