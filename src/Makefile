THEOS_DEVICE_IP ?= 0.0.0.0

TARGET := iphone:clang:latest:14.0
ARCHS  := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AdSkip

AdSkip_FILES    := Tweak.x
AdSkip_CFLAGS   := -fobjc-arc
AdSkip_LDFLAGS  := -rpath /usr/lib/swift

include $(THEOS)/makefiles/tweak.mk
