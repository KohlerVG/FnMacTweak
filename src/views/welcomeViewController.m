// =============================================================================
//  welcomeViewController.m — FnMacTweak
//  First-launch welcome / onboarding screen.
//
//  This screen is shown once when the user first installs (or updates to a new
//  version). It provides a brief overview of the tweak's controls and a
//  "Continue" button that opens the settings panel on the Quick Start tab.
//
//  Persistence: the current version string is saved under kWelcomeSeenVersion
//  in NSUserDefaults. showWelcomePopupIfNeeded() (globals.m) compares it to the
//  running version and only shows this VC when they differ.
//
//  CONTRIBUTING: To update the welcome content, edit the label/button setup in
//  -viewDidLoad. If you need a new version of the screen after an update, bump
//  the version string passed to showWelcomePopupIfNeeded().
// =============================================================================

#import "./welcomeViewController.h"
#import "../globals.h"
#import <objc/runtime.h>

#define kWelcomeSeenVersion @"fnmactweak.welcomeSeenVersion"

// ─────────────────────────────────────────────────────────────────
//  welcomeViewController — single Welcome screen, no tabs
// ─────────────────────────────────────────────────────────────────
@implementation welcomeViewController

// Never lock the pointer to the welcome window.
- (BOOL)prefersPointerLocked { return NO; }

