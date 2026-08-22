ARCHS = arm64e
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_ARCH = iphoneos-arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AAAPBWallpaperHookProbe
AAAPBWallpaperHookProbe_FILES = Tweak.xm
AAAPBWallpaperHookProbe_CFLAGS = -fobjc-arc
AAAPBWallpaperHookProbe_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
