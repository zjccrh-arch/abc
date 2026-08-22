#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString *const kPreferencesDomain = @"com.charlieleung.pbwallpaperprefs";
static CFStringRef const kPreferencesChanged = CFSTR("com.charlieleung.pbwallpaperprefs-updated");
static NSInteger const kContainerTag = 0x50425716;
static NSUInteger retryCount;

static UIView *PBWWallpaperHost(void) {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"_SBWallpaperSecureWindow"] && window.subviews.count) {
            return window.subviews.firstObject;
        }
    }
    return nil;
}

static BOOL PBWIsUILocked(void) {
    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    SEL sharedInstance = NSSelectorFromString(@"sharedInstance");
    SEL isUILocked = NSSelectorFromString(@"isUILocked");
    if (managerClass == Nil || ![managerClass respondsToSelector:sharedInstance]) {
        return NO;
    }

    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedInstance);
    if (manager == nil || ![manager respondsToSelector:isUILocked]) {
        return NO;
    }
    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, isUILocked);
}

static void PBWApplyState(BOOL locked, BOOL animated) {
    UIView *container = [PBWWallpaperHost() viewWithTag:kContainerTag];
    SEL setState = NSSelectorFromString(@"setState:animated:");
    NSString *state = locked ? @"Lock PortraitUp" : @"Home PortraitUp";
    for (UIView *packageView in container.subviews) {
        if ([packageView respondsToSelector:setState]) {
            ((void (*)(id, SEL, NSString *, BOOL))objc_msgSend)(packageView, setState, state, animated);
        }
    }
}

static NSDictionary *PBWDefaultAssets(NSDictionary *wallpaper) {
    NSDictionary *assets = wallpaper[@"assets"];
    NSDictionary *lockAndHome = assets[@"lockAndHome"];
    NSDictionary *defaults = lockAndHome[@"default"];
    return [defaults isKindOfClass:NSDictionary.class] ? defaults : nil;
}

static UIView *PBWPackageView(NSURL *url) {
    Class packageViewClass = NSClassFromString(@"BSUICAPackageView");
    if (packageViewClass == Nil) {
        return nil;
    }

    id instance = [packageViewClass alloc];
    SEL initializer = NSSelectorFromString(@"initWithURL:");
    if (![instance respondsToSelector:initializer]) {
        return nil;
    }
    return ((id (*)(id, SEL, NSURL *))objc_msgSend)(instance, initializer, url);
}

static NSUserDefaults *PBWPreferences(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kPreferencesDomain];
}

static NSString *PBWActiveWallpaperPath(NSUserDefaults *preferences) {
    NSString *dataRoot = [preferences stringForKey:@"PBWDataRootPath"];
    if ([dataRoot isKindOfClass:NSString.class]) {
        NSString *markerPath = [dataRoot stringByAppendingPathComponent:@".pbwactive"];
        NSError *error = nil;
        NSString *activePath = [NSString stringWithContentsOfFile:markerPath encoding:NSUTF8StringEncoding error:&error];
        activePath = [activePath stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (activePath.length && [[NSFileManager defaultManager] fileExistsAtPath:activePath]) {
            return activePath;
        }
    }

    NSString *selectedPath = [preferences stringForKey:@"pbWallpaperPath"];
    return [[NSFileManager defaultManager] fileExistsAtPath:selectedPath] ? selectedPath : nil;
}

static void PBWRemoveContainer(void) {
    UIView *host = PBWWallpaperHost();
    [[host viewWithTag:kContainerTag] removeFromSuperview];
}

static void PBWInstallPackages(void) {
    NSUserDefaults *preferences = PBWPreferences();
    if (![preferences boolForKey:@"PBWallpaperEnabled"]) {
        PBWRemoveContainer();
        return;
    }

    NSString *wallpaperPath = PBWActiveWallpaperPath(preferences);
    if (wallpaperPath == nil) {
        PBWRemoveContainer();
        return;
    }

    NSDictionary *wallpaper = [NSDictionary dictionaryWithContentsOfFile:[wallpaperPath stringByAppendingPathComponent:@"Wallpaper.plist"]];
    NSDictionary *assets = PBWDefaultAssets(wallpaper);
    UIView *host = PBWWallpaperHost();
    if (assets == nil || host == nil) {
        if (retryCount++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                PBWInstallPackages();
            });
        }
        return;
    }

    retryCount = 0;
    [[host viewWithTag:kContainerTag] removeFromSuperview];

    UIView *container = [[UIView alloc] initWithFrame:host.bounds];
    container.tag = kContainerTag;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.userInteractionEnabled = NO;
    container.clipsToBounds = YES;

    NSArray<NSString *> *keys = @[
        @"backgroundAnimationFileName",
        @"foregroundAnimationFileName",
        @"floatingAnimationFileNameKey"
    ];
    for (NSString *key in keys) {
        NSString *filename = assets[key];
        if (![filename isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *packagePath = [wallpaperPath stringByAppendingPathComponent:filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:packagePath]) {
            continue;
        }
        UIView *packageView = PBWPackageView([NSURL fileURLWithPath:packagePath]);
        if (packageView == nil) {
            continue;
        }
        packageView.frame = container.bounds;
        packageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        packageView.userInteractionEnabled = NO;
        [container addSubview:packageView];
    }

    if (container.subviews.count) {
        [host addSubview:container];
        PBWApplyState(PBWIsUILocked(), NO);
    }
}

static void PBWPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        retryCount = 0;
        PBWInstallPackages();
    });
}

%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PBWPreferencesChanged, kPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{
        PBWInstallPackages();
    });
}

%hook SBLockScreenManager

- (void)_reallySetUILocked:(BOOL)locked {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        PBWApplyState(locked, YES);
    });
}

%end
