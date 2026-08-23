#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static CGSize PBWFullscreenSizeThatFits(id receiver, SEL selector, CGSize size) {
    CGSize bounds = ((UIView *)receiver).bounds.size;
    return bounds.width > 0.0 && bounds.height > 0.0 ? bounds : size;
}

static void PBWFullscreenLayoutSubviews(id receiver, SEL selector) {
    struct objc_super superInfo = { receiver, class_getSuperclass(object_getClass(receiver)) };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superInfo, selector);
    UIView *view = (UIView *)receiver;
    CALayer *content = view.layer.sublayers.firstObject;
    if (content != nil) content.frame = view.bounds;
}

static Class PBWFullscreenPackageViewClass(void) {
    static Class packageViewClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class parent = NSClassFromString(@"BSUICAPackageView");
        if (parent == Nil) return;
        packageViewClass = objc_getClass("PBWFullscreenPackageView");
        if (packageViewClass != Nil) return;
        packageViewClass = objc_allocateClassPair(parent, "PBWFullscreenPackageView", 0);
        if (packageViewClass == Nil) return;
        class_addMethod(packageViewClass, @selector(sizeThatFits:), (IMP)PBWFullscreenSizeThatFits, "{CGSize=dd}@:{CGSize=dd}");
        class_addMethod(packageViewClass, @selector(layoutSubviews), (IMP)PBWFullscreenLayoutSubviews, "v@:");
        objc_registerClassPair(packageViewClass);
    });
    return packageViewClass;
}

