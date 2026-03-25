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

    // ── Title bar (40px, matches P pane) ───────────────────────
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 40)];
    titleBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.15];
    [self.view addSubview:titleBar];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, w, 40)];
    titleLabel.text = @"Welcome to FnMacTweak";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleBar addSubview:titleLabel];

    // Version pill — matches P settings pane pill style
    CGFloat pillW = 44.0;
    CGFloat pillH = 16.0;
    CGFloat pillX = w - 12.0 - pillW;
    CGFloat pillY = (40.0 - pillH) / 2.0;
    UIView *versionPill = [[UIView alloc] initWithFrame:CGRectMake(pillX, pillY, pillW, pillH)];
    versionPill.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    versionPill.layer.cornerRadius = pillH / 2.0;
    versionPill.layer.borderWidth = 0.5;
    versionPill.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1.0].CGColor;
    UILabel *versionLabel = [[UILabel alloc] initWithFrame:versionPill.bounds];
    versionLabel.text = @"v4.0.0";
    versionLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    versionLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [versionPill addSubview:versionLabel];
    [titleBar addSubview:versionPill];

    y = 40 + 20;

    // ── Logo / icon row ──────────────────────────────────────────
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y, w, 48)];
    iconLabel.text = @"🎮";
    iconLabel.font = [UIFont systemFontOfSize:40];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:iconLabel];
    y += 48 + 14;

    // ── Description ──────────────────────────────────────────────
    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = @"FnMacTweak lets you play Fortnite iOS on macOS with full mouse & keyboard support — including sensitivity tuning, key remapping, and controller mode.";
    descLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    descLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    descLabel.textAlignment = NSTextAlignmentCenter;
    descLabel.numberOfLines = 0;
    CGSize descSize = [descLabel sizeThatFits:CGSizeMake(contentW, CGFLOAT_MAX)];
    descLabel.frame = CGRectMake(pad, y, contentW, descSize.height);
    [self.view addSubview:descLabel];
    y += descSize.height + 18;

    // ── Divider ──────────────────────────────────────────────────
    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(pad, y, contentW, 1.0)];
    divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [self.view addSubview:divider];
    y += 1.0 + 16;
    
    // Layout constants for grids
    CGFloat gutter  = 8.0;
    CGFloat cellW   = (contentW - gutter) / 2.0;
    CGFloat cellPad = 10.0;
    CGFloat badgeH  = 26.0;
    CGFloat innerCW = cellW - cellPad * 2;
    
    // ── Typing Mode (Caps Lock) ──────────────────────────────────
    CGFloat typingModeCellH = 72.0;
    UIView *typingModeCell = [[UIView alloc] initWithFrame:CGRectMake(pad, y, contentW, typingModeCellH)];
    typingModeCell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
    typingModeCell.layer.cornerRadius = 8;
    typingModeCell.layer.borderWidth = 0.5;
    typingModeCell.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
    [self.view addSubview:typingModeCell];
    
    UILabel *typingTitle = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, 10, contentW - cellPad*2, 16)];
    typingTitle.text = @"Typing Mode (Raw Input)";
    typingTitle.textColor = [UIColor whiteColor];
    typingTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [typingModeCell addSubview:typingTitle];
    
    UILabel *capsBadge = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, 34, 74, 26)];
    capsBadge.text = @"Caps Lock";
    capsBadge.textColor = [UIColor whiteColor];
    capsBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    capsBadge.textAlignment = NSTextAlignmentCenter;
    capsBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
    capsBadge.layer.cornerRadius = 5;
    capsBadge.layer.borderWidth = 0.5;
    capsBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
    capsBadge.layer.masksToBounds = YES;
    [typingModeCell addSubview:capsBadge];
    
    UILabel *typingDesc = [[UILabel alloc] initWithFrame:CGRectMake(cellPad + 82, 30, contentW - (cellPad + 82) - cellPad, 36)];
    typingDesc.text = @"Toggles raw keyboard input. Syncs with your keyboard's light.";
    typingDesc.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    typingDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    typingDesc.numberOfLines = 2;
    [typingModeCell addSubview:typingDesc];
    
    y += typingModeCellH + 12;

    // ── 2-COLUMN GRID: "Opening Settings" | "Lock / Unlock Cursor" ──

    // Measure desc text so both cells share equal height
    UILabel *tmpP = [[UILabel alloc] init];
    tmpP.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    tmpP.numberOfLines = 0;
    tmpP.text = @"Press P to open the settings pane.";
    CGFloat pDescH = [tmpP sizeThatFits:CGSizeMake(innerCW, CGFLOAT_MAX)].height;

    UILabel *tmpL = [[UILabel alloc] init];
    tmpL.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    tmpL.numberOfLines = 0;
    tmpL.text = @"Press L to lock or unlock the cursor.";
    CGFloat lDescH = [tmpL sizeThatFits:CGSizeMake(innerCW, CGFLOAT_MAX)].height;

    CGFloat titleH = 16.0;
    CGFloat descH  = MAX(pDescH, lDescH);
    CGFloat cellH  = cellPad + titleH + 8 + badgeH + 8 + descH + cellPad;

    // ── Left cell: Opening Settings ──────────────────────────────
    UIView *openCell = [[UIView alloc] initWithFrame:CGRectMake(pad, y, cellW, cellH)];
    openCell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
    openCell.layer.cornerRadius = 8;
    openCell.layer.borderWidth = 0.5;
    openCell.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
    [self.view addSubview:openCell];

    UILabel *openTitle = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad, innerCW, titleH)];
    openTitle.text = @"Opening Settings";
    openTitle.textColor = [UIColor whiteColor];
    openTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [openCell addSubview:openTitle];

    UILabel *pBadge = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8, 28, badgeH)];
    pBadge.text = @"P";
    pBadge.textColor = [UIColor whiteColor];
    pBadge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    pBadge.textAlignment = NSTextAlignmentCenter;
    pBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
    pBadge.layer.cornerRadius = 5;
    pBadge.layer.borderWidth = 0.5;
    pBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
    pBadge.layer.masksToBounds = YES;
    [openCell addSubview:pBadge];

    UILabel *openDesc = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8 + badgeH + 8, innerCW, descH)];
    openDesc.text = @"Press P to open the settings pane.";
    openDesc.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    openDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    openDesc.numberOfLines = 0;
    [openCell addSubview:openDesc];

    // ── Right cell: Lock / Unlock Cursor ─────────────────────────
    UIView *lockCell = [[UIView alloc] initWithFrame:CGRectMake(pad + cellW + gutter, y, cellW, cellH)];
    lockCell.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
    lockCell.layer.cornerRadius = 8;
    lockCell.layer.borderWidth = 0.5;
    lockCell.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
    [self.view addSubview:lockCell];

    UILabel *lockTitle = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad, innerCW, titleH)];
    lockTitle.text = @"Lock / Unlock Cursor";
    lockTitle.textColor = [UIColor whiteColor];
    lockTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [lockCell addSubview:lockTitle];

    UILabel *lBadge = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8, 28, badgeH)];
    lBadge.text = @"L";
    lBadge.textColor = [UIColor whiteColor];
    lBadge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    lBadge.textAlignment = NSTextAlignmentCenter;
    lBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
    lBadge.layer.cornerRadius = 5;
    lBadge.layer.borderWidth = 0.5;
    lBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
    lBadge.layer.masksToBounds = YES;
    [lockCell addSubview:lBadge];

    UILabel *lockDesc = [[UILabel alloc] initWithFrame:CGRectMake(cellPad, cellPad + titleH + 8 + badgeH + 8, innerCW, descH)];
    lockDesc.text = @"Press L to lock or unlock the cursor.";
    lockDesc.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    lockDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    lockDesc.numberOfLines = 0;
    [lockCell addSubview:lockDesc];

    y += cellH + 22;

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
