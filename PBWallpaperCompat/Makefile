ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PBWallpaperCompat
PBWallpaperCompat_FILES = Tweak.xm
PBWallpaperCompat_CFLAGS = -fobjc-arc
PBWallpaperCompat_FRAMEWORKS = UIKit Foundation
PBWallpaperCompat_PRIVATE_FRAMEWORKS = BaseBoardUI

include $(THEOS_MAKE_PATH)/tweak.mk