static NSString *const kPreferencesDomain = @"com.charlieleung.pbwallpaperprefs";static CFStringRef const kPreferencesChanged = CFSTR("com.charlieleung.pbwallpaperprefs-updated");static NSInteger const kSecureContainerTag = 0x50425716;static NSInteger const kCoverSheetContainerTag = 0x50425717;static NSUInteger retryCount;static NSUInteger coverSheetRetryCount;static NSInteger lastCoverSheetEndpoint = -1;static BOOL lastAppliedStateKnown;static BOOL lastAppliedLocked;static char kStateMappingAssociationKey;static char kStateModelAssociationKey;
static void PBWInstallPackages(void);static void PBWInstallCoverSheetRenderer(void);@interface PBWStateModel : NSObject <NSXMLParserDelegate>@property(nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *layerPaths;@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *> *states;@property(nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *layerStack;@property(nonatomic, strong) NSMutableArray<NSNumber *> *childCounts;@property(nonatomic, copy) NSString *currentState;@property(nonatomic, copy) NSString *currentTarget;@property(nonatomic, copy) NSString *currentKeyPath;@end@implementation PBWStateModel- (instancetype)init {    self = [super init];    if (self) {        _layerPaths = [NSMutableDictionary dictionary];        _states = [NSMutableDictionary dictionary];        _layerStack = [NSMutableArray array];        _childCounts = [NSMutableArray array];    }    return self;}- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary<NSString *, NSString *> *)attributes {    if ([elementName isEqualToString:@"CALayer"]) {        NSArray<NSNumber *> *path = nil;        if (self.layerStack.count == 0) {            path = @[];        } else {            NSUInteger childIndex = self.childCounts.lastObject.unsignedIntegerValue;            self.childCounts[self.childCounts.count - 1] = @(childIndex + 1);            path = [self.layerStack.lastObject arrayByAddingObject:@(childIndex)];        }        [self.layerStack addObject:path];        [self.childCounts addObject:@0];        NSString *identifier = attributes[@"id"];        if (identifier.length) {            self.layerPaths[identifier] = path;        }        return;    }    if ([elementName isEqualToString:@"LKState"]) {        self.currentState = attributes[@"name"];        return;    }    if ([elementName isEqualToString:@"LKStateSetValue"]) {        self.currentTarget = attributes[@"targetId"];        self.currentKeyPath = attributes[@"keyPath"];        return;    }    if ([elementName isEqualToString:@"value"] && self.currentState.length && self.currentTarget.length && self.currentKeyPath.length) {        NSString *rawValue = attributes[@"value"];        if (rawValue.length) {            NSMutableDictionary *state = self.states[self.currentState];            if (state == nil) {                state = [NSMutableDictionary dictionary];                self.states[self.currentState] = state;            }            NSMutableDictionary *target = state[self.currentTarget];            if (target == nil) {                target = [NSMutableDictionary dictionary];                state[self.currentTarget] = target;            }            target[self.currentKeyPath] = @([rawValue doubleValue]);        }    }}- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName {    if ([elementName isEqualToString:@"CALayer"]) {        [self.layerStack removeLastObject];        [self.childCounts removeLastObject];    } else if ([elementName isEqualToString:@"LKStateSetValue"]) {        self.currentTarget = nil;        self.currentKeyPath = nil;    } else if ([elementName isEqualToString:@"LKState"]) {        self.currentState = nil;    }}@end
static UIView *PBWWallpaperHost(void) {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (![NSStringFromClass(window.class) isEqualToString:@"_SBWallpaperSecureWindow"] || !window.subviews.count) {
            continue;
        }
        UIView *root = window.subviews.firstObject;
        // The CoverSheet portal snapshots this first child, not root's sibling overlays.
        return root.subviews.count ? root.subviews.firstObject : root;
    }
    return nil;
}static UIView *PBWCoverSheetHost(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"SBCoverSheetWindow"]) {
            [stack addObject:window];
        }
    }
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if ([NSStringFromClass(view.class) isEqualToString:@"SBCoverSheetPanelBackgroundContainerView"]) {
            return view;
        }
        [stack addObjectsFromArray:view.subviews];
    }
    return nil;
}
static NSArray<UIView *> *PBWRendererContainers(void) {
    NSMutableArray<UIView *> *containers = [NSMutableArray array];
    UIView *secureContainer = [PBWWallpaperHost() viewWithTag:kSecureContainerTag];
    UIView *coverSheetContainer = [PBWCoverSheetHost() viewWithTag:kCoverSheetContainerTag];
    if (secureContainer != nil) [containers addObject:secureContainer];
    if (coverSheetContainer != nil) [containers addObject:coverSheetContainer];
    return containers;
}
static BOOL PBWIsUILocked(void) {    Class managerClass = NSClassFromString(@"SBLockScreenManager");    SEL sharedInstance = NSSelectorFromString(@"sharedInstance");    SEL isUILocked = NSSelectorFromString(@"isUILocked");    if (managerClass == Nil || ![managerClass respondsToSelector:sharedInstance]) {        return NO;    }    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedInstance);    if (manager == nil || ![manager respondsToSelector:isUILocked]) {        return NO;    }    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, isUILocked);}static NSDictionary<NSString *, NSString *> *PBWStateMappingForPackage(NSString *packagePath) {    NSString *documentPath = [packagePath stringByAppendingPathComponent:@"main.caml"];    NSString *document = [NSString stringWithContentsOfFile:documentPath encoding:NSUTF8StringEncoding error:nil];    if ([document containsString:@"<LKState name=\"Locked\""] && [document containsString:@"<LKState name=\"Unlock\""]) {        return @{ @"locked": @"Locked", @"home": @"Unlock" };    }    return @{ @"locked": @"Lock PortraitUp", @"home": @"Home PortraitUp" };}static void PBWApplyState(BOOL locked, BOOL animated, BOOL force) {
    NSArray<UIView *> *containers = PBWRendererContainers();
    if (!containers.count) return;
    if (!force && lastAppliedStateKnown && lastAppliedLocked == locked) return;
    SEL setState = NSSelectorFromString(@"setState:animated:");
    for (UIView *container in containers) {
        for (UIView *packageView in container.subviews) {
            if (![packageView respondsToSelector:setState]) continue;
            NSDictionary<NSString *, NSString *> *mapping = objc_getAssociatedObject(packageView, &kStateMappingAssociationKey);
            NSString *state = mapping[locked ? @"locked" : @"home"];
            if (state != nil) ((void (*)(id, SEL, NSString *, BOOL))objc_msgSend)(packageView, setState, state, animated);
        }
    }
    lastAppliedStateKnown = YES;
    lastAppliedLocked = locked;
}static PBWStateModel *PBWStateModelForPackage(NSString *packagePath) {    NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[packagePath stringByAppendingPathComponent:@"main.caml"]]];    if (parser == nil) {        return nil;    }    PBWStateModel *model = [PBWStateModel new];    parser.delegate = model;    return [parser parse] ? model : nil;}static CALayer *PBWLayerAtPath(CALayer *packageLayer, NSArray<NSNumber *> *path) {    CALayer *layer = packageLayer.sublayers.firstObject;    for (NSNumber *component in path) {        NSArray<CALayer *> *children = layer.sublayers;        NSUInteger index = component.unsignedIntegerValue;        if (index >= children.count) {            return nil;        }        layer = children[index];    }    return layer;}static void PBWApplyHomeFraction(double fraction) {
    fraction = MAX(0.0, MIN(1.0, fraction));
    NSArray<UIView *> *containers = PBWRendererContainers();
    if (!containers.count) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIView *container in containers) {
        for (UIView *packageView in container.subviews) {
            PBWStateModel *model = objc_getAssociatedObject(packageView, &kStateModelAssociationKey);
            NSDictionary<NSString *, NSString *> *mapping = objc_getAssociatedObject(packageView, &kStateMappingAssociationKey);
            NSDictionary *locked = model.states[mapping[@"locked"]];
            NSDictionary *unlocked = model.states[mapping[@"home"]];
            if (!locked.count || !unlocked.count) continue;
            for (NSString *identifier in locked) {
                NSDictionary<NSString *, NSNumber *> *fromValues = locked[identifier];
                NSDictionary<NSString *, NSNumber *> *toValues = unlocked[identifier];
                CALayer *layer = PBWLayerAtPath(packageView.layer, model.layerPaths[identifier]);
                if (layer == nil || toValues == nil) continue;
                for (NSString *keyPath in fromValues) {
                    NSNumber *to = toValues[keyPath];
                    if (to == nil) continue;
                    double value = fromValues[keyPath].doubleValue + (to.doubleValue - fromValues[keyPath].doubleValue) * fraction;
                    @try { [layer setValue:@(value) forKeyPath:keyPath]; } @catch (NSException *exception) { }
                }
            }
        }
    }
    [CATransaction commit];
}static void PBWApplyCoverSheetProgressOnMain(double progress) {
    UIView *coverSheetHost = PBWCoverSheetHost();
    if (coverSheetHost != nil && [coverSheetHost viewWithTag:kCoverSheetContainerTag] == nil) PBWInstallCoverSheetRenderer();
    PBWApplyHomeFraction(progress);
    NSInteger endpoint = progress <= 0.001 ? 1 : (progress >= 0.999 ? 0 : -1);
    if (endpoint < 0) {
        lastCoverSheetEndpoint = -1;
        return;
    }
    if (lastCoverSheetEndpoint == endpoint) return;
    lastCoverSheetEndpoint = endpoint;
    PBWApplyState(endpoint == 1, NO, YES);
}static void PBWApplyCoverSheetProgress(double progress) {
    dispatch_async(dispatch_get_main_queue(), ^{
        PBWApplyCoverSheetProgressOnMain(progress);
    });
}static NSDictionary *PBWDefaultAssets(NSDictionary *wallpaper) {    NSDictionary *assets = wallpaper[@"assets"];    NSDictionary *lockAndHome = assets[@"lockAndHome"];    NSDictionary *defaults = lockAndHome[@"default"];    return [defaults isKindOfClass:NSDictionary.class] ? defaults : nil;}static UIView *PBWPackageView(NSURL *url) {    Class packageViewClass = PBWFullscreenPackageViewClass();    if (packageViewClass == Nil) {        return nil;    }    id instance = [packageViewClass alloc];    SEL initializer = NSSelectorFromString(@"initWithURL:");    return [instance respondsToSelector:initializer] ? ((id (*)(id, SEL, NSURL *))objc_msgSend)(instance, initializer, url) : nil;}static UIView *PBWCreateRendererContainer(UIView *host, NSInteger tag, NSString *wallpaperPath, NSDictionary *assets, BOOL coverSheet) {
    [[host viewWithTag:tag] removeFromSuperview];
    UIView *container = [[UIView alloc] initWithFrame:host.bounds];
    container.tag = tag;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.userInteractionEnabled = NO;
    container.clipsToBounds = YES;
    NSArray<NSString *> *keys = @[@"backgroundAnimationFileName", @"foregroundAnimationFileName", @"floatingAnimationFileNameKey"];
    for (NSString *key in keys) {
        NSString *filename = assets[key];
        if (![filename isKindOfClass:NSString.class]) continue;
        NSString *packagePath = [wallpaperPath stringByAppendingPathComponent:filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:packagePath]) continue;
        UIView *packageView = PBWPackageView([NSURL fileURLWithPath:packagePath]);
        if (packageView == nil) continue;
        packageView.frame = container.bounds;
        packageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        packageView.userInteractionEnabled = NO;
        objc_setAssociatedObject(packageView, &kStateMappingAssociationKey, PBWStateMappingForPackage(packagePath), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(packageView, &kStateModelAssociationKey, PBWStateModelForPackage(packagePath), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [container addSubview:packageView];
    }
    if (!container.subviews.count) return nil;
    BOOL locked = PBWIsUILocked();
    SEL setState = NSSelectorFromString(@"setState:animated:");
    for (UIView *packageView in container.subviews) {
        if (![packageView respondsToSelector:setState]) continue;
        NSDictionary<NSString *, NSString *> *mapping = objc_getAssociatedObject(packageView, &kStateMappingAssociationKey);
        NSString *state = mapping[locked ? @"locked" : @"home"];
        if (state != nil) ((void (*)(id, SEL, NSString *, BOOL))objc_msgSend)(packageView, setState, state, NO);
    }
    if (coverSheet) [host insertSubview:container atIndex:MIN((NSUInteger)1, host.subviews.count)];
    else [host addSubview:container];
    return container;
}
static NSUserDefaults *PBWPreferences(void) {    return [[NSUserDefaults alloc] initWithSuiteName:kPreferencesDomain];}static NSString *PBWActiveWallpaperPath(NSUserDefaults *preferences) {    NSString *dataRoot = [preferences stringForKey:@"PBWDataRootPath"];    if ([dataRoot isKindOfClass:NSString.class]) {        NSString *markerPath = [dataRoot stringByAppendingPathComponent:@".pbwactive"];        NSError *error = nil;        NSString *activePath = [NSString stringWithContentsOfFile:markerPath encoding:NSUTF8StringEncoding error:&error];        activePath = [activePath stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];        if (activePath.length && [[NSFileManager defaultManager] fileExistsAtPath:activePath]) {            return activePath;        }    }    NSString *selectedPath = [preferences stringForKey:@"pbWallpaperPath"];    return [[NSFileManager defaultManager] fileExistsAtPath:selectedPath] ? selectedPath : nil;}static void PBWInstallCoverSheetRenderer(void) {
    NSUserDefaults *preferences = PBWPreferences();
    if (![preferences boolForKey:@"PBWallpaperEnabled"]) return;
    UIView *coverSheetHost = PBWCoverSheetHost();
    if (coverSheetHost == nil) {
        if (coverSheetRetryCount++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{ PBWInstallCoverSheetRenderer(); });
        }
        return;
    }
    coverSheetRetryCount = 0;
    if ([coverSheetHost viewWithTag:kCoverSheetContainerTag] != nil) return;
    NSString *wallpaperPath = PBWActiveWallpaperPath(preferences);
    if (wallpaperPath == nil) return;
    NSDictionary *wallpaper = [NSDictionary dictionaryWithContentsOfFile:[wallpaperPath stringByAppendingPathComponent:@"Wallpaper.plist"]];
    NSDictionary *assets = PBWDefaultAssets(wallpaper);
    if (assets != nil) PBWCreateRendererContainer(coverSheetHost, kCoverSheetContainerTag, wallpaperPath, assets, YES);
}
static void PBWRemoveContainer(void) {
    [[PBWWallpaperHost() viewWithTag:kSecureContainerTag] removeFromSuperview];
    [[PBWCoverSheetHost() viewWithTag:kCoverSheetContainerTag] removeFromSuperview];
    retryCount = 0;
    coverSheetRetryCount = 0;
    lastCoverSheetEndpoint = -1;
    lastAppliedStateKnown = NO;
}static void PBWInstallPackages(void) {
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
    UIView *secureHost = PBWWallpaperHost();
    if (assets == nil || secureHost == nil) {
        if (retryCount++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{ PBWInstallPackages(); });
        }
        return;
    }
    retryCount = 0;
    lastCoverSheetEndpoint = -1;
    PBWCreateRendererContainer(secureHost, kSecureContainerTag, wallpaperPath, assets, NO);
    [[PBWCoverSheetHost() viewWithTag:kCoverSheetContainerTag] removeFromSuperview];
    PBWInstallCoverSheetRenderer();
    lastAppliedStateKnown = YES;
    lastAppliedLocked = PBWIsUILocked();
}static void PBWPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {    dispatch_async(dispatch_get_main_queue(), ^{        retryCount = 0;        PBWInstallPackages();    });}
%ctor {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PBWPreferencesChanged, kPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{
        PBWInstallPackages();
    });
}

%hook SBLockScreenManager
- (void)lockScreenViewControllerWillPresent {
    PBWInstallCoverSheetRenderer();
    PBWApplyState(YES, YES, NO);
    %orig;
}
- (void)lockScreenViewControllerWillDismiss {
    PBWApplyState(NO, YES, NO);
    %orig;
}
- (void)_reallySetUILocked:(BOOL)locked {
    PBWApplyState(locked, YES, NO);
    %orig;
}
%end

%hook SBCoverSheetPresentationManager
- (void)coverSheetSlidingViewController:(id)controller animationTickedWithProgress:(double)progress velocity:(double)velocity coverSheetFrame:(CGRect)frame gestureActive:(BOOL)gestureActive forPresentationValue:(BOOL)presentationValue {
    %orig;
    PBWApplyCoverSheetProgress(progress);
}
%end
