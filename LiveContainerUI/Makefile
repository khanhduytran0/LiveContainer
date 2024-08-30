include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = LiveContainerUI

LiveContainerUI_FILES = LCAppDelegate.m LCJITLessSetupViewController.m LCMachOUtils.m LCAppListViewController.m LCSettingsListController.m LCTabBarController.m LCTweakListViewController.m LCUtils.m MBRoundProgressView.m UIViewController+LCAlert.m unarchive.m LCAppInfo.m LCWebView.m
LiveContainerUI_CFLAGS = \
  -fobjc-arc \
  -DCONFIG_TYPE=\"$(CONFIG_TYPE)\" \
  -DCONFIG_BRANCH=\"$(CONFIG_BRANCH)\" \
  -DCONFIG_COMMIT=\"$(CONFIG_COMMIT)\"
LiveContainerUI_FRAMEWORKS = CoreGraphics QuartzCore UIKit UniformTypeIdentifiers
LiveContainerUI_PRIVATE_FRAMEWORKS = Preferences
LiveContainerUI_LIBRARIES = archive
LiveContainerUI_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks

include $(THEOS_MAKE_PATH)/framework.mk
