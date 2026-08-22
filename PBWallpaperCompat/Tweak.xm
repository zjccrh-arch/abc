#import <Foundation/Foundation.h>
#import <objc/message.h>

static BOOL PBWIsImporterURL(NSURL *url) {
    return [url isKindOfClass:NSURL.class] &&
        [url.scheme caseInsensitiveCompare:@"pbwallpaperimporter"] == NSOrderedSame;
}

static void PBWForwardModernURLToLegacyHandler(
    id target,
    NSURL *url,
    id application,
    BOOL animated,
    id activationSettings,
    id origin,
    id result
) {
    SEL legacy = NSSelectorFromString(@"applicationOpenURL:withApplication:animating:activationSettings:origin:notifyLSOnFailure:withResult:");
    if (![target respondsToSelector:legacy]) return;

    typedef void (*LegacyHandler)(id, SEL, NSURL *, id, BOOL, id, id, BOOL, id);
    ((LegacyHandler)objc_msgSend)(
        target,
        legacy,
        url,
        application,
        animated,
        activationSettings,
        origin,
        NO,
        result
    );
}

%hook SpringBoard

- (void)_applicationOpenURL:(NSURL *)url
            withApplication:(id)application
                   animating:(BOOL)animated
          activationSettings:(id)activationSettings
                      origin:(id)origin
                  withResult:(id)result {
    if (PBWIsImporterURL(url)) {
        PBWForwardModernURLToLegacyHandler(self, url, application, animated, activationSettings, origin, result);
        return;
    }
    %orig;
}

%end
