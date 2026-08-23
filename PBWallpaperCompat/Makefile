ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_ARCH = iphoneos-arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PBWallpaperCompat
PBWallpaperCompat_FILES = Tweak.xm TweakTransitionFix.xm
PBWallpaperCompat_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
PBWallpaperCompat_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
