TARGET := iphone:clang:latest:7.0
ARCHS := arm64
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = ZSign

ZSign_FILES = $(shell find . -name '*.cpp') $(shell find . -name '*.mm') zsigner.m
ZSign_CFLAGS = -fobjc-arc -Wno-deprecated -Wno-unused-variable -Wno-unused-but-set-variable -Wno-module-import-in-extern-c
ZSign_CCFLAGS = -std=c++11
ZSign_FRAMEWORKS = OpenSSL
ZSign_INSTALL_PATH = /Applications/LiveContainer.app/Frameworks

include $(THEOS_MAKE_PATH)/library.mk

