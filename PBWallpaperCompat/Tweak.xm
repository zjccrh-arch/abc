#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <stdint.h>

static NSString *const kPreferencesDomain = @"com.charlieleung.pbwallpaperprefs";
static CFStringRef const kPreferencesChanged = CFSTR("com.charlieleung.pbwallpaperprefs-updated");
static NSInteger const kRendererTag = 0x50425716;
static NSUInteger retryCount;
static BOOL rendererStateKnown;
static BOOL rendererLocked;

static UIView *PBWWallpaperHost(void) {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"_SBWallpaperSecureWindow"] && window.subviews.count) {
            return window.subviews.firstObject;
        }
    }
    return nil;
}

static NSUserDefaults *PBWPreferences(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kPreferencesDomain];
}

static NSString *PBWActiveWallpaperPath(NSUserDefaults *preferences) {
    NSString *dataRoot = [preferences stringForKey:@"PBWDataRootPath"];
    if ([dataRoot isKindOfClass:NSString.class]) {
        NSString *marker = [dataRoot stringByAppendingPathComponent:@".pbwactive"];
        NSString *path = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil];
        path = [path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }

    NSString *path = [preferences stringForKey:@"pbWallpaperPath"];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

static BOOL PBWIsUILocked(void) {
    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    SEL lockedSelector = NSSelectorFromString(@"isUILocked");
    if (managerClass == Nil || ![managerClass respondsToSelector:sharedSelector]) {
        return NO;
    }

    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    return manager != nil && [manager respondsToSelector:lockedSelector]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(manager, lockedSelector)
        : NO;
}

static id PBWRenderer(void) {
    return [PBWWallpaperHost() viewWithTag:kRendererTag];
}

static void PBWApplyLockState(BOOL locked, BOOL force) {
    id renderer = PBWRenderer();
    SEL selector = NSSelectorFromString(@"PBWMethod011:");
    if (renderer == nil || ![renderer respondsToSelector:selector]) {
        return;
    }
    if (!force && rendererStateKnown && rendererLocked == locked) {
        return;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(renderer, selector, locked);
    rendererStateKnown = YES;
    rendererLocked = locked;
}

static void PBWApplyCoverSheetProgress(double progress) {
    id renderer = PBWRenderer();
    SEL selector = NSSelectorFromString(@"PBWMethod012:");
    if (renderer != nil && [renderer respondsToSelector:selector]) {
        ((void (*)(id, SEL, double))objc_msgSend)(renderer, selector, progress);
    }
}

static void PBWRemoveRenderer(void) {
    [PBWRenderer() removeFromSuperview];
    rendererStateKnown = NO;
}

static void PBWInstallRenderer(void) {
    NSUserDefaults *preferences = PBWPreferences();
    if (![preferences boolForKey:@"PBWallpaperEnabled"]) {
        PBWRemoveRenderer();
        return;
    }

    NSString *wallpaperPath = PBWActiveWallpaperPath(preferences);
    UIView *host = PBWWallpaperHost();
    Class rendererClass = NSClassFromString(@"hpebutktbedt");
    SEL loader = NSSelectorFromString(@"PBWMethod009:PBWMethod010:");
    if (wallpaperPath == nil || host == nil || rendererClass == Nil) {
        if (retryCount++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                PBWInstallRenderer();
            });
        }
        return;
    }

    retryCount = 0;
    PBWRemoveRenderer();

    UIView *renderer = [[rendererClass alloc] initWithFrame:host.bounds];
    if (renderer == nil || ![renderer respondsToSelector:loader]) {
        return;
    }

    renderer.tag = kRendererTag;
    renderer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    renderer.userInteractionEnabled = NO;
    renderer.clipsToBounds = YES;
    [host addSubview:renderer];

    // PBWMethod010 is the native loader's numeric presentation mode. Passing
    // the manifest dictionary here prevents the original model builder from
    // running on arm64e. Mode 0 is the importer/original default path.
    ((void (*)(id, SEL, id, uint64_t))objc_msgSend)(renderer, loader, wallpaperPath, 0);
    PBWApplyLockState(PBWIsUILocked(), YES);

    // The internal loader has no public failure result. Do not leave its empty
    // video fallback over SpringBoard when the native model was not created.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        SEL modelSelector = NSSelectorFromString(@"PBWProperty040");
        if ([renderer respondsToSelector:modelSelector] &&
            ((id (*)(id, SEL))objc_msgSend)(renderer, modelSelector) == nil) {
            [renderer removeFromSuperview];
        }
    });
}

static void PBWPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        retryCount = 0;
        PBWInstallRenderer();
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PBWPreferencesChanged, kPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{
        PBWInstallRenderer();
    });
}

%hook SBLockScreenManager

- (void)_reallySetUILocked:(BOOL)locked {
    %orig;
    PBWApplyLockState(locked, NO);
}

%end

%hook SBCoverSheetPresentationManager

- (void)coverSheetSlidingViewController:(id)controller animationTickedWithProgress:(double)progress velocity:(double)velocity coverSheetFrame:(CGRect)frame gestureActive:(BOOL)gestureActive forPresentationValue:(BOOL)presentationValue {
    %orig;
    PBWApplyCoverSheetProgress(progress);
}

%end
