#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSInteger const PBWContainerTag = 0x50425716;

static UIView *PBWTransitionHost(void) {
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"_SBWallpaperSecureWindow"] && window.subviews.count) {
            return window.subviews.firstObject;
        }
    }
    return nil;
}

static void PBWSetTerminalState(BOOL unlocked) {
    UIView *container = [PBWTransitionHost() viewWithTag:PBWContainerTag];
    SEL selector = NSSelectorFromString(@"setState:animated:");
    for (UIView *view in container.subviews) {
        if ([view respondsToSelector:selector]) {
            ((void (*)(id, SEL, NSString *, BOOL))objc_msgSend)(view, selector,
                unlocked ? @"Unlock" : @"Locked", NO);
        }
    }
}

%hook SBCoverSheetPresentationManager

- (void)coverSheetSlidingViewController:(id)controller
              animationTickedWithProgress:(double)progress
                                 velocity:(double)velocity
                          coverSheetFrame:(CGRect)frame
                            gestureActive:(BOOL)gestureActive
                     forPresentationValue:(BOOL)presentationValue {
    %orig;
    if (!gestureActive && presentationValue && (progress <= 0.001 || progress >= 0.999)) {
        PBWSetTerminalState(progress >= 0.999);
    }
}

%end