- (void)viewDidLoad {
    [super viewDidLoad];

    // ── Background ───────────────────────────────────────────────
    self.view.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.view.layer.cornerRadius = 12;
    self.view.layer.borderWidth = 0.5;
    self.view.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
    self.view.layer.masksToBounds = YES;

    CGFloat w = 320.0;  // Must match the container width set in showWelcomePopupIfNeeded
    CGFloat pad = 20.0;
    CGFloat contentW = w - pad * 2;
    CGFloat y = 0;

    // ── Title bar ────────────────────────────────────────────────
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 44)];
    titleBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.15];
    [self.view addSubview:titleBar];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, w, 44)];
    titleLabel.text = @"Welcome to FnMacTweak";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleBar addSubview:titleLabel];

    // Version pill — same style as P settings pane pill
    CGFloat pillW = 44.0;
    CGFloat pillH = 16.0;
    CGFloat pillX = w - 12.0 - pillW;
    CGFloat pillY = (44.0 - pillH) / 2.0;
    UIView *versionPill = [[UIView alloc] initWithFrame:CGRectMake(pillX, pillY, pillW, pillH)];
    versionPill.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    versionPill.layer.cornerRadius = pillH / 2.0;
    versionPill.layer.borderWidth = 0.5;
    versionPill.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:versionPill.bounds];
    versionLabel.text = @"v3.0.1";
    versionLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    versionLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [versionPill addSubview:versionLabel];
    [titleBar addSubview:versionPill];

    y = 44 + 20;

    // ── Logo / icon row ──────────────────────────────────────────
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y, w, 48)];
    iconLabel.text = @"🎮";
    iconLabel.font = [UIFont systemFontOfSize:40];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:iconLabel];
    y += 48 + 14;

    // ── Description ──────────────────────────────────────────────
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = @"FnMacTweak lets you play Fortnite iOS on macOS with full mouse & keyboard support — including sensitivity tuning, key remapping, and build mode.";
    descLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    descLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 0;
    CGSize descSize = [descLabel sizeThatFits:CGSizeMake(contentW, CGFLOAT_MAX)];
    descLabel.frame = CGRectMake(pad, y, contentW, descSize.height);
    [self.view addSubview:descLabel];
    y += descSize.height + 18;

    // ── Divider ──────────────────────────────────────────────────
    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(pad, y, contentW, 0.5)];
    divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    [self.view addSubview:divider];
    y += 0.5 + 16;

    // ── "Opening Settings" hint box ──────────────────────────────
    UIView *hintBox = [[UIView alloc] init];
    hintBox.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    hintBox.layer.cornerRadius = 8;
    hintBox.layer.borderWidth = 0.5;
    hintBox.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.4].CGColor;

    UILabel *hintTitle = [[UILabel alloc] init];
    hintTitle.text = @"Opening Settings";
    hintTitle.textColor = [UIColor whiteColor];
    hintTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];

    UILabel *hintBody = [[UILabel alloc] init];
    hintBody.text = @"Press  P  at any time while in-game to open the FnMacTweak settings pane.";
    hintBody.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    hintBody.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    hintBody.numberOfLines = 0;

    UILabel *keyBadge = [[UILabel alloc] init];
    keyBadge.text = @"P";
    keyBadge.textColor = [UIColor whiteColor];
    keyBadge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    keyBadge.textAlignment = NSTextAlignmentCenter;
    keyBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1.0];
    keyBadge.layer.cornerRadius = 5;
    keyBadge.layer.borderWidth = 0.5;
    keyBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
    keyBadge.layer.masksToBounds = YES;

    CGFloat hintInner = contentW - 24;
    CGSize hintTitleSize = [hintTitle sizeThatFits:CGSizeMake(hintInner, 20)];
    CGSize hintBodySize = [hintBody sizeThatFits:CGSizeMake(hintInner, CGFLOAT_MAX)];
    CGFloat badgeSize = 28;
    CGFloat hintBoxH = 12 + hintTitleSize.height + 6 + badgeSize + 6 + hintBodySize.height + 12;

    hintBox.frame = CGRectMake(pad, y, contentW, hintBoxH);
    hintTitle.frame = CGRectMake(12, 12, hintInner, hintTitleSize.height);
    keyBadge.frame = CGRectMake(12, 12 + hintTitleSize.height + 6, badgeSize, badgeSize);
    hintBody.frame = CGRectMake(12, 12 + hintTitleSize.height + 6 + badgeSize + 6, hintInner, hintBodySize.height);

    [hintBox addSubview:hintTitle];
    [hintBox addSubview:keyBadge];
    [hintBox addSubview:hintBody];
    [self.view addSubview:hintBox];
    y += hintBoxH + 10;

    // ── "Lock / Unlock Cursor" — single full-width card ─────────
    UIView *lockUnlockBox = [[UIView alloc] init];
    lockUnlockBox.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
    lockUnlockBox.layer.cornerRadius = 8;
    lockUnlockBox.layer.borderWidth = 0.5;
    lockUnlockBox.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.4].CGColor;

    UILabel *lockUnlockTitle = [[UILabel alloc] init];
    lockUnlockTitle.text = @"Lock / Unlock Cursor";
    lockUnlockTitle.textColor = [UIColor whiteColor];
    lockUnlockTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];

    UILabel *luBadge1 = [[UILabel alloc] init];
    luBadge1.text = @"L⌥";
    luBadge1.textColor = [UIColor whiteColor];
    luBadge1.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    luBadge1.textAlignment = NSTextAlignmentCenter;
    luBadge1.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1.0];
    luBadge1.layer.cornerRadius = 5;
    luBadge1.layer.borderWidth = 0.5;
    luBadge1.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
    luBadge1.layer.masksToBounds = YES;

    UILabel *luPlus = [[UILabel alloc] init];
    luPlus.text = @"+";
    luPlus.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    luPlus.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    luPlus.textAlignment = NSTextAlignmentCenter;

    UILabel *luBadge2 = [[UILabel alloc] init];
    luBadge2.text = @"Click";
    luBadge2.textColor = [UIColor whiteColor];
    luBadge2.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    luBadge2.textAlignment = NSTextAlignmentCenter;
    luBadge2.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1.0];
    luBadge2.layer.cornerRadius = 5;
    luBadge2.layer.borderWidth = 0.5;
    luBadge2.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
    luBadge2.layer.masksToBounds = YES;

    UILabel *lockUnlockBody = [[UILabel alloc] init];
    lockUnlockBody.text = @"Hold Left Option and click to lock or unlock your mouse cursor to the game window.";
    lockUnlockBody.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    lockUnlockBody.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    lockUnlockBody.numberOfLines = 0;

    CGFloat innerW  = contentW - 24;
    CGFloat badgeH  = 28;
    CGFloat badge1W = 34, plusW = 14, badge2W = 42;

    CGSize titleSz = [lockUnlockTitle sizeThatFits:CGSizeMake(innerW, 20)];
    CGSize bodySz  = [lockUnlockBody  sizeThatFits:CGSizeMake(innerW, CGFLOAT_MAX)];
    CGFloat boxH   = 12 + titleSz.height + 6 + badgeH + 6 + bodySz.height + 12;

    lockUnlockBox.frame   = CGRectMake(pad, y, contentW, boxH);
    lockUnlockTitle.frame = CGRectMake(12, 12, innerW, titleSz.height);
    CGFloat badgeTop      = 12 + titleSz.height + 6;
    luBadge1.frame = CGRectMake(12,                           badgeTop, badge1W, badgeH);
    luPlus.frame   = CGRectMake(12 + badge1W + 3,             badgeTop, plusW,   badgeH);
    luBadge2.frame = CGRectMake(12 + badge1W + 3 + plusW + 3, badgeTop, badge2W, badgeH);
    lockUnlockBody.frame  = CGRectMake(12, badgeTop + badgeH + 6, innerW, bodySz.height);

    [lockUnlockBox addSubview:lockUnlockTitle];
    [lockUnlockBox addSubview:luBadge1];
    [lockUnlockBox addSubview:luPlus];
    [lockUnlockBox addSubview:luBadge2];
    [lockUnlockBox addSubview:lockUnlockBody];
    [self.view addSubview:lockUnlockBox];

    y += boxH + 22;

    // ── Buttons ──────────────────────────────────────────────────
    CGFloat btnH = 36;
    CGFloat btnSpacing = 8;
    CGFloat halfW = (contentW - btnSpacing) / 2.0;

    // Row 1 — Continue to Quick Start Guide (primary, full width)
    UIButton *continueBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    continueBtn.frame = CGRectMake(pad, y, contentW, btnH);
    continueBtn.backgroundColor = [UIColor colorWithRed:0.20 green:0.53 blue:1.0 alpha:1.0];
    [continueBtn setTitle:@"Continue to Quick Start Guide" forState:UIControlStateNormal];
    [continueBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    continueBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    continueBtn.layer.cornerRadius = 8;
    continueBtn.layer.masksToBounds = YES;
    [continueBtn addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:continueBtn];
    y += btnH + btnSpacing;

    // Row 2 left — Dismiss (styled to match tab grey buttons)
    UIButton *dismissBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    dismissBtn.frame = CGRectMake(pad, y, halfW, btnH);
    dismissBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
    [dismissBtn setTitle:@"Dismiss" forState:UIControlStateNormal];
    [dismissBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dismissBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    dismissBtn.layer.cornerRadius = 6;
    dismissBtn.layer.borderWidth = 0.5;
    dismissBtn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.4].CGColor;
    dismissBtn.layer.masksToBounds = YES;
    [dismissBtn addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:dismissBtn];

    // Row 2 right — Don't Show Again (styled to match tab grey buttons)
    UIButton *dontShowBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    dontShowBtn.frame = CGRectMake(pad + halfW + btnSpacing, y, halfW, btnH);
    dontShowBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
    [dontShowBtn setTitle:@"Don't Show Again" forState:UIControlStateNormal];
    [dontShowBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dontShowBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    dontShowBtn.layer.cornerRadius = 6;
    dontShowBtn.layer.borderWidth = 0.5;
    dontShowBtn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.4].CGColor;
    dontShowBtn.layer.masksToBounds = YES;
    [dontShowBtn addTarget:self action:@selector(dontShowAgainTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:dontShowBtn];
    y += btnH + 20;

    // ── Resize container and re-center vertically using actual content height ─
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *container = objc_getAssociatedObject(self, "welcomeContainer");
        if (container && container.superview) {
            CGRect superBounds = container.superview.bounds;
            CGRect f = container.frame;
            f.size.height = y;
            f.origin.y = (superBounds.size.height - y) / 2.0;
            container.frame = f;
        }
        // Keep vc.view pinned to container bounds (no autoresizing)
        self.view.frame = CGRectMake(0, 0, w, y);
    });
}

