TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Azar

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AzarMagicButton

AzarMagicButton_FILES = Tweak.x
AzarMagicButton_CFLAGS = -fobjc-arc
AzarMagicButton_FRAMEWORKS = UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk