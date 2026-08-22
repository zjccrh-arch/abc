#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString *const kPreferencesDomain = @"com.charlieleung.pbwallpaperprefs";
static CFStringRef const kPreferencesChanged = CFSTR("com.charlieleung.pbwallpaperprefs-updated");
static NSInteger const kRendererTag = 0x50425720;
static NSUInteger retryCount;

static UIView *PBWLegacyWallpaperHost(void) {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"_SBWallpaperSecureWindow"] && window.subviews.count) {
            return window.subviews.firstObject;
        }
    }
    return nil;
}

static NSString *PBWActiveWallpaperPath(void) {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kPreferencesDomain];
    NSString *dataRoot = [preferences stringForKey:@"PBWDataRootPath"];
    if ([dataRoot isKindOfClass:NSString.class]) {
        NSString *marker = [dataRoot stringByAppendingPathComponent:@".pbwactive"];
        NSString *path = [[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (path.length && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }

    NSString *path = [preferences stringForKey:@"pbWallpaperPath"];
    return [[NSFileManager defaultManager] fileExistsAtPath:path] ? path : nil;
}

static BOOL PBWEnabled(void) {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kPreferencesDomain];
    return [preferences boolForKey:@"PBWallpaperEnabled"];
}

static void PBWRemoveRenderer(void) {
    [[PBWLegacyWallpaperHost() viewWithTag:kRendererTag] removeFromSuperview];
}

static void PBWInstallNativeRenderer(void) {
    if (!PBWEnabled()) {
        PBWRemoveRenderer();
        return;
    }

    UIView *host = PBWLegacyWallpaperHost();
    NSString *wallpaperPath = PBWActiveWallpaperPath();
    Class rendererClass = NSClassFromString(@"hpebutktbedt");
    SEL setup = NSSelectorFromString(@"PBWMethod015:");
    SEL setActive = NSSelectorFromString(@"PBWBgSetActive:");
    if (host == nil || wallpaperPath == nil || rendererClass == Nil) {
        if (retryCount++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                PBWInstallNativeRenderer();
            });
        }
        return;
    }

    retryCount = 0;
    [[host viewWithTag:kRendererTag] removeFromSuperview];

    UIView *renderer = [[rendererClass alloc] initWithFrame:host.bounds];
    if (renderer == nil || ![renderer respondsToSelector:setup]) {
        return;
    }

    renderer.tag = kRendererTag;
    renderer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    renderer.userInteractionEnabled = NO;
    renderer.clipsToBounds = YES;
    [host addSubview:renderer];
    ((void (*)(id, SEL, NSString *))objc_msgSend)(renderer, setup, wallpaperPath);
    if ([renderer respondsToSelector:setActive]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(renderer, setActive, YES);
    }
}

static void PBWPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        retryCount = 0;
        PBWInstallNativeRenderer();
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PBWPreferencesChanged, kPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{
        PBWInstallNativeRenderer();
    });
}