// ── Button actions ────────────────────────────────────────────────

- (void)continueTapped {
    // Close welcome container, then open P settings pane on Quick Start tab
    UIView *container = objc_getAssociatedObject(self, "welcomeContainer");
    if (container) {
        [UIView animateWithDuration:0.18 animations:^{
            container.alpha = 0.0;
            container.transform = CGAffineTransformMakeScale(0.85, 0.85);
        } completion:^(BOOL finished) {
            [container removeFromSuperview];
            showPopupOnQuickStartTab();
        }];
    } else {
        showPopupOnQuickStartTab();
    }
}

- (void)dismissTapped {
    [self closeWelcomeWindow];
}

- (void)dontShowAgainTapped {
    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.lastSeenVersion"] ?: @"2.0.4";
    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:kWelcomeSeenVersion];
    // Store which version was suppressed. When the version bumps,
    // this won't match and the popup will reshow once for the new version.
    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"fnmactweak.welcomeSuppressed"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self closeWelcomeWindow];
}

- (void)closeWelcomeWindow {
    // The welcome UI is now a UIView (welcomeContainer) inside the game window.
    // Retrieve it from the association set in showWelcomePopupIfNeeded.
    UIView *container = objc_getAssociatedObject(self, "welcomeContainer");
    if (container) {
        [UIView animateWithDuration:0.18 animations:^{
            container.alpha = 0.0;
            container.transform = CGAffineTransformMakeScale(0.85, 0.85);
        } completion:^(BOOL finished) {
            [container removeFromSuperview];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"FnMacTweakWelcomeDidClose"
                                                                object:nil];
        }];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"FnMacTweakWelcomeDidClose"
                                                            object:nil];
    }
}

