TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES =

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AudioHUD

AudioHUD_FILES = Tweak.m
AudioHUD_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AudioHUD_FRAMEWORKS = UIKit AVFoundation

include $(THEOS)/makefiles/tweak.mk
