TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MyTweak

MyTweak_FILES = Tweak.x
MyTweak_CFLAGS = -fobjc-arc
MyTweak_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