@end


// ── C helper: show the welcome popup ─────────────────────────────
void showWelcomePopupIfNeeded(void) {
    // Use lastSeenVersion — written by %ctor on every install/update from the control
    // file version. This is reliable even for users upgrading from 2.0.0 where
    // fnmactweak.version was never written correctly due to the wrong bundle ID in postinst.
    NSString *currentVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.lastSeenVersion"] ?: @"2.0.4";

    // "Don't Show Again" suppression — only blocks if the suppressed version matches
    // the current version. A version bump clears this automatically.
    NSString *suppressedVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.welcomeSuppressed"];
    if (suppressedVersion && [suppressedVersion isEqualToString:currentVersion]) {
        return;
    }

    NSString *seenVersion = [[NSUserDefaults standardUserDefaults] stringForKey:kWelcomeSeenVersion];
    if (seenVersion && [seenVersion isEqualToString:currentVersion]) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        if (!scene) return;

        // Get the game window — the lowest-windowLevel window in the scene.
        // We add the welcome UI directly to this window so it can never steal
        // key-window status and never interferes with pointer lock.
        UIWindow *gameWindow = nil;
        for (UIWindow *w in scene.windows) {
            if (!gameWindow || w.windowLevel < gameWindow.windowLevel) {
                gameWindow = w;
            }
        }
        if (!gameWindow) return;

        CGFloat w = 320.0;
        CGFloat h = 420.0; // Resized by viewDidLoad
        CGSize screenSize = gameWindow.bounds.size;

        // Container view — added directly to the game window (no separate UIWindow needed)
        UIView *welcomeContainer = [[UIView alloc] initWithFrame:CGRectMake(
            (screenSize.width  - w) / 2.0,
            (screenSize.height - h) / 2.0,
            w, h
        )];
        welcomeContainer.layer.zPosition = 9999;
        welcomeContainer.userInteractionEnabled = YES;
        welcomeContainer.clipsToBounds = YES;
        welcomeContainer.alpha = 0.0;
        welcomeContainer.transform = CGAffineTransformMakeScale(0.7, 0.7);

        welcomeViewController *vc = [welcomeViewController new];

        // Fixed size — no autoresizing
        vc.view.frame = CGRectMake(0, 0, w, h);
        vc.view.autoresizingMask = UIViewAutoresizingNone;
        vc.view.userInteractionEnabled = YES;

        // Retain the VC via association on the container view
        objc_setAssociatedObject(welcomeContainer, "welcomeVC", vc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [welcomeContainer addSubview:vc.view];
        [gameWindow addSubview:welcomeContainer];

        // Store container ref on the VC so button actions can hide/remove it
        objc_setAssociatedObject(vc, "welcomeContainer", welcomeContainer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [UIView animateWithDuration:0.45
                              delay:0
             usingSpringWithDamping:0.6
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            welcomeContainer.alpha = 1.0;
            welcomeContainer.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}
