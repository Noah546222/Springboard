#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#define PREFS_ID @"com.user.spinspringboard"
#define PREFS_NOTIFY CFSTR("com.user.spinspringboard/prefschanged")

@interface SBIconView : UIView
@property (nonatomic, copy) NSString *location;
@property (nonatomic, retain) id icon;
@end
@interface SBIconListView : UIView
@property (nonatomic, copy) NSString *iconLocation;
@end
@interface SBDockIconListView : SBIconListView @end
@interface SBDockView : UIView @end
@interface SBFolderIcon : NSObject @end

static NSString *const kAnimKey = @"ssb_spin";
static const void *kSigKey = &kSigKey;
static const void *kRandKey = &kRandKey;

static BOOL gEnabled = YES, gIcons = YES, gDockIcons = YES, gFolders = YES, gDockBG = NO, gPages = NO;
static NSInteger gDirection = 0;   // 0 = right (clockwise), 1 = left, 2 = random per item
static double gRPM = 20.0;         // rotations per minute
static NSHashTable *gViews;

static BOOL boolPref(NSUserDefaults *d, NSString *k, BOOL def) {
    id v = [d objectForKey:k];
    return v ? [v boolValue] : def;
}

static void loadPrefs(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:PREFS_ID];
    gEnabled   = boolPref(d, @"enabled", YES);
    gIcons     = boolPref(d, @"icons", YES);
    gDockIcons = boolPref(d, @"dockIcons", YES);
    gFolders   = boolPref(d, @"folders", YES);
    gDockBG    = boolPref(d, @"dockBG", NO);
    gPages     = boolPref(d, @"pages", NO);
    id dir = [d objectForKey:@"direction"];
    gDirection = dir ? [dir integerValue] : 0;
    id spd = [d objectForKey:@"speed"];
    gRPM = spd ? [spd doubleValue] : 20.0;
    if (gRPM < 0.5) gRPM = 0.5;
}

// force = rebuild the animation even if one is already running
static void ssb_apply(UIView *v, BOOL spin, BOOL force) {
    if (!v) return;
    CALayer *layer = v.layer;
    BOOL running = [layer animationForKey:kAnimKey] != nil;

    if (!spin || !gEnabled) {
        if (running) [layer removeAnimationForKey:kAnimKey];
        return;
    }
    if (running && !force) return;

    int dir;
    if (gDirection == 0) dir = 1;
    else if (gDirection == 1) dir = -1;
    else {
        NSNumber *r = objc_getAssociatedObject(v, kRandKey);
        if (!r) {
            r = @(arc4random_uniform(2) ? 1 : -1);
            objc_setAssociatedObject(v, kRandKey, r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        dir = r.intValue;
    }
    if (gDirection != 2) objc_setAssociatedObject(v, kRandKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    double dur = 60.0 / gRPM;
    NSString *sig = [NSString stringWithFormat:@"%d|%.3f", dir, dur];
    if (running && [objc_getAssociatedObject(v, kSigKey) isEqualToString:sig]) return;

    [layer removeAnimationForKey:kAnimKey];
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.fromValue = @0;
    a.toValue = @(dir * 2.0 * M_PI);
    a.duration = dur;
    a.repeatCount = HUGE_VALF;
    a.additive = YES;
    a.removedOnCompletion = NO;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:a forKey:kAnimKey];
    objc_setAssociatedObject(v, kSigKey, sig, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static BOOL ssb_iconShouldSpin(SBIconView *v) {
    NSString *loc = [v respondsToSelector:@selector(location)] ? v.location : nil;
    if ([loc containsString:@"Dock"]) return gDockIcons;
    if ([v.icon isKindOfClass:%c(SBFolderIcon)]) return gFolders;
    return gIcons;
}

static UIView *ssb_dockBG(SBDockView *dock) {
    @try { return [dock valueForKey:@"backgroundView"]; } @catch (id e) {}
    @try { return [dock valueForKey:@"_backgroundView"]; } @catch (id e) {}
    return nil;
}

static BOOL ssb_pageShouldSpin(SBIconListView *lv) {
    if ([lv isKindOfClass:%c(SBDockIconListView)]) return NO;
    NSString *loc = [lv respondsToSelector:@selector(iconLocation)] ? lv.iconLocation : nil;
    if (loc && ![loc containsString:@"Root"]) return NO;
    return gPages;
}

static void ssb_update(UIView *v, BOOL force) {
    if ([v isKindOfClass:%c(SBIconView)]) {
        ssb_apply(v, ssb_iconShouldSpin((SBIconView *)v), force);
    } else if ([v isKindOfClass:%c(SBDockView)]) {
        ssb_apply(ssb_dockBG((SBDockView *)v), gDockBG, force);
    } else if ([v isKindOfClass:%c(SBIconListView)]) {
        ssb_apply(v, ssb_pageShouldSpin((SBIconListView *)v), force);
    }
}

static void refreshAll(void) {
    loadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *v in [gViews allObjects]) ssb_update(v, YES);
    });
}

static void prefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    refreshAll();
}

%hook SBIconView
- (void)didMoveToWindow {
    %orig;
    [gViews addObject:self];
    ssb_update(self, NO);
}
- (void)layoutSubviews {
    %orig;
    ssb_update(self, NO);
}
%end

%hook SBDockView
- (void)didMoveToWindow {
    %orig;
    [gViews addObject:self];
    ssb_update(self, NO);
}
- (void)layoutSubviews {
    %orig;
    ssb_update(self, NO);
}
%end

%hook SBIconListView
- (void)didMoveToWindow {
    %orig;
    [gViews addObject:self];
    ssb_update(self, NO);
}
%end

%ctor {
    gViews = [NSHashTable weakObjectsHashTable];
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, prefsChanged,
        PREFS_NOTIFY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
