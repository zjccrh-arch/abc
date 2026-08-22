#import <Foundation/Foundation.h>
#import <objc/message.h>

static BOOL forwardingLegacyURL;

static void PBWForwardLegacyURL(id receiver, id url, id application, BOOL animating,
                                id activationSettings, id origin, id result) {
    if (forwardingLegacyURL || ![url isKindOfClass:NSURL.class]) {
        return;
    }

    if (![[url scheme] isEqualToString:@"pbwallpaperimporter"]) {
        return;
    }

    SEL legacySelector = NSSelectorFromString(
        @"applicationOpenURL:withApplication:animating:activationSettings:origin:notifyLSOnFailure:withResult:"
    );
    if (![receiver respondsToSelector:legacySelector]) {
        return;
    }

    forwardingLegacyURL = YES;
    ((void (*)(id, SEL, id, id, BOOL, id, id, BOOL, id))objc_msgSend)(
        receiver, legacySelector, url, application, animating,
        activationSettings, origin, NO, result
    );
    forwardingLegacyURL = NO;
}

%hook SpringBoard

- (void)_applicationOpenURL:(NSURL *)url withApplication:(id)application animating:(BOOL)animating activationSettings:(id)activationSettings origin:(id)origin withResult:(id)result {
    %orig;
    PBWForwardLegacyURL(self, url, application, animating, activationSettings, origin, result);
}

%end
