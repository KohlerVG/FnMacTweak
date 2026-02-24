// =============================================================================
//  popupViewController.m — FnMacTweak
//  The floating settings panel (opened with the P key in-game).
//
//  FILE STRUCTURE — search for these section markers to navigate:
//
//  ① FnMakePill / FnAnimatePress     — Shared liquid-glass UI helpers
//  ② FnCustomControlsView            — Video player transport bar (play/pause,
//                                       skip ±5 s, scrubber, time labels)
//  ③ FnCustomPlayerView              — Full video player view (player layer +
//                                       controls + close button + hover/tap
//                                       handling)
//  ④ FnVideoPlayerPopupVC            — Modal view controller wrapping the
//  player,
//                                       presented from the Quick Start tab
//  ⑤ popupViewController             — Main settings panel (all five tabs):
//       • Sensitivity tab            — Hip-fire & ADS sensitivity, scale factor
//       • Key Remap tab              — Fortnite action keybinds + custom remaps
//       • Build Mode tab             — Enable/disable build mode, reset red dot
//       • Container tab              — Fortnite data folder access,
//       import/export • Quick Start tab            — Tutorial cards + video
//       launch button
//
//  CONTRIBUTING:
//    • Each tab's content is built by a dedicated helper method
//    (buildSensitivityTab,
//      buildKeyRemapTab, etc.). Add new controls there.
//    • All layout is code-based — no Storyboards or Xibs.
//    • UI constants (card width, padding, font sizes) are defined as local
//    CGFloat
//      variables at the top of each build method for easy tuning.
//    • The video player is self-contained in FnCustomControlsView /
//      FnCustomPlayerView / FnVideoPlayerPopupVC. Changes to playback behaviour
//      should stay within those classes.
// =============================================================================

#import "./popupViewController.h"
#import "../FnOverlayWindow.h"
#import "../globals.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

// ─────────────────────────────────────────────────────────────────
//  FnVideoPlayerPopup & helpers
// ─────────────────────────────────────────────────────────────────

// -----------------------------------------------------------------------------
// =============================================================================
// FnLiquidGlassPill — shared helper: creates a blurred pill-shaped container
// with a thin specular border, used for ALL controls (close + transport).
// =============================================================================
static UIVisualEffectView *FnMakePill(CGRect frame) {
  UIBlurEffect *blur = [UIBlurEffect
      effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
  UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:blur];
  pill.frame = frame;
  pill.layer.cornerRadius = frame.size.height / 2.0;
  pill.layer.masksToBounds = YES;
  // Subtle specular ring — same as system Liquid Glass
  pill.layer.borderWidth = 0.5;
  pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
  return pill;
}

// Shared spring press-down / release animation for any UIView
static void FnAnimatePress(UIView *v, BOOL down) {
  CGFloat scale = down ? 0.88 : 1.0;
  [UIView animateWithDuration:down ? 0.10 : 0.22
                        delay:0
       usingSpringWithDamping:down ? 1.0 : 0.55
        initialSpringVelocity:down ? 0 : 0.6
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     v.transform = CGAffineTransformMakeScale(scale, scale);
                   }
                   completion:nil];
}

// =============================================================================
// FnCustomControlsView
// Floating pill transport bar — sits 16 pt above the bottom edge, inset 20 pt
// from left/right.  All buttons share the same liquid-glass pill style.
// Layout: [←5s pill] [▶ pill] [5s→ pill]  ·  elapsed  scrubber  remaining
// =============================================================================

@interface FnCustomControlsView : UIView
@property(nonatomic, weak) AVPlayer *player;
@property(nonatomic, strong) UIVisualEffectView *barPill; // outer pill
@property(nonatomic, strong) UIButton *playPauseButton;
@property(nonatomic, strong) UIButton *skipBackButton;
@property(nonatomic, strong) UIButton *skipForwardButton;
@property(nonatomic, strong) UISlider *scrubber;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UILabel *remainLabel;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic, assign) BOOL scrubbing;
@property(nonatomic, assign) BOOL videoDidFinish;
@property(nonatomic, assign) NSInteger lastDisplayedSecond;
- (void)attachToPlayer:(AVPlayer *)player;
- (void)detachFromPlayer;
- (void)syncPlayPauseButton;
- (void)togglePlayPause;
@end

@implementation FnCustomControlsView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self)
    return self;
  self.backgroundColor = [UIColor clearColor];

  // ── Outer floating pill (the bar itself) ──
  self.barPill = FnMakePill(self.bounds);
  self.barPill.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self addSubview:self.barPill];

  UIImageSymbolConfiguration *skipCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:15
                          weight:UIImageSymbolWeightMedium];
  UIImageSymbolConfiguration *playCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:18
                          weight:UIImageSymbolWeightMedium];

  // ── Skip Back 5 s ──
  self.skipBackButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.skipBackButton setImage:[UIImage systemImageNamed:@"gobackward.5"
                                        withConfiguration:skipCfg]
                       forState:UIControlStateNormal];
  self.skipBackButton.tintColor = [UIColor whiteColor];
  [self.skipBackButton addTarget:self
                          action:@selector(skipBack)
                forControlEvents:UIControlEventTouchUpInside];
  [self.skipBackButton
             addTarget:self
                action:@selector(btnPressDown:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.skipBackButton
             addTarget:self
                action:@selector(btnPressUp:)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.barPill.contentView addSubview:self.skipBackButton];

  // ── Play / Pause ──
  self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"
                                         withConfiguration:playCfg]
                        forState:UIControlStateNormal];
  self.playPauseButton.tintColor = [UIColor whiteColor];
  [self.playPauseButton addTarget:self
                           action:@selector(togglePlayPause)
                 forControlEvents:UIControlEventTouchUpInside];
  [self.playPauseButton
             addTarget:self
                action:@selector(btnPressDown:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.playPauseButton
             addTarget:self
                action:@selector(btnPressUp:)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.barPill.contentView addSubview:self.playPauseButton];

  // ── Skip Forward 5 s ──
  self.skipForwardButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.skipForwardButton setImage:[UIImage systemImageNamed:@"goforward.5"
                                           withConfiguration:skipCfg]
                          forState:UIControlStateNormal];
  self.skipForwardButton.tintColor = [UIColor whiteColor];
  [self.skipForwardButton addTarget:self
                             action:@selector(skipForward)
                   forControlEvents:UIControlEventTouchUpInside];
  [self.skipForwardButton
             addTarget:self
                action:@selector(btnPressDown:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.skipForwardButton
             addTarget:self
                action:@selector(btnPressUp:)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.barPill.contentView addSubview:self.skipForwardButton];

  // ── Thin vertical divider between transport and scrubber area ──
  UIView *div = [[UIView alloc] init];
  div.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
  div.tag = 77;
  [self.barPill.contentView addSubview:div];

  // ── Elapsed time ──
  self.timeLabel = [[UILabel alloc] init];
  self.timeLabel.text = @"0:00";
  self.timeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
  self.timeLabel.font =
      [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
  self.timeLabel.textAlignment = NSTextAlignmentRight;
  [self.barPill.contentView addSubview:self.timeLabel];

  // ── Scrubber ──
  self.scrubber = [[UISlider alloc] init];
  self.scrubber.minimumValue = 0.0;
  self.scrubber.maximumValue = 1.0;
  self.scrubber.value = 0.0;
  self.scrubber.minimumTrackTintColor = [UIColor colorWithRed:0.3
                                                        green:0.65
                                                         blue:1.0
                                                        alpha:1.0];
  self.scrubber.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.22];
  self.scrubber.thumbTintColor = [UIColor whiteColor];
  UITapGestureRecognizer *scrubTap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleScrubberTap:)];
  [self.scrubber addGestureRecognizer:scrubTap];
  [self.scrubber addTarget:self
                    action:@selector(scrubberBegan:)
          forControlEvents:UIControlEventTouchDown];
  [self.scrubber addTarget:self
                    action:@selector(scrubberChanged:)
          forControlEvents:UIControlEventValueChanged];
  [self.scrubber addTarget:self
                    action:@selector(scrubberEnded:)
          forControlEvents:UIControlEventTouchUpInside |
                           UIControlEventTouchUpOutside];
  [self.barPill.contentView addSubview:self.scrubber];

  // ── Remaining time ──
  self.remainLabel = [[UILabel alloc] init];
  self.remainLabel.text = @"-0:00";
  self.remainLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.45];
  self.remainLabel.font =
      [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
  self.remainLabel.textAlignment = NSTextAlignmentLeft;
  [self.barPill.contentView addSubview:self.remainLabel];

  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat W = self.bounds.size.width;
  CGFloat H = self.bounds.size.height;
  CGFloat mid = H / 2.0;
  CGFloat pad = 16.0;

  // Transport cluster
  CGFloat btnH = H - 10;
  CGFloat skipW = 38.0;
  CGFloat ppW = 44.0;
  CGFloat gap = 4.0;

  self.skipBackButton.frame = CGRectMake(pad, mid - btnH / 2, skipW, btnH);
  self.playPauseButton.frame =
      CGRectMake(pad + skipW + gap, mid - btnH / 2, ppW, btnH);
  self.skipForwardButton.frame =
      CGRectMake(pad + skipW + gap + ppW + gap, mid - btnH / 2, skipW, btnH);

  CGFloat transportRight = pad + skipW + gap + ppW + gap + skipW;

  // Divider
  UIView *div = [self.barPill.contentView viewWithTag:77];
  div.frame = CGRectMake(transportRight + 10, 10, 0.5, H - 20);

  // Scrubber area
  CGFloat timW = 40.0;
  CGFloat remW = 46.0;
  CGFloat scrubX = transportRight + 24 + timW + 6;
  CGFloat scrubW = W - scrubX - remW - 10 - pad;

  self.timeLabel.frame = CGRectMake(transportRight + 24, mid - 10, timW, 20);
  self.scrubber.frame = CGRectMake(scrubX, mid - 10, scrubW, 20);
  self.remainLabel.frame = CGRectMake(scrubX + scrubW + 6, mid - 10, remW, 20);
}

// ── Tap anywhere on the scrubber track to jump ──
- (void)handleScrubberTap:(UITapGestureRecognizer *)tap {
  CGPoint pt = [tap locationInView:self.scrubber];
  CGFloat pct = MAX(0.0, MIN(1.0, pt.x / self.scrubber.bounds.size.width));
  [self.scrubber setValue:pct animated:NO];
  [self seekToFraction:pct];
}

- (void)seekToFraction:(float)pct {
  CMTime dur = self.player.currentItem.duration;
  if (!CMTIME_IS_NUMERIC(dur))
    return;
  CMTime target =
      CMTimeMakeWithSeconds(pct * CMTimeGetSeconds(dur), NSEC_PER_SEC);
  [self.player seekToTime:target
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
}

- (void)attachToPlayer:(AVPlayer *)player {
  self.player = player;
  self.videoDidFinish = NO;
  __weak typeof(self) weak = self;
  CMTime interval = CMTimeMakeWithSeconds(0.25, NSEC_PER_SEC);
  self.timeObserver =
      [player addPeriodicTimeObserverForInterval:interval
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^(CMTime time) {
                                        [weak tickTime:time];
                                      }];
  [player.currentItem addObserver:self
                       forKeyPath:@"status"
                          options:NSKeyValueObservingOptionNew
                          context:nil];
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(playerItemDidReachEnd:)
             name:AVPlayerItemDidPlayToEndTimeNotification
           object:player.currentItem];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
  self.videoDidFinish = YES;
  [self syncPlayPauseButton];
}

- (void)detachFromPlayer {
  if (self.timeObserver && self.player)
    [self.player removeTimeObserver:self.timeObserver];
  self.timeObserver = nil;
  @try {
    [self.player.currentItem removeObserver:self forKeyPath:@"status"];
  } @catch (NSException *e) {
  }
  [[NSNotificationCenter defaultCenter]
      removeObserver:self
                name:AVPlayerItemDidPlayToEndTimeNotification
              object:self.player.currentItem];
  self.player = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if ([keyPath isEqualToString:@"status"] &&
      self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
    dispatch_async(dispatch_get_main_queue(), ^{
      CMTime dur = self.player.currentItem.duration;
      self.remainLabel.text = [NSString
          stringWithFormat:@"-%@", [self formatTime:CMTimeGetSeconds(dur)]];
      self.scrubber.value = 0.0;
    });
  }
}

- (void)tickTime:(CMTime)time {
  NSTimeInterval cur = CMTimeGetSeconds(time);
  // Only redraw labels when the displayed second actually changes
  NSInteger curSec = (NSInteger)cur;
  if (curSec != self.lastDisplayedSecond) {
    self.lastDisplayedSecond = curSec;
    self.timeLabel.text = [self formatTime:cur];
    CMTime dur = self.player.currentItem.duration;
    if (!self.scrubbing && CMTIME_IS_NUMERIC(dur) &&
        CMTimeGetSeconds(dur) > 0) {
      NSTimeInterval rem = CMTimeGetSeconds(dur) - cur;
      self.remainLabel.text =
          [NSString stringWithFormat:@"-%@", [self formatTime:rem]];
    }
  }
  if (!self.scrubbing) {
    CMTime dur = self.player.currentItem.duration;
    if (CMTIME_IS_NUMERIC(dur) && CMTimeGetSeconds(dur) > 0) {
      self.scrubber.value = (float)(cur / CMTimeGetSeconds(dur));
    }
  }
  [self syncPlayPauseButton];
}

- (NSString *)formatTime:(NSTimeInterval)s {
  if (isnan(s) || isinf(s) || s < 0)
    return @"0:00";
  NSInteger total = (NSInteger)s;
  NSInteger sec = total % 60;
  NSInteger min = (total / 60) % 60;
  NSInteger hr = total / 3600;
  if (hr > 0)
    return [NSString
        stringWithFormat:@"%ld:%02ld:%02ld", (long)hr, (long)min, (long)sec];
  return [NSString stringWithFormat:@"%ld:%02ld", (long)min, (long)sec];
}

- (void)syncPlayPauseButton {
  UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
      configurationWithPointSize:18
                          weight:UIImageSymbolWeightMedium];
  NSString *name;
  if (self.videoDidFinish) {
    name = @"arrow.counterclockwise";
  } else {
    name = (self.player.rate > 0) ? @"pause.fill" : @"play.fill";
  }
  [self.playPauseButton setImage:[UIImage systemImageNamed:name
                                         withConfiguration:cfg]
                        forState:UIControlStateNormal];
}

- (void)togglePlayPause {
  if (self.videoDidFinish) {
    // Replay from the beginning
    self.videoDidFinish = NO;
    [self.player seekToTime:kCMTimeZero
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
            if (finished)
              [self.player play];
          }];
  } else if (self.player.rate > 0) {
    [self.player pause];
  } else {
    [self.player play];
  }
  [self syncPlayPauseButton];
}

- (void)skipBack {
  CMTime t = CMTimeSubtract(self.player.currentTime,
                            CMTimeMakeWithSeconds(5, NSEC_PER_SEC));
  if (CMTimeGetSeconds(t) < 0)
    t = kCMTimeZero;
  [self.player seekToTime:t
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
}

- (void)skipForward {
  CMTime t = CMTimeAdd(self.player.currentTime,
                       CMTimeMakeWithSeconds(5, NSEC_PER_SEC));
  CMTime dur = self.player.currentItem.duration;
  if (CMTIME_IS_NUMERIC(dur) && CMTimeCompare(t, dur) > 0)
    t = dur;
  [self.player seekToTime:t
          toleranceBefore:kCMTimeZero
           toleranceAfter:kCMTimeZero];
}

- (void)scrubberBegan:(UISlider *)s {
  self.scrubbing = YES;
  // Tell the parent player view to cancel its hide timer for the duration of
  // the scrub.
  UIView *parent = self.superview;
  if ([parent respondsToSelector:@selector(cancelHideTimer)]) {
    [parent performSelector:@selector(cancelHideTimer)];
  }
}
- (void)scrubberChanged:(UISlider *)s {
  CMTime dur = self.player.currentItem.duration;
  if (!CMTIME_IS_NUMERIC(dur))
    return;
  NSTimeInterval totalSecs = CMTimeGetSeconds(dur);
  NSTimeInterval cur = s.value * totalSecs;
  NSTimeInterval rem = totalSecs - cur;
  self.timeLabel.text = [self formatTime:cur];
  self.remainLabel.text =
      [NSString stringWithFormat:@"-%@", [self formatTime:rem]];
  // Live scrub — seek with loose tolerance for smooth real-time preview
  CMTime target = CMTimeMakeWithSeconds(cur, NSEC_PER_SEC);
  CMTime tol = CMTimeMakeWithSeconds(0.1, NSEC_PER_SEC);
  [self.player seekToTime:target toleranceBefore:tol toleranceAfter:tol];
}
- (void)scrubberEnded:(UISlider *)s {
  // Final precise seek on release
  [self seekToFraction:s.value];
  self.scrubbing = NO;
  // Resume auto-hide now that the user has finished scrubbing.
  UIView *parent = self.superview;
  if ([parent respondsToSelector:@selector(scheduleHide)]) {
    [parent performSelector:@selector(scheduleHide)];
  }
}

// ── Button press spring animations ──
- (void)btnPressDown:(UIButton *)btn {
  FnAnimatePress(btn, YES);
}
- (void)btnPressUp:(UIButton *)btn {
  FnAnimatePress(btn, NO);
}

@end

// =============================================================================
// FnCustomPlayerView
// • AVPlayerLayer fills the view — no AVPlayerViewController, no overlays
// • Floating pill controls bar: sits 16 pt above bottom, inset 20 pt each side
// • Close button: liquid glass pill, same style, top-left corner
// • Mouse hover shows controls; 3 s idle hides them; tap toggles play/pause
// =============================================================================
@interface FnCustomPlayerView : UIView
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) FnCustomControlsView *controlsBar;
@property(nonatomic, strong) UIVisualEffectView *closeButton;
@property(nonatomic, strong) NSTimer *hideTimer;
@property(nonatomic, assign) BOOL controlsVisible;
- (instancetype)initWithPlayer:(AVPlayer *)player
                 dismissTarget:(id)target
                        action:(SEL)action;
- (void)showControlsAnimated:(BOOL)animated;
- (void)hideControlsAnimated:(BOOL)animated;
- (void)scheduleHide;
@end

@implementation FnCustomPlayerView

- (instancetype)initWithPlayer:(AVPlayer *)player
                 dismissTarget:(id)target
                        action:(SEL)action {
  self = [super initWithFrame:CGRectZero];
  if (!self)
    return self;
  self.backgroundColor = [UIColor blackColor];
  self.player = player;

  // ── Video layer ──
  self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
  self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
  // Performance: pixel-aligned output, no unnecessary compositing
  self.playerLayer.contentsGravity = kCAGravityResizeAspect;
  self.playerLayer.drawsAsynchronously = YES;
  [self.layer addSublayer:self.playerLayer];

  // ── Floating transport pill (44 pt tall) ──
  CGFloat barH = 44.0;
  self.controlsBar =
      [[FnCustomControlsView alloc] initWithFrame:CGRectMake(0, 0, 100, barH)];
  self.controlsBar.layer.shadowColor = [UIColor blackColor].CGColor;
  self.controlsBar.layer.shadowOpacity = 0.35;
  self.controlsBar.layer.shadowRadius = 12.0;
  self.controlsBar.layer.shadowOffset = CGSizeMake(0, 4);
  [self addSubview:self.controlsBar];
  [self.controlsBar attachToPlayer:player];

  // ── Close button — liquid glass circle, same height as transport bar (44 pt)
  // ──
  CGFloat closeS = 44.0;
  self.closeButton = FnMakePill(CGRectMake(20, 16, closeS, closeS));
  self.closeButton.layer.shadowColor = [UIColor blackColor].CGColor;
  self.closeButton.layer.shadowOpacity = 0.3;
  self.closeButton.layer.shadowRadius = 6.0;
  self.closeButton.layer.shadowOffset = CGSizeMake(0, 2);

  UIImageSymbolConfiguration *closeCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:16
                          weight:UIImageSymbolWeightSemibold];
  UIImageView *xIcon =
      [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark"
                                                 withConfiguration:closeCfg]];
  xIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85]; // bright at rest
  xIcon.contentMode = UIViewContentModeCenter;
  xIcon.frame = self.closeButton.contentView.bounds;
  xIcon.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  xIcon.tag = 998; // used by press animation
  [self.closeButton.contentView addSubview:xIcon];

  // Use a UIButton overlay so we get built-in highlight + our spring animation
  UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  closeBtn.frame = self.closeButton.contentView.bounds;
  closeBtn.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [closeBtn addTarget:target
                action:action
      forControlEvents:UIControlEventTouchUpInside];
  [closeBtn addTarget:self
                action:@selector(closePressDown)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [closeBtn addTarget:self
                action:@selector(closePressUp)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  [self.closeButton.contentView addSubview:closeBtn];
  [self addSubview:self.closeButton];

  // ── Tap on video (outside controls) → play/pause ──
  UITapGestureRecognizer *videoTap = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(handleVideoTap:)];
  videoTap.cancelsTouchesInView = NO;
  [self addGestureRecognizer:videoTap];

  // ── Mouse tracking (Catalyst / iPadOS pointer) ──
  if (@available(iOS 13.4, *)) {
    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleHover:)];
    [self addGestureRecognizer:hover];
  }

  // Start visible, auto-hide after 3 s
  self.controlsVisible = YES;
  self.controlsBar.alpha = 1.0;
  self.closeButton.alpha = 1.0;
  [self scheduleHide];

  return self;
}

// ── Close button press: animate the xIcon only (scale + opacity) ──
// Never scale the pill itself — that distorts the rounded corners.
- (void)closePressDown {
  UIView *icon = [self.closeButton viewWithTag:998];
  [UIView animateWithDuration:0.10
                        delay:0
       usingSpringWithDamping:1.0
        initialSpringVelocity:0
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     icon.transform = CGAffineTransformMakeScale(0.78, 0.78);
                     icon.alpha = 0.4; // darker on press-down
                   }
                   completion:nil];
}
- (void)closePressUp {
  UIView *icon = [self.closeButton viewWithTag:998];
  [UIView animateWithDuration:0.22
                        delay:0
       usingSpringWithDamping:0.55
        initialSpringVelocity:0.6
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     icon.transform = CGAffineTransformIdentity;
                     icon.alpha = 0.85; // restore resting brightness
                   }
                   completion:nil];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  self.playerLayer.frame = self.bounds;

  CGFloat inset = 20.0;
  CGFloat barH = 44.0;
  CGFloat closeS = 44.0;

  // Transport bar — floats 16 pt above bottom edge
  CGFloat barY = self.bounds.size.height - barH - 16.0;
  self.controlsBar.frame =
      CGRectMake(inset, barY, self.bounds.size.width - inset * 2, barH);
  self.controlsBar.layer.shadowPath =
      [UIBezierPath bezierPathWithRoundedRect:self.controlsBar.bounds
                                 cornerRadius:barH / 2.0]
          .CGPath;

  // Close button — top-left, same inset as bar, same height
  self.closeButton.frame = CGRectMake(inset, 16.0, closeS, closeS);
  self.closeButton.layer.cornerRadius = closeS / 2.0;
}

- (void)handleHover:(UIHoverGestureRecognizer *)hover {
  if (@available(iOS 13.4, *)) {
    UIGestureRecognizerState s = hover.state;
    if (s == UIGestureRecognizerStateBegan ||
        s == UIGestureRecognizerStateChanged) {
      if (!self.controlsVisible)
        [self showControlsAnimated:YES];
      [self scheduleHide];
    } else if (s == UIGestureRecognizerStateEnded ||
               s == UIGestureRecognizerStateCancelled) {
      [self.hideTimer invalidate];
      self.hideTimer = nil;
      if (self.controlsVisible)
        [self hideControlsAnimated:YES];
    }
  }
}

- (void)handleVideoTap:(UITapGestureRecognizer *)tap {
  CGPoint pt = [tap locationInView:self];
  if (CGRectContainsPoint(self.controlsBar.frame, pt))
    return;
  [self.controlsBar togglePlayPause];
  [self showControlsAnimated:YES];
  [self scheduleHide];
}

- (void)showControlsAnimated:(BOOL)animated {
  self.controlsVisible = YES;
  // Cancel any in-flight hide
  [self.controlsBar.layer removeAnimationForKey:@"fnOpacity"];
  [self.closeButton.layer removeAnimationForKey:@"fnOpacity"];
  if (animated) {
    // CABasicAnimation runs entirely on the render server — no main-thread
    // involvement, no rasterise toggle race, perfectly smooth.
    CGFloat fromAlpha = self.controlsBar.layer.presentationLayer
                            ? self.controlsBar.layer.presentationLayer.opacity
                            : 0.0;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @(fromAlpha);
    a.toValue = @1.0;
    a.duration = 0.20;
    a.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    a.removedOnCompletion = YES;
    [self.controlsBar.layer addAnimation:a forKey:@"fnOpacity"];
    [self.closeButton.layer addAnimation:a forKey:@"fnOpacity"];
  }
  self.controlsBar.layer.opacity = 1.0;
  self.closeButton.layer.opacity = 1.0;
  self.controlsBar.alpha = 1.0;
  self.closeButton.alpha = 1.0;
}

- (void)hideControlsAnimated:(BOOL)animated {
  self.controlsVisible = NO;
  [self.hideTimer invalidate];
  self.hideTimer = nil;
  // Cancel any in-flight show
  [self.controlsBar.layer removeAnimationForKey:@"fnOpacity"];
  [self.closeButton.layer removeAnimationForKey:@"fnOpacity"];
  if (animated) {
    // Smooth custom cubic: gradual start, clean finish — no choppy EaseIn
    // cliff.
    CGFloat fromAlpha = self.controlsBar.layer.presentationLayer
                            ? self.controlsBar.layer.presentationLayer.opacity
                            : 1.0;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
    a.fromValue = @(fromAlpha);
    a.toValue = @0.0;
    a.duration = 0.28;
    a.timingFunction =
        [CAMediaTimingFunction functionWithControlPoints:0.4:0.0:0.6:1.0];
    a.removedOnCompletion = YES;
    [self.controlsBar.layer addAnimation:a forKey:@"fnOpacity"];
    [self.closeButton.layer addAnimation:a forKey:@"fnOpacity"];
  }
  self.controlsBar.layer.opacity = 0.0;
  self.closeButton.layer.opacity = 0.0;
  self.controlsBar.alpha = 0.0;
  self.closeButton.alpha = 0.0;
}

- (void)cancelHideTimer {
  [self.hideTimer invalidate];
  self.hideTimer = nil;
}

- (void)scheduleHide {
  [self.hideTimer invalidate];
  self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                    target:self
                                                  selector:@selector(autoHide)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)autoHide {
  if (self.controlsBar.scrubbing) {
    [self scheduleHide];
    return;
  }
  if (self.player.rate > 0)
    [self hideControlsAnimated:YES];
  else
    [self scheduleHide];
}

- (void)dealloc {
  [self.hideTimer invalidate];
  [self.controlsBar detachFromPlayer];
}

@end

// -----------------------------------------------------------------------------
// FnVideoPlayerPopup Interface (declared before FnVideoRootViewController
// so that sending messages to it compiles without a forward-declaration error)
// -----------------------------------------------------------------------------
@interface FnVideoPlayerPopup : NSObject

@property(nonatomic, strong) UIWindow *videoWindow;
@property(nonatomic, strong) UIView *overlayView;
@property(nonatomic, strong) UIView *playerContainer;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) FnCustomPlayerView *customPlayerView;
@property(nonatomic, strong) UIActivityIndicatorView *bufferingSpinner;

+ (instancetype)shared;
+ (instancetype)sharedInstance;
- (void)presentWithURL:(NSURL *)url inWindow:(UIWindow *)sourceWindow;
- (void)dismiss;
- (void)layoutResizeHandles:(UIView *)container;
- (void)addResizeHandlesToContainer:(UIView *)container;
- (void)handleDrag:(UIPanGestureRecognizer *)gr;
- (void)handleResize:(UIPanGestureRecognizer *)gr;
- (void)pushNSCursor:(NSString *)selName;
- (void)popNSCursor;

@end

// -----------------------------------------------------------------------------
// FnPassthroughView — passes touches outside the player container through to
// underlying windows so the game remains fully interactive.
// -----------------------------------------------------------------------------
@interface FnPassthroughView : UIView
@end
@implementation FnPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  return (hit == self) ? nil : hit;
}
@end

// FnVideoRootViewController — handles ESC key to close the popup
// -----------------------------------------------------------------------------
@interface FnVideoRootViewController : UIViewController
@end

@implementation FnVideoRootViewController

// Never lock the pointer to this window — pointer lock is owned by
// IOSViewController (the game).
- (BOOL)prefersPointerLocked {
  return NO;
}

// Use pass-through view so touches outside the player fall through to the game.
- (void)loadView {
  FnPassthroughView *v = [[FnPassthroughView alloc] init];
  self.view = v;
}

// Allow interaction with controls
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesBegan:touches withEvent:event];
}

// Handle ESC key to close
- (NSArray<UIKeyCommand *> *)keyCommands {
  return @[ [UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                                modifierFlags:0
                                       action:@selector(handleEsc:)] ];
}

- (void)handleEsc:(UIKeyCommand *)command {
  [[FnVideoPlayerPopup sharedInstance] dismiss];
}
@end

// ─────────────────────────────────────────────────────────────────
//  FnVideoPlayerPopup Implementation
// ─────────────────────────────────────────────────────────────────

@implementation FnVideoPlayerPopup

+ (instancetype)sharedInstance {
  static FnVideoPlayerPopup *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[FnVideoPlayerPopup alloc] init];
  });
  return sharedInstance;
}

+ (instancetype)shared {
  return [self sharedInstance];
}

- (void)presentWithURL:(NSURL *)url inWindow:(UIWindow *)sourceWindow {
  // 1. Lazy Load Window (Persistent)
  if (!self.videoWindow) {
    UIWindowScene *scene = (UIWindowScene *)sourceWindow.windowScene;
    if (!scene) return;

    self.videoWindow = [[FnOverlayWindow alloc] initWithWindowScene:scene];
    self.videoWindow.windowLevel = UIWindowLevelAlert + 10;
    self.videoWindow.backgroundColor = [UIColor clearColor];

    FnVideoRootViewController *rootVC = [[FnVideoRootViewController alloc] init];
    self.videoWindow.rootViewController = rootVC;

    [self setupPersistentUI];
  }

  // 2. Re-center the window (user may have dragged it last time).
  UIView *wrapper = objc_getAssociatedObject(self.playerContainer, "shadowWrapper");
  UIView *animTarget = wrapper ?: self.playerContainer;
  [animTarget.layer removeAllAnimations];

  CGFloat W = 1000, H = W * 9.0 / 16.0;
  UIWindowScene *ws = (UIWindowScene *)self.videoWindow.windowScene;
  CGRect sb = ws ? ws.effectiveGeometry.coordinateSpace.bounds : self.videoWindow.bounds;
  animTarget.transform = CGAffineTransformIdentity;
  animTarget.frame = CGRectMake(floor((sb.size.width - W) / 2.0),
                                floor((sb.size.height - H) / 2.0), W, H);
  if (wrapper)
    wrapper.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, W, H) cornerRadius:12].CGPath;
  self.playerContainer.frame = CGRectMake(0, 0, W, H);
  [self layoutResizeHandles:wrapper ?: self.playerContainer];

  // 3. Setup Player Item — detach/re-attach so controls bar observes the new item.
  //    *** Video loading is exactly as in v2.0.1 — untouched. ***
  [self.customPlayerView.controlsBar detachFromPlayer];
  AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
  item.preferredForwardBufferDuration = 10.0;
  [self.player replaceCurrentItemWithPlayerItem:item];
  [self.customPlayerView.controlsBar attachToPlayer:self.player];
  self.customPlayerView.controlsBar.scrubber.value = 0.0;
  [self.customPlayerView showControlsAnimated:NO];

  // 4. Show window and animate in.
  self.videoWindow.hidden = NO;
  animTarget.alpha = 0.0;
  animTarget.transform = CGAffineTransformMakeScale(0.8, 0.8);
  [UIView animateWithDuration:0.38
      delay:0
      usingSpringWithDamping:0.72
      initialSpringVelocity:0.3
      options:UIViewAnimationOptionAllowUserInteraction
      animations:^{ animTarget.transform = CGAffineTransformIdentity; animTarget.alpha = 1.0; }
      completion:^(BOOL finished) {
        [self.player play];
      }];
}

- (void)setupPersistentUI {
  // A. Transparent overlay — no dimming, floats freely like PiP.
  //    Covers full screen to capture gestures; pass-through view lets
  //    touches outside the player fall through to the game.
  self.overlayView = [[UIView alloc] initWithFrame:self.videoWindow.bounds];
  self.overlayView.backgroundColor = [UIColor clearColor];
  self.overlayView.alpha = 1.0;
  self.overlayView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.overlayView.userInteractionEnabled = NO;
  [self.videoWindow.rootViewController.view addSubview:self.overlayView];

  // B. Player Container — centered 16:9, 1000 pt wide
  CGFloat w = 1000;
  CGFloat h = w * 9.0 / 16.0;
  UIWindowScene *scene = (UIWindowScene *)self.videoWindow.windowScene;
  CGRect screenBounds = scene
      ? scene.effectiveGeometry.coordinateSpace.bounds
      : self.videoWindow.bounds;

  // Outer shadow wrapper — masksToBounds=NO so shadow renders outside bounds
  CGFloat ox = floor((screenBounds.size.width  - w) / 2.0);
  CGFloat oy = floor((screenBounds.size.height - h) / 2.0);
  UIView *shadowWrapper = [[UIView alloc] initWithFrame:CGRectMake(ox, oy, w, h)];
  shadowWrapper.backgroundColor = [UIColor clearColor];
  shadowWrapper.layer.shadowColor   = [UIColor blackColor].CGColor;
  shadowWrapper.layer.shadowOpacity = 0.55;
  shadowWrapper.layer.shadowRadius  = 20;
  shadowWrapper.layer.shadowOffset  = CGSizeMake(0, 6);
  shadowWrapper.layer.shadowPath    =
      [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h)
                                 cornerRadius:12].CGPath;
  [self.videoWindow.rootViewController.view addSubview:shadowWrapper];

  // Inner container — masksToBounds=YES clips video and controls to rounded rect
  self.playerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
  self.playerContainer.backgroundColor = [UIColor blackColor];
  self.playerContainer.layer.cornerRadius = 12;
  self.playerContainer.layer.masksToBounds = YES;
  self.playerContainer.layer.borderWidth = 1.0;
  self.playerContainer.layer.borderColor =
      [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
  [shadowWrapper addSubview:self.playerContainer];

  // Store shadow wrapper so drag/resize can move it together
  objc_setAssociatedObject(self.playerContainer, "shadowWrapper",
                           shadowWrapper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  // Drag to move
  UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc]
      initWithTarget:self action:@selector(handleDrag:)];
  drag.minimumNumberOfTouches = 1;
  [self.playerContainer addGestureRecognizer:drag];

  // Resize handles on shadowWrapper — outside masksToBounds clip
  [self addResizeHandlesToContainer:shadowWrapper];

  // C. AVPlayer & Custom Player View
  self.player = [[AVPlayer alloc] init];
  self.player.allowsExternalPlayback = NO;

  self.customPlayerView =
      [[FnCustomPlayerView alloc] initWithPlayer:self.player
                                   dismissTarget:self
                                          action:@selector(dismiss)];
  self.customPlayerView.frame = self.playerContainer.bounds;
  self.customPlayerView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.playerContainer addSubview:self.customPlayerView];

  // D. Buffering Spinner
  self.bufferingSpinner = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
  self.bufferingSpinner.color = [UIColor whiteColor];
  self.bufferingSpinner.center =
      CGPointMake(self.playerContainer.bounds.size.width / 2,
                  self.playerContainer.bounds.size.height / 2);
  self.bufferingSpinner.autoresizingMask =
      UIViewAutoresizingFlexibleTopMargin |
      UIViewAutoresizingFlexibleBottomMargin |
      UIViewAutoresizingFlexibleLeftMargin |
      UIViewAutoresizingFlexibleRightMargin;
  self.bufferingSpinner.hidesWhenStopped = YES;
  [self.playerContainer addSubview:self.bufferingSpinner];

  // Observer
  [self.player addObserver:self
                forKeyPath:@"timeControlStatus"
                   options:NSKeyValueObservingOptionNew
                   context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (object == self.player && [keyPath isEqualToString:@"timeControlStatus"]) {
    if (self.player.timeControlStatus ==
        AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
      // Debounce: only show spinner if still buffering after 0.5 s.
      // This prevents the 1-frame flash on startup when AVPlayer briefly
      // passes through WaitingToPlay before the first frame is decoded.
      dispatch_after(
          dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
          dispatch_get_main_queue(), ^{
            if (self.player.timeControlStatus ==
                AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
              [self.bufferingSpinner startAnimating];
              [self.playerContainer bringSubviewToFront:self.bufferingSpinner];
            }
          });
    } else {
      // Stop immediately — no delay when buffering actually ends
      [self.bufferingSpinner stopAnimating];
    }
  }
}

- (void)dismiss {
  [self dismissAnimated:YES];
}

- (void)dismissAnimated:(BOOL)animated {
  [self.player pause];
  [self.player replaceCurrentItemWithPlayerItem:nil];

  UIView *wrapper = objc_getAssociatedObject(self.playerContainer, "shadowWrapper");
  UIView *animTarget = wrapper ?: self.playerContainer;

  if (animated) {
    [UIView animateWithDuration:0.25
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.2
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                       animTarget.transform = CGAffineTransformMakeScale(0.88, 0.88);
                       animTarget.alpha = 0.0;
                     }
                     completion:^(BOOL finished) {
                       self.videoWindow.hidden = YES;
                       animTarget.transform = CGAffineTransformIdentity;
                       animTarget.alpha = 1.0;
                     }];
  } else {
    self.videoWindow.hidden = YES;
  }
}

// ── Drag to move ──────────────────────────────────────────────────────────────
- (void)handleDrag:(UIPanGestureRecognizer *)gr {
  UIView *container = self.playerContainer;
  UIView *wrapper = objc_getAssociatedObject(container, "shadowWrapper");
  UIView *parent = wrapper ? wrapper.superview : container.superview;
  UIView *moving = wrapper ?: container;
  if (!parent) return;

  CGPoint delta = [gr translationInView:parent];
  CGRect f = moving.frame;
  f.origin.x += delta.x;
  f.origin.y += delta.y;

  CGRect sb = parent.bounds;
  f.origin.x = MAX(0, MIN(sb.size.width  - f.size.width,  f.origin.x));
  f.origin.y = MAX(0, MIN(sb.size.height - f.size.height, f.origin.y));

  moving.frame = f;
  [gr setTranslation:CGPointZero inView:parent];
}

// ── Resize handle setup ───────────────────────────────────────────────────────
- (void)addResizeHandlesToContainer:(UIView *)container {
  NSArray *configs = @[
    @[@1,  @"resizeUpDownCursor"],
    @[@2,  @"resizeUpDownCursor"],
    @[@4,  @"resizeLeftRightCursor"],
    @[@8,  @"resizeLeftRightCursor"],
    @[@5,  @"_windowResizeNorthWestSouthEastCursor"],
    @[@9,  @"_windowResizeNorthEastSouthWestCursor"],
    @[@6,  @"_windowResizeNorthEastSouthWestCursor"],
    @[@10, @"_windowResizeNorthWestSouthEastCursor"],
  ];
  for (NSArray *cfg in configs) {
    UIView *handle = [[UIView alloc] initWithFrame:CGRectZero];
    handle.backgroundColor = [UIColor clearColor];
    handle.tag = [cfg[0] integerValue];
    objc_setAssociatedObject(handle, "nsCursorSel", cfg[1],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIPanGestureRecognizer *rp = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleResize:)];
    [handle addGestureRecognizer:rp];
    if (@available(iOS 13.4, *)) {
      UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc]
          initWithTarget:self action:@selector(handleResizeHandleHover:)];
      [handle addGestureRecognizer:hover];
    }
    [container addSubview:handle];
  }
  [self layoutResizeHandles:container];
}

- (void)pushNSCursor:(NSString *)selName {
  Class cls = NSClassFromString(@"NSCursor");
  if (!cls) return;
  SEL getSel = NSSelectorFromString(selName);
  IMP getImp = [cls methodForSelector:getSel];
  if (!getImp) return;
  id cursor = ((id (*)(id, SEL))getImp)(cls, getSel);
  if (!cursor) return;
  SEL pushSel = NSSelectorFromString(@"push");
  IMP pushImp = [cursor methodForSelector:pushSel];
  if (pushImp) ((void (*)(id, SEL))pushImp)(cursor, pushSel);
}

- (void)popNSCursor {
  Class cls = NSClassFromString(@"NSCursor");
  if (!cls) return;
  SEL popSel = NSSelectorFromString(@"pop");
  IMP popImp = [cls methodForSelector:popSel];
  if (popImp) ((void (*)(id, SEL))popImp)(cls, popSel);
}

- (void)handleResizeHandleHover:(UIHoverGestureRecognizer *)hover
    API_AVAILABLE(ios(13.4)) {
  UIView *handle = hover.view;
  NSString *cursorSel = objc_getAssociatedObject(handle, "nsCursorSel");
  if (hover.state == UIGestureRecognizerStateBegan) {
    [self pushNSCursor:cursorSel];
  } else if (hover.state == UIGestureRecognizerStateEnded ||
             hover.state == UIGestureRecognizerStateCancelled) {
    [self popNSCursor];
  }
}

- (void)layoutResizeHandles:(UIView *)container {
  CGFloat e = 16.0;
  CGFloat w = container.bounds.size.width;
  CGFloat h = container.bounds.size.height;
  for (UIView *handle in container.subviews) {
    if (handle.tag == 0) continue;
    NSInteger t = handle.tag;
    BOOL top    = (t & 1) != 0;
    BOOL bottom = (t & 2) != 0;
    BOOL left   = (t & 4) != 0;
    BOOL right  = (t & 8) != 0;
    CGFloat x  = left ? 0 : (right ? w - e : e);
    CGFloat y  = top  ? 0 : (bottom ? h - e : e);
    CGFloat fw = (left || right) ? e : w - e * 2;
    CGFloat fh = (top || bottom) ? e : h - e * 2;
    handle.frame = CGRectMake(x, y, fw, fh);
  }
}

- (void)handleResize:(UIPanGestureRecognizer *)gr {
  UIView *handle  = (UIView *)gr.view;
  UIView *wrapper = handle.superview;
  UIView *parent  = wrapper.superview;
  if (!parent) return;

  static CGRect startFrame;
  if (gr.state == UIGestureRecognizerStateBegan) {
    startFrame = wrapper.frame;
    return;
  }

  CGPoint delta = [gr translationInView:parent];
  CGRect f = startFrame;
  NSInteger t = handle.tag;
  BOOL top    = (t & 1) != 0;
  BOOL bottom = (t & 2) != 0;
  BOOL left   = (t & 4) != 0;
  BOOL right  = (t & 8) != 0;

  static const CGFloat kAspect = 16.0 / 9.0;
  if (left || right) {
    if (left)  { f.origin.x += delta.x; f.size.width  -= delta.x; }
    if (right) { f.size.width  += delta.x; }
    f.size.height = f.size.width / kAspect;
    if (top) f.origin.y = startFrame.origin.y + startFrame.size.height - f.size.height;
  } else {
    if (top)    { f.origin.y += delta.y; f.size.height -= delta.y; }
    if (bottom) { f.size.height += delta.y; }
    f.size.width = f.size.height * kAspect;
    if (left) f.origin.x = startFrame.origin.x + startFrame.size.width - f.size.width;
  }

  CGFloat minW = 400, minH = 225;
  if (f.size.width  < minW) { f.size.width  = minW; f.size.height = minW / kAspect; }
  if (f.size.height < minH) { f.size.height = minH; f.size.width  = minH * kAspect; }

  CGRect sb = parent.bounds;
  f.origin.x = MAX(0, MIN(sb.size.width  - f.size.width,  f.origin.x));
  f.origin.y = MAX(0, MIN(sb.size.height - f.size.height, f.origin.y));

  wrapper.frame = f;
  wrapper.layer.shadowPath =
      [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, f.size.width, f.size.height)
                                 cornerRadius:12].CGPath;
  self.playerContainer.frame = CGRectMake(0, 0, f.size.width, f.size.height);
  [self layoutResizeHandles:wrapper];

  FnCustomPlayerView *pv = (FnCustomPlayerView *)self.customPlayerView;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  pv.playerLayer.frame = pv.bounds;
  [CATransaction commit];
  [pv setNeedsLayout];
  [pv layoutIfNeeded];
}

@end

// ─────────────────────────────────────────────────────────────────
//  FnVideoCardView — Dashboard Card
//  Streams video and launches the FnVideoPlayerPopup.
// ─────────────────────────────────────────────────────────────────

static NSString *const kFnVideoAssetURL =
    @"https://github.com/KohlerVG/FnMacTweak/releases/download/v2-assets/"
    @"Quick.Start.Video.mp4";

@interface FnVideoCardView : UIView
@property(nonatomic, strong) UIView *thumbnailContainer;
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) UIImageView *thumbnailView;
@end

@implementation FnVideoCardView

- (void)pausePlayback {
  [[FnVideoPlayerPopup shared] dismiss];
}

- (void)generateThumbnail:(NSURL *)url {
  // Always fetch fresh from the remote URL — no disk cache — so that when the
  // video asset is updated at the same URL path the thumbnail stays in sync.
  NSDictionary *opts = @{AVURLAssetPreferPreciseDurationAndTimingKey : @NO};
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:opts];
  AVAssetImageGenerator *gen =
      [[AVAssetImageGenerator alloc] initWithAsset:asset];
  gen.appliesPreferredTrackTransform = YES;
  // Wide tolerance lets AVFoundation grab the nearest keyframe from the first
  // bytes of the response — much faster than forcing frame-exact at t=0.
  gen.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(3.0, 600);
  gen.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(3.0, 600);

  [gen generateCGImageAsynchronouslyForTime:kCMTimeZero
                          completionHandler:^(CGImageRef _Nullable image,
                                              CMTime actualTime,
                                              NSError *_Nullable error) {
                            if (image) {
                              UIImage *thumb = [UIImage imageWithCGImage:image];
                              dispatch_async(dispatch_get_main_queue(), ^{
                                self.thumbnailView.image = thumb;
                                self.thumbnailView.hidden = NO;
                              });
                            } else {
                              // Thumbnail generation failed — keep black background
                            }
                          }];
}

- (instancetype)initWithTitle:(NSString *)title
                  description:(NSString *)desc
                        width:(CGFloat)w {
  // Simplified Init - Same height calc for consistency
  CGFloat pad = 12.0;
  CGFloat inner = w - pad * 2;
  CGFloat videoH = inner * 9.0 / 16.0;
  CGFloat gap = 6.0;

  UILabel *tmp = [[UILabel alloc] init];
  tmp.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  tmp.numberOfLines = 0;
  tmp.text = desc;
  CGFloat descH = [tmp sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height;
  CGFloat totalH = pad + 16 + gap + descH + gap + videoH + pad;

  self = [super initWithFrame:CGRectMake(0, 0, w, totalH)];
  if (!self)
    return nil;

  self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
  self.layer.cornerRadius = 10;
  self.layer.borderWidth = 0.5;
  self.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;

  // Title & Desc labels (Same as before)
  CGFloat y = pad;
  UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, inner, 16)];
  tl.text = title;
  tl.textColor = [UIColor whiteColor];
  tl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  [self addSubview:tl];
  y += 16 + gap;

  UILabel *dl =
      [[UILabel alloc] initWithFrame:CGRectMake(pad, y, inner, descH)];
  dl.text = desc;
  dl.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  dl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  dl.numberOfLines = 0;
  [self addSubview:dl];
  y += descH + gap;

  // Placeholder Container
  self.thumbnailContainer =
      [[UIView alloc] initWithFrame:CGRectMake(pad, y, inner, videoH)];
  self.thumbnailContainer.backgroundColor = [UIColor blackColor];
  self.thumbnailContainer.layer.cornerRadius = 6;
  self.thumbnailContainer.layer.masksToBounds = YES;
  [self addSubview:self.thumbnailContainer];

  // Thumbnail View
  self.thumbnailView =
      [[UIImageView alloc] initWithFrame:self.thumbnailContainer.bounds];
  self.thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
  self.thumbnailView.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.thumbnailView.hidden = YES;
  [self.thumbnailContainer addSubview:self.thumbnailView];

  // Play Button (Large, Centered)
  // UIButtonTypeCustom — we drive highlight ourselves so there's no sluggish
  // system fade; a fast CABasicAnimation gives instant, crisp feedback.
  self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.playButton.frame = CGRectMake(0, 0, 80, 80);
  self.playButton.center = CGPointMake(inner / 2, videoH / 2);
  self.playButton.tintColor = [UIColor whiteColor];
  UIImageSymbolConfiguration *playCfg = [UIImageSymbolConfiguration
      configurationWithPointSize:80
                          weight:UIImageSymbolWeightRegular];
  UIImage *playImg = [UIImage systemImageNamed:@"play.circle.fill"
                             withConfiguration:playCfg];
  [self.playButton setImage:playImg forState:UIControlStateNormal];
  self.playButton.contentVerticalAlignment =
      UIControlContentVerticalAlignmentFill;
  self.playButton.contentHorizontalAlignment =
      UIControlContentHorizontalAlignmentFill;
  // UIButtonTypeCustom already disables the system highlight — no need to set
  // adjustsImageWhenHighlighted
  [self.playButton addTarget:self
                      action:@selector(launchPopup)
            forControlEvents:UIControlEventTouchUpInside];
  [self.playButton
             addTarget:self
                action:@selector(playBtnDown)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
  [self.playButton
             addTarget:self
                action:@selector(playBtnUp)
      forControlEvents:UIControlEventTouchUpInside |
                       UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
  self.playButton.hidden = NO;
  [self.thumbnailContainer addSubview:self.playButton];

  // Loading thumbnail
  [self generateThumbnail:[NSURL URLWithString:kFnVideoAssetURL]];

  return self;
}

- (void)playBtnDown {
  CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
  a.toValue = @0.45;
  a.duration = 0.08;
  a.fillMode = kCAFillModeForwards;
  a.removedOnCompletion = NO;
  a.timingFunction =
      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
  [self.playButton.layer addAnimation:a forKey:@"playPress"];
  self.playButton.layer.opacity = 0.45;
}

- (void)playBtnUp {
  [self.playButton.layer removeAnimationForKey:@"playPress"];
  CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
  a.fromValue = @(self.playButton.layer.presentationLayer.opacity);
  a.toValue = @1.0;
  a.duration = 0.14;
  a.timingFunction =
      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
  a.removedOnCompletion = YES;
  [self.playButton.layer addAnimation:a forKey:@"playRelease"];
  self.playButton.layer.opacity = 1.0;
}

- (void)launchPopup {
  // Stream directly from remote URL.
  // Walk up the superview chain to find the containing UIWindow.
  UIWindow *gameWindow = nil;
  UIView *v = self;
  while (v && ![v isKindOfClass:[UIWindow class]])
    v = v.superview;
  gameWindow = (UIWindow *)v;

  NSURL *remoteURL = [NSURL URLWithString:kFnVideoAssetURL];
  [[FnVideoPlayerPopup shared] presentWithURL:remoteURL inWindow:gameWindow];
}

@end

// Load settings from persistent storage
static void loadSettings() {
  NSDictionary *settings =
      [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSettingsKey];
  if (settings) {
    BASE_XY_SENSITIVITY = [settings[kBaseXYKey] floatValue] ?: 6.4f;
    LOOK_SENSITIVITY_X = [settings[kLookXKey] floatValue] ?: 50.0f;
    LOOK_SENSITIVITY_Y = [settings[kLookYKey] floatValue] ?: 50.0f;
    SCOPE_SENSITIVITY_X = [settings[kScopeXKey] floatValue] ?: 50.0f;
    SCOPE_SENSITIVITY_Y = [settings[kScopeYKey] floatValue] ?: 50.0f;
    MACOS_TO_PC_SCALE = [settings[kScaleKey] floatValue] ?: 20.0f;

    // CRITICAL: Recalculate pre-computed sensitivities after loading
    recalculateSensitivities();
  }

  // Load key remappings
  loadKeyRemappings();
}

// Helper to get readable key name
static NSString *getKeyName(GCKeyCode keyCode) {
  // Check for mouse buttons first (our custom codes)
  if (keyCode == MOUSE_BUTTON_MIDDLE)
    return @"🖱️ Middle";
  if (keyCode == MOUSE_BUTTON_SIDE1)
    return @"🖱️ Side 1";
  if (keyCode == MOUSE_BUTTON_SIDE2)
    return @"🖱️ Side 2";
  if (keyCode == MOUSE_SCROLL_UP)
    return @"🖱️ Scroll ↑";
  if (keyCode == MOUSE_SCROLL_DOWN)
    return @"🖱️ Scroll ↓";

  // Letter keys A–Z (USB HID: A=4 … Z=29)
  if (keyCode >= 4 && keyCode <= 29) {
    char letter = 'A' + (keyCode - 4);
    return [NSString stringWithFormat:@"%c", letter];
  }

  // Number row 1–9, 0 (USB HID: 1=30 … 9=38, 0=39)
  if (keyCode >= 30 && keyCode <= 39) {
    return [NSString
        stringWithFormat:@"%ld", keyCode == 39 ? 0L : (long)(keyCode - 29)];
  }

  // Function keys F1–F12 (USB HID: F1=58 … F12=69)
  if (keyCode >= 58 && keyCode <= 69) {
    return [NSString stringWithFormat:@"F%ld", (long)(keyCode - 57)];
  }

  // Keypad numbers (static dict — allocated once)
  static NSDictionary *keyNames = nil;
  if (!keyNames) {
    keyNames = @{
      // Keypad
      @(89) : @"Num 1",
      @(90) : @"Num 2",
      @(91) : @"Num 3",
      @(92) : @"Num 4",
      @(93) : @"Num 5",
      @(94) : @"Num 6",
      @(95) : @"Num 7",
      @(96) : @"Num 8",
      @(97) : @"Num 9",
      @(98) : @"Num 0",
      // Special keys
      @(44) : @"Space",
      @(225) : @"L Shift",
      @(229) : @"R Shift",
      @(224) : @"L Ctrl",
      @(228) : @"R Ctrl",
      @(226) : @"L Alt",
      @(230) : @"R Alt",
      @(43) : @"Tab",
      @(40) : @"Enter",
      @(41) : @"Esc",
      @(42) : @"Backspace",
      @(57) : @"Caps",
      @(80) : @"←",
      @(79) : @"→",
      @(82) : @"↑",
      @(81) : @"↓",
      @(53) : @"`",
      @(45) : @"-",
      @(46) : @"=",
      @(47) : @"[",
      @(48) : @"]",
      @(49) : @"\\",
      @(51) : @";",
      @(52) : @"'",
      @(54) : @",",
      @(55) : @".",
      @(56) : @"/",
    };
  }

  NSString *name = keyNames[@(keyCode)];
  if (name)
    return name;

  return [NSString stringWithFormat:@"?%ld", (long)keyCode];
}

@interface popupViewController ()
// Sensitivity tab fields
@property UITextField *baseXYField;
@property UITextField *lookXField;
@property UITextField *lookYField;
@property UITextField *scopeXField;
@property UITextField *scopeYField;
@property UITextField *scaleField;
@property UILabel *feedbackLabel;
@property UIScrollView *scrollView;

// Track original sensitivity values for unsaved changes detection
@property float originalBaseXY;
@property float originalLookX;
@property float originalLookY;
@property float originalScopeX;
@property float originalScopeY;
@property float originalScale;

// Key remapping fields
@property NSMutableArray *keyRemapRows;
@property UIButton *addRemapButton;
@property UIButton *currentCapturingButton;
@property GCKeyCode currentCapturingSourceKey;
@property BOOL isCapturingKey;

// Content size tracking
@property CGFloat sensitivityContentHeight;
@property CGFloat keyRemapContentHeight;
@property CGFloat quickStartContentHeight;

// Drag tracking
@property CGPoint dragStartPoint;

// Close button
@property UIButton *closeButton;
@property UIView *closeX; // Can be UILabel or UIImageView

// Cached Fortnite actions for performance
@property(nonatomic, strong) NSArray *cachedFortniteActions;
@property(nonatomic, strong) NSDictionary *actionToDefaultKeyMap;

// Export/Import tracking
@property(nonatomic, strong) NSData *exportData;
@property(nonatomic, strong) NSString *exportFileName;

- (void)saveButtonTapped:(UIButton *)sender;
- (void)applyDefaultsTapped:(UIButton *)sender;
- (void)switchToTab:(PopupTab)tab;
@end

@implementation popupViewController

// Never lock the pointer to the settings panel window.
- (BOOL)prefersPointerLocked {
  return NO;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  loadSettings();

  self.keyRemapRows = [NSMutableArray array];
  self.isCapturingKey = NO;

  // Initialize staged keybinds dictionary
  self.stagedKeybinds = [NSMutableDictionary dictionary];

  // Capture original sensitivity values for unsaved changes detection
  self.originalBaseXY = BASE_XY_SENSITIVITY;
  self.originalLookX = LOOK_SENSITIVITY_X;
  self.originalLookY = LOOK_SENSITIVITY_Y;
  self.originalScopeX = SCOPE_SENSITIVITY_X;
  self.originalScopeY = SCOPE_SENSITIVITY_Y;
  self.originalScale = MACOS_TO_PC_SCALE;

  // Cache Fortnite actions array for performance (created once, reused many
  // times)
  self.cachedFortniteActions = @[
    @{@"action" : @"Forward", @"default" : @(26)},
    @{@"action" : @"Left", @"default" : @(4)},
    @{@"action" : @"Backward", @"default" : @(22)},
    @{@"action" : @"Right", @"default" : @(7)},
    @{@"action" : @"Sprint", @"default" : @(225)},
    @{@"action" : @"Crouch", @"default" : @(224)},
    @{@"action" : @"Auto Walk", @"default" : @(46)},
    @{@"action" : @"Harvesting Tool", @"default" : @(9)},
    @{@"action" : @"Use", @"default" : @(8)},
    @{@"action" : @"Reload", @"default" : @(21)},
    @{@"action" : @"Weapon Slot 1", @"default" : @(30)},
    @{@"action" : @"Weapon Slot 2", @"default" : @(31)},
    @{@"action" : @"Weapon Slot 3", @"default" : @(32)},
    @{@"action" : @"Weapon Slot 4", @"default" : @(33)},
    @{@"action" : @"Weapon Slot 5", @"default" : @(34)},
    @{@"action" : @"Build", @"default" : @(20)},
    @{@"action" : @"Edit", @"default" : @(10)},
    @{@"action" : @"Wall", @"default" : @(29)},
    @{@"action" : @"Floor", @"default" : @(27)},
    @{@"action" : @"Stairs", @"default" : @(6)},
    @{@"action" : @"Roof", @"default" : @(25)},
    @{@"action" : @"Inventory Toggle", @"default" : @(230)},
    @{@"action" : @"Emote", @"default" : @(5)},
    @{@"action" : @"Chat", @"default" : @(40)},
    @{@"action" : @"Push To Talk", @"default" : @(23)},
    @{@"action" : @"Shake Head", @"default" : @(11)},
    @{@"action" : @"Map", @"default" : @(16)}
  ];

  // Create lookup map: action name -> default key (O(1) lookups instead of O(n)
  // loops)
  NSMutableDictionary *tempMap = [NSMutableDictionary dictionary];
  for (NSDictionary *actionInfo in self.cachedFortniteActions) {
    tempMap[actionInfo[@"action"]] = actionInfo[@"default"];
  }
  self.actionToDefaultKeyMap = [tempMap copy];

  // macOS Tahoe-style background - solid dark with clean border
  // Set background color
  self.view.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];

  // Set corner radius and border to match macOS windows exactly
  self.view.layer.cornerRadius = 12; // macOS windows use 12px corner radius
  self.view.layer.borderWidth = 0.5; // Thinner border like macOS
  self.view.layer.borderColor =
      [UIColor colorWithWhite:0.25 alpha:0.8].CGColor; // Darker border
  self.view.layer.masksToBounds = YES;

  // ========================================
  // WINDOW TITLE BAR (macOS style)
  // ========================================
  UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 40)];
  titleBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.15];
  [self.view addSubview:titleBar];

  // Window title
  UILabel *titleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(60, 0, 210, 40)];
  titleLabel.text = @"FnMacTweak";
  titleLabel.textColor = [UIColor whiteColor];
  titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  titleLabel.textAlignment = NSTextAlignmentCenter;
  [titleBar addSubview:titleLabel];

  // macOS-style close button (red dot) - X shows on hover
  self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.closeButton.frame = CGRectMake(12, 12, 16, 16);
  self.closeButton.backgroundColor = [UIColor colorWithRed:1.0
                                                     green:0.23
                                                      blue:0.19
                                                     alpha:1.0];
  self.closeButton.layer.cornerRadius = 8;
  self.closeButton.layer.borderWidth = 0.5;
  self.closeButton.layer.borderColor =
      [UIColor colorWithRed:0.25 green:0.0 blue:0.0 alpha:1.0].CGColor;
  [self.closeButton addTarget:self
                       action:@selector(closeButtonTapped)
             forControlEvents:UIControlEventTouchUpInside];

  // Add X symbol - hidden by default, shows on hover like macOS
  // Use SF Symbol for the official macOS X icon
  UIImageSymbolConfiguration *xConfig = [UIImageSymbolConfiguration
      configurationWithPointSize:9
                          weight:UIImageSymbolWeightBlack];
  UIImage *xImage = [[UIImage systemImageNamed:@"xmark"]
      imageByApplyingSymbolConfiguration:xConfig];

  UIImageView *xImageView = [[UIImageView alloc] initWithImage:xImage];
  xImageView.frame = CGRectMake(0, 0, 16, 16);
  xImageView.contentMode = UIViewContentModeCenter;
  xImageView.tintColor =
      [UIColor colorWithRed:0.25
                      green:0.0
                       blue:0.0
                      alpha:1.0];      // Very dark red, almost black
  xImageView.alpha = 0;                // Hidden by default
  self.closeX = (UILabel *)xImageView; // Store as closeX for hover handling
  [self.closeButton addSubview:xImageView];

  // Add hover tracking
  UIHoverGestureRecognizer *hoverGesture = [[UIHoverGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(closeButtonHover:)];
  [self.closeButton addGestureRecognizer:hoverGesture];

  [titleBar addSubview:self.closeButton];

  // Add pan gesture for dragging window via title bar
  UIPanGestureRecognizer *panGesture =
      [[UIPanGestureRecognizer alloc] initWithTarget:self
                                              action:@selector(handlePan:)];
  [titleBar addGestureRecognizer:panGesture];

  // ========================================
  // TAB BAR (macOS segmented control style)
  // ========================================
  UIView *tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 40, 330, 50)];
  tabBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.1];
  [self.view addSubview:tabBar];

  // Create segmented control style container for tabs (expanded to fit 5 tabs)
  self.segmentedContainer =
      [[UIView alloc] initWithFrame:CGRectMake(18, 10, 294, 30)];
  self.segmentedContainer.backgroundColor = [UIColor colorWithWhite:0.15
                                                              alpha:0.6];
  self.segmentedContainer.layer.cornerRadius = 6;
  self.segmentedContainer.layer.borderWidth = 0.5;
  self.segmentedContainer.layer.borderColor =
      [UIColor colorWithWhite:0.3 alpha:0.3].CGColor;
  [tabBar addSubview:self.segmentedContainer];

  // Sliding indicator pill — sits behind the tab buttons, animates on tab
  // change
  self.tabIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 59, 30)];
  self.tabIndicator.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.8];
  self.tabIndicator.layer.cornerRadius = 6;
  [self.segmentedContainer addSubview:self.tabIndicator];

  // Sensitivity Tab Button
  self.sensitivityTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.sensitivityTabButton.frame = CGRectMake(0, 0, 59, 30);
  [self.sensitivityTabButton setTitle:@"🖱️" forState:UIControlStateNormal];
  self.sensitivityTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.sensitivityTabButton.layer.cornerRadius = 6;
  self.sensitivityTabButton.clipsToBounds = YES;
  self.sensitivityTabButton.backgroundColor = [UIColor clearColor];
  [self.sensitivityTabButton addTarget:self
                                action:@selector(sensitivityTabTapped)
                      forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.sensitivityTabButton];

  // Key Remap Tab Button
  self.keyRemapTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.keyRemapTabButton.frame = CGRectMake(59, 0, 59, 30);
  [self.keyRemapTabButton setTitle:@"⌨️" forState:UIControlStateNormal];
  self.keyRemapTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.keyRemapTabButton.layer.cornerRadius = 6;
  self.keyRemapTabButton.clipsToBounds = YES;
  self.keyRemapTabButton.backgroundColor = [UIColor clearColor];
  [self.keyRemapTabButton addTarget:self
                             action:@selector(keyRemapTabTapped)
                   forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.keyRemapTabButton];

  // BUILD Mode Tab Button (🔨 Hammer)
  self.buildModeTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.buildModeTabButton.frame = CGRectMake(118, 0, 58, 30);
  [self.buildModeTabButton setTitle:@"🔨" forState:UIControlStateNormal];
  self.buildModeTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.buildModeTabButton.layer.cornerRadius = 6;
  self.buildModeTabButton.clipsToBounds = YES;
  self.buildModeTabButton.backgroundColor = [UIColor clearColor];
  [self.buildModeTabButton addTarget:self
                              action:@selector(buildModeTabTapped)
                    forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.buildModeTabButton];

  // Container Tab Button (🔗 Link)
  self.containerTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.containerTabButton.frame = CGRectMake(176, 0, 59, 30);
  [self.containerTabButton setTitle:@"🔗" forState:UIControlStateNormal];
  self.containerTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.containerTabButton.layer.cornerRadius = 6;
  self.containerTabButton.clipsToBounds = YES;
  self.containerTabButton.backgroundColor = [UIColor clearColor];
  [self.containerTabButton addTarget:self
                              action:@selector(containerTabTapped)
                    forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.containerTabButton];

  // Quick Start Tab Button (❓)
  self.quickStartTabButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.quickStartTabButton.frame = CGRectMake(235, 0, 59, 30);
  [self.quickStartTabButton setTitle:@"❓" forState:UIControlStateNormal];
  self.quickStartTabButton.titleLabel.font = [UIFont systemFontOfSize:22];
  self.quickStartTabButton.layer.cornerRadius = 6;
  self.quickStartTabButton.clipsToBounds = YES;
  self.quickStartTabButton.backgroundColor = [UIColor clearColor];
  [self.quickStartTabButton addTarget:self
                               action:@selector(quickStartTabTapped)
                     forControlEvents:UIControlEventTouchUpInside];
  [self.segmentedContainer addSubview:self.quickStartTabButton];

  // ========================================
  // CONTENT AREA (SCROLLABLE)
  // ========================================
  self.scrollView =
      [[UIScrollView alloc] initWithFrame:CGRectMake(0, 90, 330, 510)];
  self.scrollView.backgroundColor = [UIColor clearColor];
  self.scrollView.showsVerticalScrollIndicator = YES;
  self.scrollView.bounces = YES;
  self.scrollView.alwaysBounceVertical = YES;
  self.scrollView.delaysContentTouches = NO;
  self.scrollView.canCancelContentTouches = YES;
  self.scrollView.userInteractionEnabled = YES;
  [self.view addSubview:self.scrollView];

  // ========================================
  // CREATE TAB VIEWS
  // ========================================
  [self createSensitivityTab];
  [self createKeyRemapTab];
  [self createBuildModeTab];
  [self createContainerTab];
  [self createQuickStartTab];

  // Default tab is set in viewDidAppear: so the scroll view is fully laid out
  // first
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  // Only set the default tab on first appearance
  if (self.currentTab == 0 && self.sensitivityTab.superview == nil) {
    [self switchToTab:PopupTabSensitivity];
  }
  // Ensure the red dot reflects the current Build Mode state whenever the popup appears
  updateRedDotVisibility();
}

// Public entry point called by Tweak.xm after opening the window
- (void)switchToQuickStartTab {
  [self switchToTab:PopupTabQuickStart];
}

- (void)createSensitivityTab {
  self.sensitivityTab =
      [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 600)];
  self.sensitivityTab.userInteractionEnabled = YES;
  self.sensitivityTab.clipsToBounds = NO;

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  // ========================================
  // HEADER
  // ========================================
  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Sensitivity Settings";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.sensitivityTab addSubview:title];
  y += 32;

  // Instruction banner
  UIView *instructionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 58)];
  instructionBanner.backgroundColor = [UIColor colorWithRed:0.2
                                                      green:0.4
                                                       blue:0.8
                                                      alpha:0.2];
  instructionBanner.layer.cornerRadius = 8;
  [self.sensitivityTab addSubview:instructionBanner];

  UILabel *instruction =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 38)];
  instruction.text = @"Match your PC Fortnite sensitivity\nAdjust values to "
                     @"feel like PC gameplay";
  instruction.textColor = [UIColor colorWithRed:0.6
                                          green:0.8
                                           blue:1.0
                                          alpha:1.0];
  instruction.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  instruction.textAlignment = NSTextAlignmentCenter;
  instruction.numberOfLines = 2;
  [instructionBanner addSubview:instruction];
  y += 74;

  // ========================================
  // ACTION BUTTONS (moved to top)
  // ========================================

  // Save Settings button
  UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
  saveButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  saveButton.backgroundColor = [UIColor colorWithRed:0.0
                                               green:0.47
                                                blue:1.0
                                               alpha:0.85];
  [saveButton setTitle:@"Apply Changes (0)" forState:UIControlStateNormal];
  [saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  saveButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                 weight:UIFontWeightSemibold];
  saveButton.layer.cornerRadius = 6;
  saveButton.layer.borderWidth = 0.5;
  saveButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  saveButton.layer.shadowColor =
      [UIColor colorWithRed:0.0 green:0.3 blue:0.8 alpha:1.0].CGColor;
  saveButton.layer.shadowOffset = CGSizeMake(0, 1);
  saveButton.layer.shadowOpacity = 0.2;
  saveButton.layer.shadowRadius = 1;
  saveButton.userInteractionEnabled = YES;
  saveButton.enabled = NO; // Disabled by default
  saveButton.alpha = 0.5;  // Greyed out when disabled
  self.applySensitivityButton =
      saveButton; // Store direct reference - no viewWithTag needed
  [saveButton addTarget:self
                 action:@selector(saveButtonTapped:)
       forControlEvents:UIControlEventTouchUpInside];
  [self.sensitivityTab addSubview:saveButton];
  y += 38;

  // Discard Changes button (yellow, below Save Settings)
  self.discardSensitivityButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.discardSensitivityButton.frame =
      CGRectMake(leftMargin, y, contentWidth, 32);
  self.discardSensitivityButton.backgroundColor = [UIColor colorWithRed:1.0
                                                                  green:0.9
                                                                   blue:0.3
                                                                  alpha:1.0];
  [self.discardSensitivityButton setTitle:@"Discard Changes (0)"
                                 forState:UIControlStateNormal];
  [self.discardSensitivityButton setTitleColor:[UIColor blackColor]
                                      forState:UIControlStateNormal];
  self.discardSensitivityButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.discardSensitivityButton.layer.cornerRadius = 6;
  self.discardSensitivityButton.layer.borderWidth = 0.5;
  self.discardSensitivityButton.layer.borderColor =
      [UIColor colorWithRed:0.9 green:0.8 blue:0.2 alpha:0.6].CGColor;
  self.discardSensitivityButton.layer.shadowColor =
      [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0].CGColor;
  self.discardSensitivityButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.discardSensitivityButton.layer.shadowOpacity = 0.2;
  self.discardSensitivityButton.layer.shadowRadius = 1;
  self.discardSensitivityButton.enabled = NO; // Disabled by default
  self.discardSensitivityButton.alpha = 0.3;  // Greyed out when disabled
  [self.discardSensitivityButton
             addTarget:self
                action:@selector(discardSensitivityChangesTapped)
      forControlEvents:UIControlEventTouchUpInside];
  [self.sensitivityTab addSubview:self.discardSensitivityButton];
  y += 38;

  // Reset All to Defaults button (matching keybinds tab styling)
  UIButton *resetAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetAllButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  resetAllButton.backgroundColor = [UIColor colorWithRed:0.6
                                                   green:0.2
                                                    blue:0.2
                                                   alpha:0.5];
  [resetAllButton setTitle:@"Reset All to Defaults"
                  forState:UIControlStateNormal];
  [resetAllButton setTitleColor:[UIColor colorWithRed:1.0
                                                green:0.7
                                                 blue:0.7
                                                alpha:1.0]
                       forState:UIControlStateNormal];
  resetAllButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  resetAllButton.layer.cornerRadius = 6;
  resetAllButton.layer.borderWidth = 0.5;
  resetAllButton.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  [resetAllButton addTarget:self
                     action:@selector(resetAllSensitivityTapped)
           forControlEvents:UIControlEventTouchUpInside];
  [self.sensitivityTab addSubview:resetAllButton];
  y += 50; // Extra spacing before sensitivity sections

  // ========================================
  // BASE SENSITIVITY SECTION
  // ========================================
  y = [self addSectionWithTitle:@"Base Sensitivity"
                       subtitle:@"X/Y-Axis Sensitivity (recommended: 6.4)"
                            atY:y
                         fields:@[ @{
                           @"label" : @"X/Y",
                           @"value" : @(BASE_XY_SENSITIVITY),
                           @"field" : @"baseXYField",
                           @"default" : @(6.4)
                         } ]
                       isDouble:NO
                         toView:self.sensitivityTab];

  // ========================================
  // HIP-FIRE SECTION
  // ========================================
  y = [self addSectionWithTitle:@"Hip-Fire (Look)"
                       subtitle:@"Targeting sensitivity when not aiming"
                            atY:y
                         fields:@[
                           @{
                             @"label" : @"X",
                             @"value" : @(LOOK_SENSITIVITY_X),
                             @"field" : @"lookXField",
                             @"default" : @(50.0)
                           },
                           @{
                             @"label" : @"Y",
                             @"value" : @(LOOK_SENSITIVITY_Y),
                             @"field" : @"lookYField",
                             @"default" : @(50.0)
                           }
                         ]
                       isDouble:YES
                         toView:self.sensitivityTab];

  // ========================================
  // ADS SECTION
  // ========================================
  y = [self addSectionWithTitle:@"ADS (Scope)"
                       subtitle:@"Sensitivity when aiming down sights"
                            atY:y
                         fields:@[
                           @{
                             @"label" : @"X",
                             @"value" : @(SCOPE_SENSITIVITY_X),
                             @"field" : @"scopeXField",
                             @"default" : @(50.0)
                           },
                           @{
                             @"label" : @"Y",
                             @"value" : @(SCOPE_SENSITIVITY_Y),
                             @"field" : @"scopeYField",
                             @"default" : @(50.0)
                           }
                         ]
                       isDouble:YES
                         toView:self.sensitivityTab];

  // ========================================
  // SCALE FACTOR SECTION (ADVANCED)
  // ========================================
  y += 8; // Extra top spacing above divider to match other tabs (8 + 8 from
          // section = 16pt total)
  [self addDividerAtY:y toView:self.sensitivityTab];
  y += 20;

  UILabel *advancedLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  advancedLabel.text = @"ADVANCED";
  advancedLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  advancedLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
  advancedLabel.textAlignment = NSTextAlignmentCenter;
  [self.sensitivityTab addSubview:advancedLabel];
  y += 28;

  // Mouse Conversion Scale section using the same style as Hip-Fire and ADS
  y = [self addSectionWithTitle:@"Mouse Conversion Scale"
                       subtitle:@"macOS to PC scale (Recommended: 20)"
                            atY:y
                         fields:@[ @{
                           @"label" : @"",
                           @"value" : @(MACOS_TO_PC_SCALE),
                           @"field" : @"scaleField",
                           @"default" : @(20.0)
                         } ]
                       isDouble:NO
                         toView:self.sensitivityTab];

  y += 20; // Bottom margin (matching left/right margins)

  // Feedback label (hidden, for legacy code compatibility)
  self.feedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
  self.feedbackLabel.font = [UIFont systemFontOfSize:13
                                              weight:UIFontWeightSemibold];
  self.feedbackLabel.alpha = 0;
  [self.sensitivityTab addSubview:self.feedbackLabel];

  // Save content height for scrolling
  self.sensitivityContentHeight = y;

  // Update the tab's frame to match the actual content height
  self.sensitivityTab.frame = CGRectMake(0, 0, 330, y);

  // Apply initial styling (white BG for non-default values)
  [self updateSensitivityFieldBorders];
}

- (void)createKeyRemapTab {
  self.keyRemapTab = [[UIView alloc]
      initWithFrame:CGRectMake(0, 0, 330,
                               2000)]; // Large initial height, will be resized

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  // Header
  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Key Bindings";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.keyRemapTab addSubview:title];
  y += 32;

  // Description banner (explains what keybinds tab does)
  UIView *descriptionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 58)];
  descriptionBanner.backgroundColor =
      [UIColor colorWithRed:0.2
                      green:0.6
                       blue:0.3
                      alpha:0.2]; // Green background
  descriptionBanner.layer.cornerRadius = 8;
  [self.keyRemapTab addSubview:descriptionBanner];

  UILabel *descriptionLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 38)];
  descriptionLabel.text =
      @"Customize Fortnite controls and create advanced key remaps";
  descriptionLabel.textColor = [UIColor colorWithRed:0.6
                                               green:1.0
                                                blue:0.7
                                               alpha:1.0]; // Light green text
  descriptionLabel.font = [UIFont systemFontOfSize:13
                                            weight:UIFontWeightMedium];
  descriptionLabel.textAlignment = NSTextAlignmentCenter;
  descriptionLabel.numberOfLines = 2;
  [descriptionBanner addSubview:descriptionLabel];
  y += 74; // Banner height + spacing (matching sensitivity tab)

  // Apply Changes button (always visible, grayed when count is 0)
  self.applyChangesButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.applyChangesButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  self.applyChangesButton.backgroundColor = [UIColor colorWithRed:0.0
                                                            green:0.47
                                                             blue:1.0
                                                            alpha:0.85];
  [self.applyChangesButton setTitle:@"Apply Changes (0)"
                           forState:UIControlStateNormal];
  [self.applyChangesButton setTitleColor:[UIColor whiteColor]
                                forState:UIControlStateNormal];
  self.applyChangesButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.applyChangesButton.layer.cornerRadius = 6;
  self.applyChangesButton.layer.borderWidth = 0.5;
  self.applyChangesButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  self.applyChangesButton.layer.shadowColor =
      [UIColor colorWithRed:0.0 green:0.3 blue:0.8 alpha:1.0].CGColor;
  self.applyChangesButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.applyChangesButton.layer.shadowOpacity = 0.2;
  self.applyChangesButton.layer.shadowRadius = 1;
  self.applyChangesButton.enabled = NO; // Disabled by default
  self.applyChangesButton.alpha = 0.5;  // Grayed out when disabled
  [self.applyChangesButton addTarget:self
                              action:@selector(applyKeybindChangesTapped)
                    forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:self.applyChangesButton];
  y += 38; // Button height + spacing (32 + 6)

  // Discard Changes button (yellow, below Apply Changes)
  self.discardKeybindsButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.discardKeybindsButton.frame =
      CGRectMake(leftMargin, y, contentWidth, 32);
  self.discardKeybindsButton.backgroundColor = [UIColor colorWithRed:1.0
                                                               green:0.9
                                                                blue:0.3
                                                               alpha:1.0];
  [self.discardKeybindsButton setTitle:@"Discard Changes (0)"
                              forState:UIControlStateNormal];
  [self.discardKeybindsButton setTitleColor:[UIColor blackColor]
                                   forState:UIControlStateNormal];
  self.discardKeybindsButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  self.discardKeybindsButton.layer.cornerRadius = 6;
  self.discardKeybindsButton.layer.borderWidth = 0.5;
  self.discardKeybindsButton.layer.borderColor =
      [UIColor colorWithRed:0.9 green:0.8 blue:0.2 alpha:0.6].CGColor;
  self.discardKeybindsButton.layer.shadowColor =
      [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:1.0].CGColor;
  self.discardKeybindsButton.layer.shadowOffset = CGSizeMake(0, 1);
  self.discardKeybindsButton.layer.shadowOpacity = 0.2;
  self.discardKeybindsButton.layer.shadowRadius = 1;
  self.discardKeybindsButton.enabled = NO; // Disabled by default
  self.discardKeybindsButton.alpha = 0.3;  // Greyed out when disabled
  [self.discardKeybindsButton addTarget:self
                                 action:@selector(discardKeybindChangesTapped)
                       forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:self.discardKeybindsButton];
  y += 38; // Button height + spacing (32 + 6)

  // Reset All button (below Discard Changes)
  UIButton *resetAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetAllButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  resetAllButton.backgroundColor = [UIColor colorWithRed:0.6
                                                   green:0.2
                                                    blue:0.2
                                                   alpha:0.5];
  [resetAllButton setTitle:@"Reset All to Defaults"
                  forState:UIControlStateNormal];
  [resetAllButton setTitleColor:[UIColor colorWithRed:1.0
                                                green:0.7
                                                 blue:0.7
                                                alpha:1.0]
                       forState:UIControlStateNormal];
  resetAllButton.titleLabel.font =
      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
  resetAllButton.layer.cornerRadius = 6;
  resetAllButton.layer.borderWidth = 0.5;
  resetAllButton.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  [resetAllButton addTarget:self
                     action:@selector(resetAllKeybindsTapped)
           forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:resetAllButton];
  y += 50; // Button height + extra spacing before keybinds (32 + 18)

  // Container for keybind rows (scrollable content)
  UIView *keybindsContainer =
      [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  keybindsContainer.tag = 9998; // Tag for fortnite keybinds container
  [self.keyRemapTab addSubview:keybindsContainer];

  // Create all Fortnite default keybind rows
  CGFloat rowY = 0;

  // Define all Fortnite default keybinds organized by category
  NSArray *keybindCategories = @[
    @{
      @"title" : @"MOVEMENT",
      @"binds" : @[
        @{@"action" : @"Forward", @"default" : @(26)},  // W
        @{@"action" : @"Left", @"default" : @(4)},      // A
        @{@"action" : @"Backward", @"default" : @(22)}, // S
        @{@"action" : @"Right", @"default" : @(7)},     // D
        @{@"action" : @"Sprint", @"default" : @(225)},  // L Shift
        @{@"action" : @"Crouch", @"default" : @(224)},  // L Ctrl
        @{@"action" : @"Auto Walk", @"default" : @(46)} // =
      ]
    },
    @{
      @"title" : @"COMBAT",
      @"binds" : @[
        @{@"action" : @"Harvesting Tool", @"default" : @(9)}, // F
        @{@"action" : @"Use", @"default" : @(8)},             // E
        @{@"action" : @"Reload", @"default" : @(21)},         // R
        @{@"action" : @"Weapon Slot 1", @"default" : @(30)},  // 1
        @{@"action" : @"Weapon Slot 2", @"default" : @(31)},  // 2
        @{@"action" : @"Weapon Slot 3", @"default" : @(32)},  // 3
        @{@"action" : @"Weapon Slot 4", @"default" : @(33)},  // 4
        @{@"action" : @"Weapon Slot 5", @"default" : @(34)}   // 5
      ]
    },
    @{
      @"title" : @"BUILDING",
      @"binds" : @[
        @{@"action" : @"Build", @"default" : @(20)}, // Q
        @{@"action" : @"Edit", @"default" : @(10)},  // G
        @{@"action" : @"Wall", @"default" : @(29)},  // Z
        @{@"action" : @"Floor", @"default" : @(27)}, // X
        @{@"action" : @"Stairs", @"default" : @(6)}, // C
        @{@"action" : @"Roof", @"default" : @(25)}   // V
      ]
    },
    @{
      @"title" : @"INVENTORY",
      @"binds" : @[
        @{@"action" : @"Inventory", @"default" : @(43)}, // Tab (now remappable)
        @{@"action" : @"Inventory Toggle", @"default" : @(230)} // R Alt
      ]
    },
    @{
      @"title" : @"COMMUNICATION",
      @"binds" : @[
        @{@"action" : @"Emote", @"default" : @(5)},         // B
        @{@"action" : @"Chat", @"default" : @(40)},         // Return
        @{@"action" : @"Push To Talk", @"default" : @(23)}, // T
        @{@"action" : @"Shake Head", @"default" : @(11)}    // H
      ]
    },
    @{
      @"title" : @"NAVIGATION",
      @"binds" : @[
        @{@"action" : @"Map", @"default" : @(16)} // M
      ]
    }
  ];

  // Create rows for each category
  for (NSDictionary *category in keybindCategories) {
    // Category header
    UILabel *categoryLabel =
        [[UILabel alloc] initWithFrame:CGRectMake(0, rowY, contentWidth, 20)];
    categoryLabel.text = category[@"title"];
    categoryLabel.textColor = [UIColor colorWithRed:0.5
                                              green:0.7
                                               blue:1.0
                                              alpha:1.0];
    categoryLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    categoryLabel.textAlignment = NSTextAlignmentLeft;
    [keybindsContainer addSubview:categoryLabel];
    rowY += 24;

    // Create rows for each keybind in this category
    for (NSDictionary *bind in category[@"binds"]) {
      UIView *row = [self
          createFortniteKeybindRowWithAction:bind[@"action"]
                                  defaultKey:[bind[@"default"] integerValue]
                                    readOnly:[bind[@"readonly"] boolValue]
                                         atY:rowY
                                       width:contentWidth];
      [keybindsContainer addSubview:row];
      rowY += 36;
    }

    rowY += 8; // Extra spacing between categories
  }

  // Resize container to fit all keybind rows
  CGRect containerFrame = keybindsContainer.frame;
  containerFrame.size.height = rowY;
  keybindsContainer.frame = containerFrame;
  y += rowY + 16;

  // Divider
  UIView *divider = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.keyRemapTab addSubview:divider];
  y += 20;

  // Advanced Custom Remaps section header
  UILabel *advancedLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  advancedLabel.text = @"Advanced Custom Remaps";
  advancedLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  advancedLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  advancedLabel.textAlignment = NSTextAlignmentCenter;
  [self.keyRemapTab addSubview:advancedLabel];
  y += 28;

  // Container for advanced custom remap rows
  UIView *remapContainer =
      [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  remapContainer.tag = 9999; // Tag for advanced custom remaps
  [self.keyRemapTab addSubview:remapContainer];

  // Load existing advanced custom remappings
  [self refreshKeyRemapRows];

  // Get actual height from container after refresh
  CGFloat containerHeight = remapContainer.frame.size.height;
  y += containerHeight + 16;

  // Add new advanced remap button
  self.addRemapButton = [UIButton buttonWithType:UIButtonTypeSystem];
  self.addRemapButton.frame = CGRectMake(leftMargin, y, contentWidth, 32);
  self.addRemapButton.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
  [self.addRemapButton setTitle:@"+ Add Custom Remap"
                       forState:UIControlStateNormal];
  [self.addRemapButton setTitleColor:[UIColor whiteColor]
                            forState:UIControlStateNormal];
  self.addRemapButton.titleLabel.font =
      [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  self.addRemapButton.layer.cornerRadius = 6;
  self.addRemapButton.layer.borderWidth = 0.5;
  self.addRemapButton.layer.borderColor =
      [UIColor colorWithWhite:0.4 alpha:0.4].CGColor;
  [self.addRemapButton addTarget:self
                          action:@selector(addKeyRemapTapped)
                forControlEvents:UIControlEventTouchUpInside];
  [self.keyRemapTab addSubview:self.addRemapButton];
  y += 32; // Button height

  // Feedback label (hidden, used by legacy code - keeping for compatibility but
  // minimal space)
  UILabel *keyRemapFeedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 0)];
  keyRemapFeedbackLabel.textAlignment = NSTextAlignmentCenter;
  keyRemapFeedbackLabel.font = [UIFont systemFontOfSize:13
                                                 weight:UIFontWeightSemibold];
  keyRemapFeedbackLabel.alpha = 0;
  keyRemapFeedbackLabel.tag = 8888;
  [self.keyRemapTab addSubview:keyRemapFeedbackLabel];
  y += 20; // Bottom margin (matching left/right margins)

  // Save initial content height for scrolling
  self.keyRemapContentHeight = y;

  // Recalculate to ensure everything is properly sized
  [self recalculateKeyRemapContentHeight];
}

// Create BUILD mode tab
- (void)createBuildModeTab {
  self.buildModeTab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 510)];
  self.buildModeTab.backgroundColor = [UIColor clearColor];

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  // ========================================
  // HEADER
  // ========================================
  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"BUILD Mode Settings";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.buildModeTab addSubview:title];
  y += 32;

  // Instruction banner (matching other tabs' style)
  UIView *instructionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 140)];
  instructionBanner.backgroundColor = [UIColor colorWithRed:0.8
                                                      green:0.4
                                                       blue:0.2
                                                      alpha:0.2];
  instructionBanner.layer.cornerRadius = 8;
  [self.buildModeTab addSubview:instructionBanner];

  UILabel *instruction =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 120)];
  instruction.text =
      @"Toggle between ZERO BUILD and BUILD\n\nAlign the RED DOT directly over "
      @"your centered ATTACK and EDIT BUILD buttons. Stacking them identically "
      @"at this single coordinate creates a universal touch-point for both "
      @"actions.";
  instruction.textColor = [UIColor colorWithRed:1.0
                                          green:0.8
                                           blue:0.6
                                          alpha:1.0];
  instruction.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  instruction.textAlignment = NSTextAlignmentCenter;
  instruction.numberOfLines = 0;
  instruction.lineBreakMode = NSLineBreakByWordWrapping;
  [instructionBanner addSubview:instruction];
  y += 156;

  // Two-button toggle (BUILD and ZERO BUILD side by side)
  CGFloat buttonY = y;
  CGFloat buttonPadding = 32; // Horizontal padding per side
  CGFloat buttonGap = 8;

  // Calculate button widths based on text
  UIFont *buttonFont = [UIFont systemFontOfSize:16 weight:UIFontWeightBlack];
  NSString *buildText = @"BUILD";
  NSString *zeroBuildText = @"ZERO BUILD";

  CGSize buildTextSize =
      [buildText sizeWithAttributes:@{NSFontAttributeName : buttonFont}];
  CGSize zeroBuildTextSize =
      [zeroBuildText sizeWithAttributes:@{NSFontAttributeName : buttonFont}];

  CGFloat buildButtonWidth = buildTextSize.width + (buttonPadding * 2);
  CGFloat zeroBuildButtonWidth = zeroBuildTextSize.width + (buttonPadding * 2);

  // Center both buttons together
  CGFloat totalWidth = buildButtonWidth + buttonGap + zeroBuildButtonWidth;
  CGFloat startX = leftMargin + (contentWidth - totalWidth) / 2.0;

  // BUILD button (left)
  UIButton *buildButton = [UIButton buttonWithType:UIButtonTypeSystem];
  buildButton.frame = CGRectMake(startX, buttonY, buildButtonWidth, 44);
  buildButton.backgroundColor = isBuildModeEnabled
                                    ? [UIColor colorWithRed:0.2
                                                      green:0.8
                                                       blue:0.3
                                                      alpha:1.0]
                                    : [UIColor colorWithWhite:0.3 alpha:0.6];
  [buildButton setTitle:buildText forState:UIControlStateNormal];
  [buildButton setTitleColor:isBuildModeEnabled ? [UIColor blackColor]
                                                : [UIColor colorWithWhite:0.6
                                                                    alpha:1.0]
                    forState:UIControlStateNormal];
  buildButton.titleLabel.font = buttonFont;
  buildButton.layer.cornerRadius = 6;
  buildButton.layer.borderWidth = 2;
  buildButton.layer.borderColor =
      isBuildModeEnabled
          ? [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:1.0].CGColor
          : [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
  buildButton.tag = 8888; // Tag to find it later
  [buildButton addTarget:self
                  action:@selector(selectBuildMode)
        forControlEvents:UIControlEventTouchUpInside];
  [self.buildModeTab addSubview:buildButton];

  // ZERO BUILD button (right)
  UIButton *zeroBuildButton = [UIButton buttonWithType:UIButtonTypeSystem];
  zeroBuildButton.frame = CGRectMake(startX + buildButtonWidth + buttonGap,
                                     buttonY, zeroBuildButtonWidth, 44);
  zeroBuildButton.backgroundColor =
      !isBuildModeEnabled
          ? [UIColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:1.0]
          : [UIColor colorWithWhite:0.3 alpha:0.6];
  [zeroBuildButton setTitle:zeroBuildText forState:UIControlStateNormal];
  [zeroBuildButton
      setTitleColor:!isBuildModeEnabled ? [UIColor blackColor]
                                        : [UIColor colorWithWhite:0.6 alpha:1.0]
           forState:UIControlStateNormal];
  zeroBuildButton.titleLabel.font = buttonFont;
  zeroBuildButton.layer.cornerRadius = 6;
  zeroBuildButton.layer.borderWidth = 2;
  zeroBuildButton.layer.borderColor =
      !isBuildModeEnabled
          ? [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:1.0].CGColor
          : [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
  zeroBuildButton.tag = 8889; // Tag to find it later
  [zeroBuildButton addTarget:self
                      action:@selector(selectZeroBuildMode)
            forControlEvents:UIControlEventTouchUpInside];
  [self.buildModeTab addSubview:zeroBuildButton];
  y += 60;

  // Divider
  UIView *divider = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.buildModeTab addSubview:divider];
  y += 20;

  // Red dot reset section
  UILabel *redDotLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  redDotLabel.text = @"Red Dot Target Position";
  redDotLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  redDotLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  redDotLabel.textAlignment = NSTextAlignmentCenter;
  [self.buildModeTab addSubview:redDotLabel];
  y += 28;

  // Reset button (macOS liquid glass style - subtle)
  UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetButton.frame = CGRectMake(leftMargin + 40, y, contentWidth - 80, 36);
  resetButton.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.6];
  [resetButton setTitle:@"Reset to Center" forState:UIControlStateNormal];
  [resetButton setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0]
                    forState:UIControlStateNormal];
  resetButton.titleLabel.font = [UIFont systemFontOfSize:12
                                                  weight:UIFontWeightMedium];
  resetButton.layer.cornerRadius = 6;
  resetButton.layer.borderWidth = 0.5;
  resetButton.layer.borderColor =
      [UIColor colorWithWhite:0.3 alpha:0.4].CGColor;
  [resetButton addTarget:self
                  action:@selector(resetRedDotTapped)
        forControlEvents:UIControlEventTouchUpInside];
  [self.buildModeTab addSubview:resetButton];
  y += 50;

  // Feedback label for build mode tab
  UILabel *buildFeedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  buildFeedbackLabel.textAlignment = NSTextAlignmentCenter;
  buildFeedbackLabel.font = [UIFont systemFontOfSize:13
                                              weight:UIFontWeightSemibold];
  buildFeedbackLabel.alpha = 0;
  buildFeedbackLabel.tag = 8890; // Unique tag for build mode feedback
  [self.buildModeTab addSubview:buildFeedbackLabel];
  y += 20; // Bottom margin (matching left/right margins)

  // Update the tab's frame to match the actual content height
  self.buildModeTab.frame = CGRectMake(0, 0, 330, y);

  // Update button and status based on current state
  [self updateBuildModeUI];
}

- (void)selectBuildMode {
  if (!isBuildModeEnabled) {
    isBuildModeEnabled = YES;
    [[NSUserDefaults standardUserDefaults] setBool:isBuildModeEnabled
                                            forKey:kBuildModeKey];
    [self updateBuildModeUI];
    updateRedDotVisibility();
  }
}

- (void)selectZeroBuildMode {
  if (isBuildModeEnabled) {
    isBuildModeEnabled = NO;
    [[NSUserDefaults standardUserDefaults] setBool:isBuildModeEnabled
                                            forKey:kBuildModeKey];
    [self updateBuildModeUI];
    updateRedDotVisibility();
  }
}

- (void)resetRedDotTapped {
  // Reset the red dot to center of screen
  resetRedDotPosition();

  // Show feedback
  [self showFeedback:@"Red Dot Reset to Center"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)updateBuildModeUI {
  // Find the buttons
  UIButton *buildButton = (UIButton *)[self.buildModeTab viewWithTag:8888];
  UIButton *zeroBuildButton = (UIButton *)[self.buildModeTab viewWithTag:8889];

  // Smooth animated transition
  [UIView
      animateWithDuration:0.25
                    delay:0
                  options:UIViewAnimationOptionCurveEaseInOut
               animations:^{
                 if (isBuildModeEnabled) {
                   // BUILD mode enabled
                   buildButton.backgroundColor = [UIColor colorWithRed:0.2
                                                                 green:0.8
                                                                  blue:0.3
                                                                 alpha:1.0];
                   [buildButton setTitleColor:[UIColor blackColor]
                                     forState:UIControlStateNormal];
                   buildButton.layer.borderColor = [UIColor colorWithRed:0.15
                                                                   green:0.6
                                                                    blue:0.25
                                                                   alpha:1.0]
                                                       .CGColor;

                   zeroBuildButton.backgroundColor =
                       [UIColor colorWithWhite:0.3 alpha:0.6];
                   [zeroBuildButton setTitleColor:[UIColor colorWithWhite:0.6
                                                                    alpha:1.0]
                                         forState:UIControlStateNormal];
                   zeroBuildButton.layer.borderColor =
                       [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;
                 } else {
                   // ZERO BUILD mode (default)
                   buildButton.backgroundColor = [UIColor colorWithWhite:0.3
                                                                   alpha:0.6];
                   [buildButton setTitleColor:[UIColor colorWithWhite:0.6
                                                                alpha:1.0]
                                     forState:UIControlStateNormal];
                   buildButton.layer.borderColor =
                       [UIColor colorWithWhite:0.25 alpha:0.6].CGColor;

                   zeroBuildButton.backgroundColor = [UIColor colorWithRed:0.2
                                                                     green:0.8
                                                                      blue:0.3
                                                                     alpha:1.0];
                   [zeroBuildButton setTitleColor:[UIColor blackColor]
                                         forState:UIControlStateNormal];
                   zeroBuildButton.layer.borderColor =
                       [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:1.0]
                           .CGColor;
                 }
               }
               completion:nil];
}

// Refresh the key remap rows display
- (void)refreshKeyRemapRows {
  UIView *container = [self.keyRemapTab viewWithTag:9999];
  if (!container)
    return;

  // Clear existing rows
  for (UIView *subview in container.subviews) {
    [subview removeFromSuperview];
  }
  [self.keyRemapRows removeAllObjects];

  CGFloat y = 0;
  CGFloat contentWidth = 290;

  // Create a row for each existing remapping
  for (NSNumber *sourceKey in keyRemappings) {
    NSNumber *targetKey = keyRemappings[sourceKey];

    UIView *row = [self createKeyRemapRowWithSourceKey:[sourceKey integerValue]
                                             targetKey:[targetKey integerValue]
                                                   atY:y
                                                 width:contentWidth];
    [container addSubview:row];
    [self.keyRemapRows addObject:row];
    y += 50;
  }

  // Resize container to fit content
  CGRect frame = container.frame;
  frame.size.height = y;
  container.frame = frame;

  // Reposition buttons below the container
  [self repositionKeyRemapButtons];
}

- (void)repositionKeyRemapButtons {
  UIView *container = [self.keyRemapTab viewWithTag:9999];
  if (!container)
    return;

  CGFloat y = container.frame.origin.y + container.frame.size.height + 16;

  // Reposition add button
  CGRect addFrame = self.addRemapButton.frame;
  addFrame.origin.y = y;
  self.addRemapButton.frame = addFrame;
  y += 46;

  // Reposition feedback label
  UILabel *feedbackLabel = [self.keyRemapTab viewWithTag:8888];
  if (feedbackLabel) {
    CGRect feedbackFrame = feedbackLabel.frame;
    feedbackFrame.origin.y = y;
    feedbackLabel.frame = feedbackFrame;
    y += 30;
  }

  // Recalculate total content height
  [self recalculateKeyRemapContentHeight];
}

// Create a single key remap row
- (UIView *)createKeyRemapRowWithSourceKey:(GCKeyCode)sourceKey
                                 targetKey:(GCKeyCode)targetKey
                                       atY:(CGFloat)y
                                     width:(CGFloat)width {
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, 44)];
  row.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  row.layer.cornerRadius = 8;
  row.layer.borderWidth = 0.5;
  row.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;

  // Source key button (macOS glass style - neutral)
  UIButton *sourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
  sourceButton.frame = CGRectMake(10, 7, 80, 30);
  sourceButton.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.7];
  [sourceButton setTitle:getKeyName(sourceKey) forState:UIControlStateNormal];
  [sourceButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  sourceButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightMedium];
  sourceButton.layer.cornerRadius = 5;
  sourceButton.layer.borderWidth = 0.5;
  sourceButton.layer.borderColor =
      [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
  sourceButton.tag = sourceKey;
  [sourceButton addTarget:self
                   action:@selector(changeSourceKeyTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:sourceButton];

  // Arrow label
  UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectMake(95, 7, 30, 30)];
  arrow.text = @"→";
  arrow.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  arrow.font = [UIFont systemFontOfSize:18 weight:UIFontWeightLight];
  arrow.textAlignment = NSTextAlignmentCenter;
  [row addSubview:arrow];

  // Target key button (macOS glass style - slightly lighter)
  UIButton *targetButton = [UIButton buttonWithType:UIButtonTypeSystem];
  targetButton.frame = CGRectMake(130, 7, 80, 30);
  targetButton.backgroundColor = [UIColor colorWithWhite:0.32 alpha:0.7];
  [targetButton setTitle:getKeyName(targetKey) forState:UIControlStateNormal];
  [targetButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  targetButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightMedium];
  targetButton.layer.cornerRadius = 5;
  targetButton.layer.borderWidth = 0.5;
  targetButton.layer.borderColor =
      [UIColor colorWithWhite:0.38 alpha:0.5].CGColor;
  targetButton.tag = sourceKey; // Store source key for lookup
  [targetButton addTarget:self
                   action:@selector(changeTargetKeyTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:targetButton];

  // Delete button (macOS glass style - subtle red tint)
  UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
  deleteButton.frame = CGRectMake(220, 7, 60, 30);
  deleteButton.backgroundColor = [UIColor colorWithRed:0.4
                                                 green:0.2
                                                  blue:0.2
                                                 alpha:0.6];
  [deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
  [deleteButton setTitleColor:[UIColor colorWithRed:1.0
                                              green:0.7
                                               blue:0.7
                                              alpha:1.0]
                     forState:UIControlStateNormal];
  deleteButton.titleLabel.font = [UIFont systemFontOfSize:12
                                                   weight:UIFontWeightMedium];
  deleteButton.layer.cornerRadius = 5;
  deleteButton.layer.borderWidth = 0.5;
  deleteButton.layer.borderColor =
      [UIColor colorWithRed:0.5 green:0.25 blue:0.25 alpha:0.5].CGColor;
  deleteButton.tag = sourceKey;
  [deleteButton addTarget:self
                   action:@selector(deleteKeyRemapTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:deleteButton];

  return row;
}

// Create a single Fortnite keybind row with color-coded status
- (UIView *)createFortniteKeybindRowWithAction:(NSString *)action
                                    defaultKey:(GCKeyCode)defaultKey
                                      readOnly:(BOOL)readOnly
                                           atY:(CGFloat)y
                                         width:(CGFloat)width {
  UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, 30)];

  // Reset button (arrow icon)
  UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
  resetButton.frame = CGRectMake(0, 5, 20, 20);
  [resetButton setTitle:@"↪️" forState:UIControlStateNormal];
  resetButton.titleLabel.font = [UIFont systemFontOfSize:14];
  resetButton.accessibilityLabel = action; // Store action name
  resetButton.tag = defaultKey;            // Store default key
  [resetButton addTarget:self
                  action:@selector(resetKeybindTapped:)
        forControlEvents:UIControlEventTouchUpInside];
  [row addSubview:resetButton];

  // Action name label
  UILabel *actionLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(24, 5, width - 140, 20)];
  actionLabel.text = action;
  actionLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
  actionLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  actionLabel.textAlignment = NSTextAlignmentLeft;
  [row addSubview:actionLabel];

  // Get current effective key for this action
  GCKeyCode currentKey = [self getCurrentKeyForAction:action
                                           defaultKey:defaultKey];
  BOOL isStaged = [self.stagedKeybinds objectForKey:action] != nil;
  BOOL isCustomSaved = [self isActionCustomSaved:action defaultKey:defaultKey];
  BOOL isUnbound = (currentKey == 0);

  // Key button with color-coded status
  UIButton *keyButton = [UIButton buttonWithType:UIButtonTypeSystem];
  keyButton.frame = CGRectMake(width - 110, 3, 110, 24);
  keyButton.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.7];
  keyButton.layer.cornerRadius = 4;
  keyButton.layer.borderWidth = 0.5;
  keyButton.accessibilityLabel = action; // Store action name for later
  keyButton.tag = defaultKey;            // Store default key
  keyButton.enabled = !readOnly;

  // Set button title and color based on status
  if (isUnbound) {
    // RED: Unbound
    [keyButton setTitle:@"[Unbound]" forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithRed:1.0
                                             green:0.3
                                              blue:0.3
                                             alpha:1.0]
                    forState:UIControlStateNormal];
    keyButton.layer.borderColor =
        [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.5].CGColor;
  } else if (isStaged) {
    // YELLOW: Staged change
    [keyButton setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithRed:1.0
                                             green:0.9
                                              blue:0.2
                                             alpha:1.0]
                    forState:UIControlStateNormal];
    keyButton.layer.borderColor =
        [UIColor colorWithRed:0.8 green:0.7 blue:0.0 alpha:0.5].CGColor;
  } else if (isCustomSaved) {
    // BLACK: Custom saved
    [keyButton setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithWhite:0.15 alpha:1.0]
                    forState:UIControlStateNormal];
    keyButton.backgroundColor =
        [UIColor colorWithWhite:0.9
                          alpha:1.0]; // Lighter background for black text
    keyButton.layer.borderColor =
        [UIColor colorWithWhite:0.6 alpha:0.5].CGColor;
  } else {
    // LIGHT GREY: Default
    [keyButton setTitle:getKeyName(currentKey) forState:UIControlStateNormal];
    [keyButton setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0]
                    forState:UIControlStateNormal];
    keyButton.layer.borderColor =
        [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
  }

  if (readOnly) {
    keyButton.alpha = 0.5; // Dim read-only buttons
  } else {
    [keyButton addTarget:self
                  action:@selector(fortniteKeybindTapped:)
        forControlEvents:UIControlEventTouchUpInside];
  }

  keyButton.titleLabel.font = [UIFont systemFontOfSize:12
                                                weight:UIFontWeightSemibold];
  [row addSubview:keyButton];

  return row;
}

// Get current effective key for an action (considering staged changes and saved
// bindings)
- (GCKeyCode)getCurrentKeyForAction:(NSString *)action
                         defaultKey:(GCKeyCode)defaultKey {
  // Check if there's a staged change first
  NSNumber *stagedKey = self.stagedKeybinds[action];
  if (stagedKey) {
    return [stagedKey integerValue];
  }

  // Check if there's a saved custom binding
  NSNumber *savedKey = [self getSavedKeyForAction:action];
  if (savedKey) {
    return [savedKey integerValue];
  }

  // Return default
  return defaultKey;
}

// Check if action has a custom saved binding (different from default)
- (BOOL)isActionCustomSaved:(NSString *)action
                 defaultKey:(GCKeyCode)defaultKey {
  NSNumber *savedKey = [self getSavedKeyForAction:action];
  if (!savedKey)
    return NO;
  return [savedKey integerValue] != defaultKey;
}

// Get saved custom key for an action (returns nil if using default)
- (NSNumber *)getSavedKeyForAction:(NSString *)action {
  // Load from UserDefaults - we store action -> key mappings
  NSDictionary *savedBindings = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"];
  return savedBindings[action];
}

// Handle Fortnite keybind button tap
- (void)fortniteKeybindTapped:(UIButton *)sender {
  NSString *actionName = sender.accessibilityLabel;

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Change Key Binding"
                       message:[NSString stringWithFormat:@"%@\nPress a key",
                                                          actionName]
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *_Nonnull action) {
                                 keyCaptureCallback = nil;
                               }]];

  [self
      presentViewController:alert
                   animated:YES
                 completion:^{
                   __weak typeof(self) weakSelf = self;

                   keyCaptureCallback = ^(GCKeyCode keyCode) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf)
                         return;

                       keyCaptureCallback = nil;
                       [strongSelf.presentedViewController
                           dismissViewControllerAnimated:YES
                                              completion:nil];

                       // Check for system keys
                       if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Key"
                                              message:@"Cannot use system keys "
                                                      @"(Alt, P)"
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       // Check for conflicts
                       NSString *conflictAction =
                           [strongSelf findActionUsingKey:keyCode
                                          excludingAction:actionName];
                       NSString *customRemapConflict =
                           [strongSelf findCustomRemapUsingKey:keyCode];

                       if (conflictAction || customRemapConflict) {
                         // Build conflict message without bullet points
                         NSMutableString *message = [NSMutableString string];

                         if (conflictAction && customRemapConflict) {
                           [message appendFormat:
                                        @"%@ is currently bound to %@ in "
                                        @"Fortnite Keybinds and is also used "
                                        @"in Advanced Custom Remaps (%@). This "
                                        @"will create conflicts. Continue?",
                                        getKeyName(keyCode), conflictAction,
                                        customRemapConflict];
                         } else if (conflictAction) {
                           [message
                               appendFormat:
                                   @"%@ is currently bound to %@. Remapping "
                                   @"will create a conflict. Continue?",
                                   getKeyName(keyCode), conflictAction];
                         } else {
                           [message
                               appendFormat:@"%@ is used in Advanced Custom "
                                            @"Remaps (%@). This will create a "
                                            @"conflict. Continue?",
                                            getKeyName(keyCode),
                                            customRemapConflict];
                         }

                         UIAlertController *conflictAlert = [UIAlertController
                             alertControllerWithTitle:@"Key Conflict"
                                              message:message
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];

                         [conflictAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
                         [conflictAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"Continue Anyway"
                                               style:
                                                   UIAlertActionStyleDestructive
                                             handler:^(
                                                 UIAlertAction
                                                     *_Nonnull alertAction) {
                                               // User confirmed - apply the
                                               // change
                                               [strongSelf
                                                   stageKeybindChange:actionName
                                                               newKey:keyCode];
                                               [strongSelf
                                                   refreshFortniteKeybinds];
                                             }]];

                         [strongSelf presentViewController:conflictAlert
                                                  animated:YES
                                                completion:nil];
                       } else {
                         // No conflict - apply directly
                         [strongSelf stageKeybindChange:actionName
                                                 newKey:keyCode];
                         [strongSelf refreshFortniteKeybinds];
                       }
                     });
                   };
                 }];
}

// Find which action is using a specific key (returns nil if none or if it's the
// excluded action)
- (NSString *)findActionUsingKey:(GCKeyCode)keyCode
                 excludingAction:(NSString *)excludeAction {
  // Get all Fortnite actions and their current keys
  NSArray *allActions = [self getAllFortniteActions];

  for (NSDictionary *actionInfo in allActions) {
    NSString *action = actionInfo[@"action"];
    if ([action isEqualToString:excludeAction])
      continue;

    GCKeyCode defaultKey = [actionInfo[@"default"] integerValue];
    GCKeyCode currentKey = [self getCurrentKeyForAction:action
                                             defaultKey:defaultKey];

    if (currentKey == keyCode) {
      return action;
    }
  }

  return nil;
}

// Find if a key is used in Advanced Custom Remaps (returns description or nil)
- (NSString *)findCustomRemapUsingKey:(GCKeyCode)keyCode {
  // Check if key is used as source in custom remaps
  NSNumber *targetKey = keyRemappings[@(keyCode)];
  if (targetKey) {
    return [NSString stringWithFormat:@"%@ → %@", getKeyName(keyCode),
                                      getKeyName([targetKey integerValue])];
  }

  // Check if key is used as target in custom remaps
  for (NSNumber *sourceKey in keyRemappings) {
    NSNumber *target = keyRemappings[sourceKey];
    if ([target integerValue] == keyCode) {
      return [NSString stringWithFormat:@"%@ → %@",
                                        getKeyName([sourceKey integerValue]),
                                        getKeyName(keyCode)];
    }
  }

  return nil;
}

// Find if a key is used in Fortnite keybinds (returns action name or nil)
- (NSString *)findFortniteActionUsingKey:(GCKeyCode)keyCode {
  NSArray *allActions = [self getAllFortniteActions];

  for (NSDictionary *actionInfo in allActions) {
    NSString *action = actionInfo[@"action"];
    GCKeyCode defaultKey = [actionInfo[@"default"] integerValue];
    GCKeyCode currentKey = [self getCurrentKeyForAction:action
                                             defaultKey:defaultKey];

    if (currentKey == keyCode) {
      return action;
    }
  }

  return nil;
}

// Get all Fortnite actions (cached for performance)
- (NSArray *)getAllFortniteActions {
  return self.cachedFortniteActions;
}

// Stage a keybind change (doesn't save yet)
- (void)stageKeybindChange:(NSString *)action newKey:(GCKeyCode)newKey {
  // If this change unbinds another action, stage that too
  NSString *conflictAction = [self findActionUsingKey:newKey
                                      excludingAction:action];
  if (conflictAction) {
    self.stagedKeybinds[conflictAction] = @(0); // Unbind the conflicting action
  }

  // Stage this change
  self.stagedKeybinds[action] = @(newKey);

  // Show/update Apply Changes button
  [self updateApplyChangesButton];
}

// Update the Apply Changes button enabled state and count
- (void)updateApplyChangesButton {
  NSInteger changeCount = self.stagedKeybinds.count;

  [self.applyChangesButton
      setTitle:[NSString
                   stringWithFormat:@"Apply Changes (%ld)", (long)changeCount]
      forState:UIControlStateNormal];
  [self.discardKeybindsButton
      setTitle:[NSString
                   stringWithFormat:@"Discard Changes (%ld)", (long)changeCount]
      forState:UIControlStateNormal];

  if (changeCount > 0) {
    // Enable both buttons
    self.applyChangesButton.enabled = YES;
    self.discardKeybindsButton.enabled = YES;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.applyChangesButton.alpha = 1.0;
                       self.discardKeybindsButton.alpha =
                           1.0; // Full opacity when enabled
                     }];
  } else {
    // Disable both buttons
    self.applyChangesButton.enabled = NO;
    self.discardKeybindsButton.enabled = NO;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.applyChangesButton.alpha = 0.5;
                       self.discardKeybindsButton.alpha =
                           0.3; // More greyed out when disabled
                     }];
  }
}

// Apply all staged keybind changes (OPTIMIZED)
- (void)applyKeybindChangesTapped {
  if (self.stagedKeybinds.count == 0)
    return;

  // Load existing saved bindings
  NSMutableDictionary *savedBindings = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"] mutableCopy];
  if (!savedBindings)
    savedBindings = [NSMutableDictionary dictionary];

  // Apply all staged changes
  for (NSString *action in self.stagedKeybinds) {
    NSNumber *newKey = self.stagedKeybinds[action];

    // OPTIMIZED: O(1) hash lookup instead of O(n) loop
    NSNumber *defaultKeyNum = self.actionToDefaultKeyMap[action];
    GCKeyCode defaultKey = defaultKeyNum ? [defaultKeyNum integerValue] : 0;

    // If newKey is 0 (unbound) or matches default, remove from saved bindings
    // Otherwise, save the custom binding
    if ([newKey integerValue] == 0 || [newKey integerValue] == defaultKey) {
      [savedBindings removeObjectForKey:action];
    } else {
      savedBindings[action] = newKey;
    }
  }

  // Save to UserDefaults
  [[NSUserDefaults standardUserDefaults] setObject:savedBindings
                                            forKey:@"fortniteKeybinds"];

  // CRITICAL: Reload Fortnite keybinds into fast array
  loadFortniteKeybinds();

  // Clear staged changes
  [self.stagedKeybinds removeAllObjects];

  // Refresh UI
  [self refreshFortniteKeybinds];
  [self updateApplyChangesButton];

  // Show confirmation
  [self showFeedback:@"Keybinds Applied & Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

// Discard all staged keybind changes
- (void)discardKeybindChangesTapped {
  if (self.stagedKeybinds.count == 0)
    return;

  // Clear all staged changes
  [self.stagedKeybinds removeAllObjects];

  // Refresh UI to show saved keybinds (remove yellow borders)
  [self refreshFortniteKeybinds];
  [self updateApplyChangesButton];

  // Show feedback
  [self showFeedback:@"Changes Discarded"
               color:[UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0]];
}

// Sync Fortnite keybinds into the keyRemappings table (O(1) lookup, called on save)

// Reset a single keybind to default
- (void)resetKeybindTapped:(UIButton *)sender {
  NSString *action = sender.accessibilityLabel;
  GCKeyCode defaultKey = sender.tag;

  // Check if resetting to default would create a conflict
  NSString *conflictAction = [self findActionUsingKey:defaultKey
                                      excludingAction:action];

  if (conflictAction) {
    // Show conflict warning
    NSString *message = [NSString
        stringWithFormat:@"Resetting %@ to %@ will conflict with %@. Continue?",
                         action, getKeyName(defaultKey), conflictAction];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Key Conflict"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert
        addAction:[UIAlertAction
                      actionWithTitle:@"Reset Anyway"
                                style:UIAlertActionStyleDestructive
                              handler:^(UIAlertAction *_Nonnull alertAction) {
                                [self performResetForAction:action
                                                 defaultKey:defaultKey];
                              }]];

    [self presentViewController:alert animated:YES completion:nil];
  } else {
    // No conflict, reset directly
    [self performResetForAction:action defaultKey:defaultKey];
  }
}

// Perform the actual reset (helper method)
- (void)performResetForAction:(NSString *)action
                   defaultKey:(GCKeyCode)defaultKey {
  // Remove from staged changes
  [self.stagedKeybinds removeObjectForKey:action];

  // Remove from saved bindings
  NSMutableDictionary *savedBindings = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"] mutableCopy];
  if (savedBindings) {
    [savedBindings removeObjectForKey:action];
    [[NSUserDefaults standardUserDefaults] setObject:savedBindings
                                              forKey:@"fortniteKeybinds"];
  }

  // CRITICAL: Reload Fortnite keybinds into fast array
  loadFortniteKeybinds();

  // Refresh UI
  [self refreshFortniteKeybinds];
  [self updateApplyChangesButton];

  // Show feedback
  [self showFeedback:[NSString stringWithFormat:@"%@ reset to %@", action,
                                                getKeyName(defaultKey)]
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

// Reset all keybinds to defaults
- (void)resetAllKeybindsTapped {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reset All Keybinds?"
                       message:@"This will clear all custom keybinds and "
                               @"restore Fortnite defaults"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert
      addAction:[UIAlertAction
                    actionWithTitle:@"Reset All"
                              style:UIAlertActionStyleDestructive
                            handler:^(UIAlertAction *_Nonnull action) {
                              // Clear all staged changes
                              [self.stagedKeybinds removeAllObjects];

                              // Clear all saved Fortnite bindings
                              [[NSUserDefaults standardUserDefaults]
                                  removeObjectForKey:@"fortniteKeybinds"];

                              // CRITICAL: Reload Fortnite keybinds into fast
                              // array (clears it)
                              loadFortniteKeybinds();

                              // Refresh UI
                              [self refreshFortniteKeybinds];
                              [self updateApplyChangesButton];

                              // Show feedback
                              [self
                                  showFeedback:@"All keybinds reset to defaults"
                                         color:[UIColor colorWithRed:0.3
                                                               green:0.9
                                                                blue:0.3
                                                               alpha:1.0]];
                            }]];

  [self presentViewController:alert animated:YES completion:nil];
}

// Refresh the Fortnite keybinds display
- (void)refreshFortniteKeybinds {
  UIView *container = [self.keyRemapTab viewWithTag:9998];
  if (!container)
    return;

  // Clear existing rows
  for (UIView *subview in container.subviews) {
    [subview removeFromSuperview];
  }

  CGFloat rowY = 0;
  CGFloat contentWidth = 290;

  // Recreate all Fortnite keybind rows (same structure as in createKeyRemapTab)
  NSArray *keybindCategories = @[
    @{
      @"title" : @"MOVEMENT",
      @"binds" : @[
        @{@"action" : @"Forward", @"default" : @(26)},
        @{@"action" : @"Left", @"default" : @(4)},
        @{@"action" : @"Backward", @"default" : @(22)},
        @{@"action" : @"Right", @"default" : @(7)},
        @{@"action" : @"Sprint", @"default" : @(225)},
        @{@"action" : @"Crouch", @"default" : @(224)},
        @{@"action" : @"Auto Walk", @"default" : @(46)}
      ]
    },
    @{
      @"title" : @"COMBAT",
      @"binds" : @[
        @{@"action" : @"Harvesting Tool", @"default" : @(9)},
        @{@"action" : @"Use", @"default" : @(8)},
        @{@"action" : @"Reload", @"default" : @(21)},
        @{@"action" : @"Weapon Slot 1", @"default" : @(30)},
        @{@"action" : @"Weapon Slot 2", @"default" : @(31)},
        @{@"action" : @"Weapon Slot 3", @"default" : @(32)},
        @{@"action" : @"Weapon Slot 4", @"default" : @(33)},
        @{@"action" : @"Weapon Slot 5", @"default" : @(34)}
      ]
    },
    @{
      @"title" : @"BUILDING",
      @"binds" : @[
        @{@"action" : @"Build", @"default" : @(20)},
        @{@"action" : @"Edit", @"default" : @(10)},
        @{@"action" : @"Wall", @"default" : @(29)},
        @{@"action" : @"Floor", @"default" : @(27)},
        @{@"action" : @"Stairs", @"default" : @(6)},
        @{@"action" : @"Roof", @"default" : @(25)}
      ]
    },
    @{
      @"title" : @"INVENTORY",
      @"binds" : @[
        @{@"action" : @"Inventory", @"default" : @(43)}, // Tab (now remappable)
        @{@"action" : @"Inventory Toggle", @"default" : @(230)}
      ]
    },
    @{
      @"title" : @"COMMUNICATION",
      @"binds" : @[
        @{@"action" : @"Emote", @"default" : @(5)},
        @{@"action" : @"Chat", @"default" : @(40)},
        @{@"action" : @"Push To Talk", @"default" : @(23)},
        @{@"action" : @"Shake Head", @"default" : @(11)}
      ]
    },
    @{
      @"title" : @"NAVIGATION",
      @"binds" : @[ @{@"action" : @"Map", @"default" : @(16)} ]
    }
  ];

  for (NSDictionary *category in keybindCategories) {
    // Category header
    UILabel *categoryLabel =
        [[UILabel alloc] initWithFrame:CGRectMake(0, rowY, contentWidth, 20)];
    categoryLabel.text = category[@"title"];
    categoryLabel.textColor = [UIColor colorWithRed:0.5
                                              green:0.7
                                               blue:1.0
                                              alpha:1.0];
    categoryLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    categoryLabel.textAlignment = NSTextAlignmentLeft;
    [container addSubview:categoryLabel];
    rowY += 24;

    // Create rows for each keybind
    for (NSDictionary *bind in category[@"binds"]) {
      UIView *row = [self
          createFortniteKeybindRowWithAction:bind[@"action"]
                                  defaultKey:[bind[@"default"] integerValue]
                                    readOnly:[bind[@"readonly"] boolValue]
                                         atY:rowY
                                       width:contentWidth];
      [container addSubview:row];
      rowY += 36;
    }

    rowY += 8;
  }

  // Resize container
  CGRect frame = container.frame;
  frame.size.height = rowY;
  container.frame = frame;

  // Recalculate total content height
  [self recalculateKeyRemapContentHeight];
}

// Recalculate the total content height for the key remap tab
- (void)recalculateKeyRemapContentHeight {
  // Simply get the Add button's position and add button height + bottom margin
  // This is much simpler and matches exactly what Sensitivity tab does
  if (!self.addRemapButton)
    return;

  CGFloat y = self.addRemapButton.frame.origin.y; // Button starts here
  y += 32;                                        // Button height
  y += 20; // Bottom margin (matching left/right margins)

  // Update stored content height
  self.keyRemapContentHeight = y;

  // CRITICAL: Resize the tab view itself to match content height
  // This allows touches to pass through to all elements
  CGRect tabFrame = self.keyRemapTab.frame;
  tabFrame.size.height = self.keyRemapContentHeight;
  self.keyRemapTab.frame = tabFrame;

  // If we're currently showing this tab, update scroll view
  if (self.currentTab == PopupTabKeyRemap) {
    self.scrollView.contentSize = CGSizeMake(330, self.keyRemapContentHeight);
  }
}

// Tab switching
- (void)sensitivityTabTapped {
  [self switchToTab:PopupTabSensitivity];
}

- (void)keyRemapTabTapped {
  [self switchToTab:PopupTabKeyRemap];
}

- (void)buildModeTabTapped {
  [self switchToTab:PopupTabBuildMode];
}

- (void)containerTabTapped {
  [self switchToTab:PopupTabContainer];
}

// Create Container tab
- (void)createContainerTab {
  self.containerTab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 510)];
  self.containerTab.backgroundColor = [UIColor clearColor];

  CGFloat y = 16;
  CGFloat leftMargin = 20;
  CGFloat rightMargin = 20;
  CGFloat contentWidth = 330 - leftMargin - rightMargin;

  // ========================================
  // HEADER
  // ========================================
  UILabel *title = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  title.text = @"Container Settings";
  title.textColor = [UIColor whiteColor];
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  title.textAlignment = NSTextAlignmentCenter;
  [self.containerTab addSubview:title];
  y += 32;

  // Instruction banner (matching other tabs' style)
  UIView *instructionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 76)];
  instructionBanner.backgroundColor = [UIColor colorWithRed:0.6
                                                      green:0.2
                                                       blue:0.8
                                                      alpha:0.2];
  instructionBanner.layer.cornerRadius = 8;
  [self.containerTab addSubview:instructionBanner];

  UILabel *instruction =
      [[UILabel alloc] initWithFrame:CGRectMake(8, 10, contentWidth - 16, 56)];
  instruction.text = @"Link tweak to your game container\nSelect Fortnite data "
                     @"folder below\nApp will restart after selection";
  instruction.textColor = [UIColor colorWithRed:0.8
                                          green:0.6
                                           blue:1.0
                                          alpha:1.0];
  instruction.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  instruction.textAlignment = NSTextAlignmentCenter;
  instruction.numberOfLines = 3;
  [instructionBanner addSubview:instruction];
  y += 92;

  // Data folder button (macOS liquid glass style - accent color)
  UIButton *folderButton = [UIButton buttonWithType:UIButtonTypeSystem];
  folderButton.frame = CGRectMake(leftMargin, y, contentWidth, 44);
  folderButton.backgroundColor = [UIColor colorWithRed:0.5
                                                 green:0.2
                                                  blue:0.7
                                                 alpha:0.85];
  [folderButton setTitle:@"Select Fortnite Data Folder"
                forState:UIControlStateNormal];
  [folderButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  folderButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightMedium];
  folderButton.layer.cornerRadius = 6;
  folderButton.layer.borderWidth = 0.5;
  folderButton.layer.borderColor =
      [UIColor colorWithRed:0.4 green:0.15 blue:0.6 alpha:0.6].CGColor;
  // Add subtle shadow for depth
  folderButton.layer.shadowColor =
      [UIColor colorWithRed:0.4 green:0.1 blue:0.6 alpha:1.0].CGColor;
  folderButton.layer.shadowOffset = CGSizeMake(0, 1);
  folderButton.layer.shadowOpacity = 0.2;
  folderButton.layer.shadowRadius = 1;
  folderButton.userInteractionEnabled = YES;
  [folderButton addTarget:self
                   action:@selector(selectFolderTapped:)
         forControlEvents:UIControlEventTouchUpInside];
  [self.containerTab addSubview:folderButton];
  y += 60;

  // Divider
  UIView *divider1 = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  divider1.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [self.containerTab addSubview:divider1];
  y += 20;

  // Settings Import/Export section
  UILabel *importExportLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 20)];
  importExportLabel.text = @"Settings Import/Export";
  importExportLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
  importExportLabel.font = [UIFont systemFontOfSize:13
                                             weight:UIFontWeightMedium];
  importExportLabel.textAlignment = NSTextAlignmentCenter;
  [self.containerTab addSubview:importExportLabel];
  y += 28;

  // Description
  UILabel *importExportDesc = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 32)];
  importExportDesc.text = @"Share your sensitivity and keybind settings";
  importExportDesc.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
  importExportDesc.font = [UIFont systemFontOfSize:11
                                            weight:UIFontWeightMedium];
  importExportDesc.textAlignment = NSTextAlignmentCenter;
  importExportDesc.numberOfLines = 2;
  [self.containerTab addSubview:importExportDesc];
  y += 40;

  // Export button
  UIButton *exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
  exportButton.frame = CGRectMake(leftMargin, y, contentWidth, 36);
  exportButton.backgroundColor = [UIColor colorWithRed:0.0
                                                 green:0.47
                                                  blue:1.0
                                                 alpha:0.85];
  [exportButton setTitle:@"Export Settings 📤" forState:UIControlStateNormal];
  [exportButton setTitleColor:[UIColor whiteColor]
                     forState:UIControlStateNormal];
  exportButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightSemibold];
  exportButton.layer.cornerRadius = 6;
  exportButton.layer.borderWidth = 0.5;
  exportButton.layer.borderColor =
      [UIColor colorWithRed:0.0 green:0.4 blue:0.9 alpha:0.6].CGColor;
  exportButton.layer.shadowColor =
      [UIColor colorWithRed:0.0 green:0.3 blue:0.8 alpha:1.0].CGColor;
  exportButton.layer.shadowOffset = CGSizeMake(0, 1);
  exportButton.layer.shadowOpacity = 0.2;
  exportButton.layer.shadowRadius = 1;
  [exportButton addTarget:self
                   action:@selector(exportSettings)
         forControlEvents:UIControlEventTouchUpInside];
  [self.containerTab addSubview:exportButton];
  y += 42;

  // Import button
  UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
  importButton.frame = CGRectMake(leftMargin, y, contentWidth, 36);
  importButton.backgroundColor = [UIColor colorWithRed:0.2
                                                 green:0.8
                                                  blue:0.3
                                                 alpha:0.85];
  [importButton setTitle:@"Import Settings 📥" forState:UIControlStateNormal];
  [importButton setTitleColor:[UIColor blackColor]
                     forState:UIControlStateNormal];
  importButton.titleLabel.font = [UIFont systemFontOfSize:13
                                                   weight:UIFontWeightSemibold];
  importButton.layer.cornerRadius = 6;
  importButton.layer.borderWidth = 0.5;
  importButton.layer.borderColor =
      [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:0.6].CGColor;
  importButton.layer.shadowColor =
      [UIColor colorWithRed:0.1 green:0.6 blue:0.2 alpha:1.0].CGColor;
  importButton.layer.shadowOffset = CGSizeMake(0, 1);
  importButton.layer.shadowOpacity = 0.2;
  importButton.layer.shadowRadius = 1;
  [importButton addTarget:self
                   action:@selector(importSettings)
         forControlEvents:UIControlEventTouchUpInside];
  [self.containerTab addSubview:importButton];
  y += 48;

  // Feedback label for container tab
  UILabel *containerFeedbackLabel = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  containerFeedbackLabel.textAlignment = NSTextAlignmentCenter;
  containerFeedbackLabel.font = [UIFont systemFontOfSize:13
                                                  weight:UIFontWeightSemibold];
  containerFeedbackLabel.alpha = 0;
  containerFeedbackLabel.tag = 8889; // Unique tag for container feedback
  [self.containerTab addSubview:containerFeedbackLabel];
}

// Create Quick Start tab — single Build Mode Setup video card
- (void)createQuickStartTab {
  CGFloat w = 330.0;
  CGFloat leftMargin = 20.0;
  CGFloat contentWidth = w - leftMargin * 2;

  self.quickStartTab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 10)];
  self.quickStartTab.backgroundColor = [UIColor clearColor];

  // Content added directly to self.quickStartTab (plain UIView),
  // matching the pattern of all other tabs. The outer self.scrollView
  // handles all scrolling — no nested UIScrollView needed.
  UIView *content = self.quickStartTab;

  CGFloat y = 16;

  // ========================================
  // HEADER — matches all other tabs exactly
  // ========================================
  UILabel *header = [[UILabel alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, 24)];
  header.text = @"Quick Start Guide";
  header.textColor = [UIColor whiteColor];
  header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
  header.textAlignment = NSTextAlignmentCenter;
  [content addSubview:header];
  y += 32;

  // ========================================
  // INSTRUCTION BANNER — matches other tabs
  // ========================================
  UILabel *tmpLabel = [[UILabel alloc] init];
  tmpLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  tmpLabel.numberOfLines = 0;
  tmpLabel.text =
      @"Watch this short tutorial to get up and running with FnMacTweak.";
  CGFloat textH =
      [tmpLabel sizeThatFits:CGSizeMake(contentWidth - 16, CGFLOAT_MAX)].height;
  CGFloat bannerH = textH + 20;

  UIView *instructionBanner = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, bannerH)];
  instructionBanner.backgroundColor = [UIColor colorWithRed:0.35
                                                      green:0.35
                                                       blue:0.40
                                                      alpha:0.35];
  instructionBanner.layer.cornerRadius = 8;
  [content addSubview:instructionBanner];

  UILabel *instruction = [[UILabel alloc]
      initWithFrame:CGRectMake(8, 10, contentWidth - 16, textH)];
  instruction.text =
      @"Watch this short tutorial to get up and running with FnMacTweak.";
  instruction.textColor = [UIColor colorWithWhite:0.80 alpha:1.0];
  instruction.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  instruction.textAlignment = NSTextAlignmentCenter;
  instruction.numberOfLines = 0;
  [instructionBanner addSubview:instruction];
  y += bannerH + 16;

  // ========================================
  // DIVIDER — matches other tabs exactly
  // ========================================
  UIView *div = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  div.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [content addSubview:div];
  y += 20;

  // ========================================
  // VIDEO CARD — full width, no wrapper box
  // ========================================
  FnVideoCardView *card1 = [[FnVideoCardView alloc]
      initWithTitle:@"Build Mode Setup"
        description:
            @"Learn how to configure the HUD, use the red dot touch target, "
            @"tune your in-game settings, and switch between Zero Build and "
            @"Build modes."
              width:contentWidth];
  card1.tag = 201;
  card1.frame =
      CGRectMake(leftMargin, y, contentWidth, card1.bounds.size.height);
  [content addSubview:card1];
  y += card1.bounds.size.height + 16;

  // ========================================
  // LINE SPACER — matches other tabs
  // ========================================
  UIView *spacer = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + 40, y, contentWidth - 80, 1)];
  spacer.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [content addSubview:spacer];
  y += 20;

  // ========================================
  // "Opening Settings" CARD
  // ========================================
  CGFloat cardW = contentWidth;

  UIView *openCard =
      [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, cardW, 90)];
  openCard.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  openCard.layer.cornerRadius = 8;
  openCard.layer.borderWidth = 0.5;
  openCard.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [content addSubview:openCard];

  UILabel *openTitle =
      [[UILabel alloc] initWithFrame:CGRectMake(12, 10, cardW - 24, 16)];
  openTitle.text = @"Opening Settings";
  openTitle.textColor = [UIColor whiteColor];
  openTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  [openCard addSubview:openTitle];

  // "P" key badge
  UILabel *pBadge = [[UILabel alloc] initWithFrame:CGRectMake(12, 32, 28, 24)];
  pBadge.text = @"P";
  pBadge.textColor = [UIColor whiteColor];
  pBadge.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  pBadge.textAlignment = NSTextAlignmentCenter;
  pBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  pBadge.layer.cornerRadius = 5;
  pBadge.layer.borderWidth = 0.5;
  pBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  pBadge.clipsToBounds = YES;
  [openCard addSubview:pBadge];

  UILabel *openDesc =
      [[UILabel alloc] initWithFrame:CGRectMake(12, 62, cardW - 24, 20)];
  openDesc.text = @"Press P at any time while in-game to open the FnMacTweak "
                  @"settings pane.";
  openDesc.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  openDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  openDesc.numberOfLines = 2;
  // Resize to fit
  CGSize openDescSize =
      [openDesc sizeThatFits:CGSizeMake(cardW - 24, CGFLOAT_MAX)];
  openDesc.frame = CGRectMake(12, 62, cardW - 24, openDescSize.height);
  // Resize card to fit description
  CGRect openCardF = openCard.frame;
  openCardF.size.height = 62 + openDescSize.height + 12;
  openCard.frame = openCardF;
  [openCard addSubview:openDesc];
  y += openCardF.size.height + 10;

  // ========================================
  // "Lock Cursor" + "Unlock Cursor" ROW
  // ========================================
  CGFloat halfW = (cardW - 8) / 2;

  // — Lock Cursor card (left) —
  UIView *lockCard =
      [[UIView alloc] initWithFrame:CGRectMake(leftMargin, y, halfW, 10)];
  lockCard.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  lockCard.layer.cornerRadius = 8;
  lockCard.layer.borderWidth = 0.5;
  lockCard.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [content addSubview:lockCard];

  UILabel *lockTitle =
      [[UILabel alloc] initWithFrame:CGRectMake(10, 10, halfW - 20, 16)];
  lockTitle.text = @"Lock Cursor";
  lockTitle.textColor = [UIColor whiteColor];
  lockTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  [lockCard addSubview:lockTitle];

  // L⌥ badge
  UILabel *ltBadge = [[UILabel alloc] initWithFrame:CGRectMake(10, 32, 32, 24)];
  ltBadge.text = @"L⌥";
  ltBadge.textColor = [UIColor whiteColor];
  ltBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
  ltBadge.textAlignment = NSTextAlignmentCenter;
  ltBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  ltBadge.layer.cornerRadius = 5;
  ltBadge.layer.borderWidth = 0.5;
  ltBadge.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  ltBadge.clipsToBounds = YES;
  [lockCard addSubview:ltBadge];

  // "+" label
  UILabel *plusLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(46, 32, 16, 24)];
  plusLabel.text = @"+";
  plusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
  plusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
  plusLabel.textAlignment = NSTextAlignmentCenter;
  [lockCard addSubview:plusLabel];

  // "Click" badge
  UILabel *clickBadge =
      [[UILabel alloc] initWithFrame:CGRectMake(64, 32, 40, 24)];
  clickBadge.text = @"Click";
  clickBadge.textColor = [UIColor whiteColor];
  clickBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
  clickBadge.textAlignment = NSTextAlignmentCenter;
  clickBadge.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  clickBadge.layer.cornerRadius = 5;
  clickBadge.layer.borderWidth = 0.5;
  clickBadge.layer.borderColor =
      [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  clickBadge.clipsToBounds = YES;
  [lockCard addSubview:clickBadge];

  UILabel *lockDesc =
      [[UILabel alloc] initWithFrame:CGRectMake(10, 62, halfW - 20, 10)];
  lockDesc.text = @"Locks your mouse cursor to the game window.";
  lockDesc.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  lockDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  lockDesc.numberOfLines = 0;
  CGSize lockDescSize =
      [lockDesc sizeThatFits:CGSizeMake(halfW - 20, CGFLOAT_MAX)];
  lockDesc.frame = CGRectMake(10, 62, halfW - 20, lockDescSize.height);
  [lockCard addSubview:lockDesc];
  CGRect lockCardF = lockCard.frame;
  lockCardF.size.height = 62 + lockDescSize.height + 12;
  lockCard.frame = lockCardF;

  // — Unlock Cursor card (right) —
  UIView *unlockCard = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin + halfW + 8, y, halfW, 10)];
  unlockCard.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  unlockCard.layer.cornerRadius = 8;
  unlockCard.layer.borderWidth = 0.5;
  unlockCard.layer.borderColor =
      [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [content addSubview:unlockCard];

  UILabel *unlockTitle =
      [[UILabel alloc] initWithFrame:CGRectMake(10, 10, halfW - 20, 16)];
  unlockTitle.text = @"Unlock Cursor";
  unlockTitle.textColor = [UIColor whiteColor];
  unlockTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  [unlockCard addSubview:unlockTitle];

  // L⌥ badge (unlock — no + Click)
  UILabel *ltBadge2 =
      [[UILabel alloc] initWithFrame:CGRectMake(10, 32, 32, 24)];
  ltBadge2.text = @"L⌥";
  ltBadge2.textColor = [UIColor whiteColor];
  ltBadge2.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
  ltBadge2.textAlignment = NSTextAlignmentCenter;
  ltBadge2.backgroundColor = [UIColor colorWithWhite:0.28 alpha:0.9];
  ltBadge2.layer.cornerRadius = 5;
  ltBadge2.layer.borderWidth = 0.5;
  ltBadge2.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.6].CGColor;
  ltBadge2.clipsToBounds = YES;
  [unlockCard addSubview:ltBadge2];

  UILabel *unlockDesc =
      [[UILabel alloc] initWithFrame:CGRectMake(10, 62, halfW - 20, 10)];
  unlockDesc.text = @"Unlocks your mouse cursor from the game window.";
  unlockDesc.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
  unlockDesc.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
  unlockDesc.numberOfLines = 0;
  CGSize unlockDescSize =
      [unlockDesc sizeThatFits:CGSizeMake(halfW - 20, CGFLOAT_MAX)];
  unlockDesc.frame = CGRectMake(10, 62, halfW - 20, unlockDescSize.height);
  [unlockCard addSubview:unlockDesc];
  CGRect unlockCardF = unlockCard.frame;
  unlockCardF.size.height = 62 + unlockDescSize.height + 12;
  unlockCard.frame = unlockCardF;

  // Equalize both side-by-side cards to the taller one
  CGFloat pairH = MAX(lockCardF.size.height, unlockCardF.size.height);
  lockCardF.size.height = pairH;
  lockCard.frame = lockCardF;
  unlockCardF.size.height = pairH;
  unlockCard.frame = unlockCardF;
  y += pairH + 16;

  // Save content height so switchToTab: can set self.scrollView.contentSize,
  // exactly like sensitivityContentHeight and keyRemapContentHeight.
  self.quickStartContentHeight = y;

  CGRect f = self.quickStartTab.frame;
  f.size.height = y;
  self.quickStartTab.frame = f;
}

- (void)quickStartTabTapped {
  [self pauseQuickStartVideos];
  [self switchToTab:PopupTabQuickStart];
}

// Pause the Quick Start video card (called when leaving the tab or closing the
// popup)
- (void)pauseQuickStartVideos {
  FnVideoCardView *card1 =
      (FnVideoCardView *)[self.quickStartTab viewWithTag:201];
  [card1 pausePlayback];
}

- (void)switchToTab:(PopupTab)tab {
  // Pause Quick Start videos whenever we navigate away from that tab
  if (self.currentTab == PopupTabQuickStart && tab != PopupTabQuickStart) {
    [self pauseQuickStartVideos];
  }

  self.currentTab = tab;

  // Remove all tab views from scroll view
  [self.sensitivityTab removeFromSuperview];
  [self.keyRemapTab removeFromSuperview];
  [self.buildModeTab removeFromSuperview];
  [self.containerTab removeFromSuperview];
  [self.quickStartTab removeFromSuperview];

  // Map each tab to its button frame so the indicator can slide to it
  CGRect targetFrame;
  switch (tab) {
  case PopupTabSensitivity:
    targetFrame = self.sensitivityTabButton.frame;
    break;
  case PopupTabKeyRemap:
    targetFrame = self.keyRemapTabButton.frame;
    break;
  case PopupTabBuildMode:
    targetFrame = self.buildModeTabButton.frame;
    break;
  case PopupTabContainer:
    targetFrame = self.containerTabButton.frame;
    break;
  case PopupTabQuickStart:
    targetFrame = self.quickStartTabButton.frame;
    break;
  default:
    targetFrame = self.sensitivityTabButton.frame;
    break;
  }

  // Slide the indicator pill with a snappy spring
  [UIView animateWithDuration:0.28
                        delay:0
       usingSpringWithDamping:0.78
        initialSpringVelocity:0.4
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
                     self.tabIndicator.frame = targetFrame;
                   }
                   completion:nil];

  // Add the selected tab's content
  if (tab == PopupTabSensitivity) {
    [self.scrollView addSubview:self.sensitivityTab];
    self.scrollView.contentSize =
        CGSizeMake(330, self.sensitivityContentHeight);
  } else if (tab == PopupTabKeyRemap) {
    [self.scrollView addSubview:self.keyRemapTab];
    self.scrollView.contentSize = CGSizeMake(330, self.keyRemapContentHeight);
  } else if (tab == PopupTabBuildMode) {
    [self.scrollView addSubview:self.buildModeTab];
    self.scrollView.contentSize = CGSizeMake(330, 400);
  } else if (tab == PopupTabContainer) {
    [self.scrollView addSubview:self.containerTab];
    self.scrollView.contentSize = CGSizeMake(330, 400);
  } else if (tab == PopupTabQuickStart) {
    [self.scrollView addSubview:self.quickStartTab];
    self.scrollView.contentSize =
        CGSizeMake(330, self.quickStartContentHeight);
  }

  // Reset scroll position to top
  [self.scrollView setContentOffset:CGPointZero animated:NO];
}

// Key remapping actions
- (void)addKeyRemapTapped {
  // Show instruction alert
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Add Key Remap"
                       message:@"Press a keyboard key to use as source"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *_Nonnull action) {
                                 keyCaptureCallback = nil;
                               }]];

  [self presentViewController:alert
                     animated:YES
                   completion:^{
                     // Set up callback to capture keyboard key press only
                     __weak typeof(self) weakSelf = self;

                     // Keyboard capture
                     keyCaptureCallback = ^(GCKeyCode keyCode) {
                       dispatch_async(dispatch_get_main_queue(), ^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (!strongSelf)
                           return;

                         // Clear callback
                         keyCaptureCallback = nil;

                         // Dismiss alert
                         [strongSelf.presentedViewController
                             dismissViewControllerAnimated:YES
                                                completion:nil];

                         // Check for system keys
                         if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                           UIAlertController *errorAlert = [UIAlertController
                               alertControllerWithTitle:@"Invalid Key"
                                                message:@"Cannot remap system "
                                                        @"keys (Alt, P)"
                                         preferredStyle:
                                             UIAlertControllerStyleAlert];
                           [errorAlert
                               addAction:
                                   [UIAlertAction
                                       actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
                           [strongSelf presentViewController:errorAlert
                                                    animated:YES
                                                  completion:nil];
                           return;
                         }

                         // Show target key picker
                         [strongSelf showTargetKeyPickerForSourceKey:keyCode];
                       });
                     };
                   }];
}

- (void)changeSourceKeyTapped:(UIButton *)sender {
  GCKeyCode oldSourceKey = sender.tag;

  // Show alert
  UIAlertController *alert =
      [UIAlertController alertControllerWithTitle:@"Change Source Key"
                                          message:@"Press a keyboard key"
                                   preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *_Nonnull action) {
                                 keyCaptureCallback = nil;
                               }]];

  [self presentViewController:alert
                     animated:YES
                   completion:^{
                     // Set up callback to capture keyboard key press only
                     __weak typeof(self) weakSelf = self;

                     // Keyboard capture
                     keyCaptureCallback = ^(GCKeyCode keyCode) {
                       dispatch_async(dispatch_get_main_queue(), ^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (!strongSelf)
                           return;

                         // Clear callback
                         keyCaptureCallback = nil;

                         // Dismiss alert
                         [strongSelf.presentedViewController
                             dismissViewControllerAnimated:YES
                                                completion:nil];

                         // Check for system keys
                         if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                           UIAlertController *errorAlert = [UIAlertController
                               alertControllerWithTitle:@"Invalid Key"
                                                message:@"Cannot remap system "
                                                        @"keys (Alt, P)"
                                         preferredStyle:
                                             UIAlertControllerStyleAlert];
                           [errorAlert
                               addAction:
                                   [UIAlertAction
                                       actionWithTitle:@"OK"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
                           [strongSelf presentViewController:errorAlert
                                                    animated:YES
                                                  completion:nil];
                           return;
                         }

                         // Remove old mapping and add new one
                         NSNumber *targetKey = keyRemappings[@(oldSourceKey)];
                         [keyRemappings removeObjectForKey:@(oldSourceKey)];
                         keyRemappings[@(keyCode)] = targetKey;

                         // CRITICAL: Save to persistent storage
                         saveKeyRemappings();

                         [strongSelf refreshKeyRemapRows];

                         // Show confirmation
                         [strongSelf
                             showFeedback:[NSString
                                              stringWithFormat:
                                                  @"Source changed: %@ → %@",
                                                  getKeyName(keyCode),
                                                  getKeyName(
                                                      [targetKey integerValue])]
                                    color:[UIColor colorWithRed:0.3
                                                          green:0.9
                                                           blue:0.3
                                                          alpha:1.0]];
                       });
                     };
                   }];
}

- (void)changeTargetKeyTapped:(UIButton *)sender {
  GCKeyCode sourceKey = sender.tag;

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Change Target Key"
                       message:[NSString
                                   stringWithFormat:
                                       @"Remapping: %@\nPress a keyboard key",
                                       getKeyName(sourceKey)]
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *_Nonnull action) {
                                 keyCaptureCallback = nil;
                               }]];

  [self
      presentViewController:alert
                   animated:YES
                 completion:^{
                   // Set up callback to capture keyboard key press only
                   __weak typeof(self) weakSelf = self;

                   // Keyboard capture
                   keyCaptureCallback = ^(GCKeyCode keyCode) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf)
                         return;

                       // Clear callback
                       keyCaptureCallback = nil;

                       // Dismiss alert
                       [strongSelf.presentedViewController
                           dismissViewControllerAnimated:YES
                                              completion:nil];

                       // Check for system keys
                       if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Key"
                                              message:@"Cannot use system keys "
                                                      @"(Alt, P) as target"
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       // Update the mapping with new target
                       keyRemappings[@(sourceKey)] = @(keyCode);

                       // CRITICAL: Save to persistent storage
                       saveKeyRemappings();

                       [strongSelf refreshKeyRemapRows];

                       // Show confirmation
                       [strongSelf
                           showFeedback:
                               [NSString
                                   stringWithFormat:@"Target changed: %@ → %@",
                                                    getKeyName(sourceKey),
                                                    getKeyName(keyCode)]
                                  color:[UIColor colorWithRed:0.3
                                                        green:0.9
                                                         blue:0.3
                                                        alpha:1.0]];
                     });
                   };
                 }];
}

- (void)deleteKeyRemapTapped:(UIButton *)sender {
  GCKeyCode sourceKey = sender.tag;
  NSNumber *targetKey = keyRemappings[@(sourceKey)];

  [keyRemappings removeObjectForKey:@(sourceKey)];

  // CRITICAL: Save to persistent storage
  saveKeyRemappings();

  [self refreshKeyRemapRows];

  // Show confirmation with the deleted mapping
  [self showFeedback:[NSString
                         stringWithFormat:@"Removed: %@ → %@",
                                          getKeyName(sourceKey),
                                          getKeyName([targetKey integerValue])]
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

- (void)showTargetKeyPickerForSourceKey:(GCKeyCode)sourceKey {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Select Target Key"
                       message:[NSString
                                   stringWithFormat:
                                       @"Source: %@\nPress a keyboard key",
                                       getKeyName(sourceKey)]
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Cancel"
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *_Nonnull action) {
                                 keyCaptureCallback = nil;
                               }]];

  [self
      presentViewController:alert
                   animated:YES
                 completion:^{
                   // Set up callback to capture keyboard key press only
                   __weak typeof(self) weakSelf = self;

                   // Keyboard capture
                   keyCaptureCallback = ^(GCKeyCode keyCode) {
                     dispatch_async(dispatch_get_main_queue(), ^{
                       __strong typeof(weakSelf) strongSelf = weakSelf;
                       if (!strongSelf)
                         return;

                       // Clear callback
                       keyCaptureCallback = nil;

                       // Dismiss alert
                       [strongSelf.presentedViewController
                           dismissViewControllerAnimated:YES
                                              completion:nil];

                       // Check for system keys
                       if (keyCode == TRIGGER_KEY || keyCode == POPUP_KEY) {
                         UIAlertController *errorAlert = [UIAlertController
                             alertControllerWithTitle:@"Invalid Key"
                                              message:@"Cannot use system keys "
                                                      @"(Alt, P) as target"
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];
                         [errorAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
                         [strongSelf presentViewController:errorAlert
                                                  animated:YES
                                                completion:nil];
                         return;
                       }

                       // Check for conflicts with Fortnite keybinds (both
                       // source and target)
                       NSString *sourceConflict =
                           [strongSelf findFortniteActionUsingKey:sourceKey];
                       NSString *targetConflict =
                           [strongSelf findFortniteActionUsingKey:keyCode];

                       void (^createMapping)(void) = ^{
                         // Create the mapping
                         keyRemappings[@(sourceKey)] = @(keyCode);

                         // CRITICAL: Save to persistent storage
                         saveKeyRemappings();

                         [strongSelf refreshKeyRemapRows];

                         // Show confirmation
                         [strongSelf
                             showFeedback:[NSString stringWithFormat:
                                                        @"Added: %@ → %@",
                                                        getKeyName(sourceKey),
                                                        getKeyName(keyCode)]
                                    color:[UIColor colorWithRed:0.3
                                                          green:0.9
                                                           blue:0.3
                                                          alpha:1.0]];
                       };

                       if (sourceConflict || targetConflict) {
                         // Build conflict message without bullet points
                         NSMutableString *message = [NSMutableString string];

                         if (sourceConflict && targetConflict) {
                           [message
                               appendFormat:
                                   @"%@ is bound to %@ and %@ is bound to %@ "
                                   @"in Fortnite Keybinds. This custom remap "
                                   @"will override these keybinds. Continue?",
                                   getKeyName(sourceKey), sourceConflict,
                                   getKeyName(keyCode), targetConflict];
                         } else if (sourceConflict) {
                           [message appendFormat:
                                        @"%@ is bound to %@ in Fortnite "
                                        @"Keybinds. This custom remap will "
                                        @"override these keybinds. Continue?",
                                        getKeyName(sourceKey), sourceConflict];
                         } else {
                           [message appendFormat:
                                        @"%@ is bound to %@ in Fortnite "
                                        @"Keybinds. This custom remap will "
                                        @"override these keybinds. Continue?",
                                        getKeyName(keyCode), targetConflict];
                         }

                         UIAlertController *conflictAlert = [UIAlertController
                             alertControllerWithTitle:@"Key Conflict"
                                              message:message
                                       preferredStyle:
                                           UIAlertControllerStyleAlert];

                         [conflictAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
                         [conflictAlert
                             addAction:
                                 [UIAlertAction
                                     actionWithTitle:@"Continue Anyway"
                                               style:
                                                   UIAlertActionStyleDestructive
                                             handler:^(
                                                 UIAlertAction
                                                     *_Nonnull alertAction) {
                                               createMapping();
                                             }]];

                         [strongSelf presentViewController:conflictAlert
                                                  animated:YES
                                                completion:nil];
                       } else {
                         // No conflict - create directly
                         createMapping();
                       }
                     });
                   };
                 }];
}

// Helper method to add a section with fields
- (CGFloat)addSectionWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                           atY:(CGFloat)y
                        fields:(NSArray<NSDictionary *> *)fields
                      isDouble:(BOOL)isDouble
                        toView:(UIView *)parentView {

  CGFloat leftMargin = 20;
  CGFloat contentWidth = 290;
  // Layout: title row top=10 h=18, subtitle top=30 h=14, fieldY=48,
  // double: label h=12 + field h=28 = 88 + 12 bottom = 100
  // single: field h=28 = 76 + 12 bottom = 88
  CGFloat sectionHeight = isDouble ? 100 : 88;

  UIView *section = [[UIView alloc]
      initWithFrame:CGRectMake(leftMargin, y, contentWidth, sectionHeight)];
  section.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.6];
  section.layer.cornerRadius = 8;
  section.layer.borderWidth = 0.5;
  section.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.4].CGColor;
  [parentView addSubview:section];

  // ↪️ Reset button — matches keybind row style exactly
  // button at x=12 w=20, label starts at x=36 (12+20+4)
  UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
  resetBtn.frame = CGRectMake(12, 9, 20, 20);
  [resetBtn setTitle:@"↪️" forState:UIControlStateNormal];
  resetBtn.titleLabel.font = [UIFont systemFontOfSize:14];
  NSMutableArray *pairs = [NSMutableArray array];
  for (NSDictionary *f in fields) {
    float resetVal = [f[@"default"] floatValue] ?: [f[@"value"] floatValue];
    [pairs addObject:[NSString
                         stringWithFormat:@"%@:%.1f", f[@"field"], resetVal]];
  }
  resetBtn.accessibilityLabel = [pairs componentsJoinedByString:@","];
  resetBtn.accessibilityHint = title; // Store section title for feedback toast
  [resetBtn addTarget:self
                action:@selector(resetSectionTapped:)
      forControlEvents:UIControlEventTouchUpInside];
  [section addSubview:resetBtn];

  // Title label — starts at x=36 (4pt gap after 20pt icon), matching keybind
  // rows
  UILabel *titleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(36, 10, contentWidth - 48, 18)];
  titleLabel.text = title;
  titleLabel.textColor = [UIColor whiteColor];
  titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  [section addSubview:titleLabel];

  UILabel *subtitleLabel =
      [[UILabel alloc] initWithFrame:CGRectMake(12, 30, contentWidth - 24, 14)];
  subtitleLabel.text = subtitle;
  subtitleLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
  subtitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
  [section addSubview:subtitleLabel];

  CGFloat fieldY = 48;
  CGFloat fieldSpacing = isDouble ? 12 : 0;
  CGFloat fieldWidth = isDouble ? (contentWidth - 36) / 2 : (contentWidth - 24);

  for (NSInteger i = 0; i < fields.count; i++) {
    NSDictionary *fieldInfo = fields[i];

    CGFloat fieldX = 12 + (i * (fieldWidth + fieldSpacing));

    if (isDouble) {
      UILabel *label = [[UILabel alloc]
          initWithFrame:CGRectMake(fieldX, fieldY, fieldWidth, 12)];
      label.text = fieldInfo[@"label"];
      label.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
      label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
      label.textAlignment = NSTextAlignmentCenter;
      [section addSubview:label];
    }

    UITextField *field = [[UITextField alloc]
        initWithFrame:CGRectMake(fieldX, fieldY + (isDouble ? 14 : 0),
                                 fieldWidth, 28)];
    field.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    field.textColor = [UIColor whiteColor];
    field.layer.cornerRadius = 6;
    field.keyboardType = UIKeyboardTypeDecimalPad;
    field.text =
        [NSString stringWithFormat:@"%.1f", [fieldInfo[@"value"] floatValue]];
    field.textAlignment = NSTextAlignmentCenter;
    field.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    field.delegate = self;

    // Add change notification for real-time updates
    [field addTarget:self
                  action:@selector(sensitivityFieldChanged:)
        forControlEvents:UIControlEventEditingChanged];

    [section addSubview:field];
    [self setValue:field forKey:fieldInfo[@"field"]];
  }

  return floor(y + sectionHeight + 8);
}

// Helper: Add a visual divider
- (void)addDividerAtY:(CGFloat)y toView:(UIView *)parentView {
  y = floor(y);
  UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(40, y, 250, 1)];
  divider.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
  [parentView addSubview:divider];
}

// Handle dragging the window
- (void)closeButtonTapped {
  [self.view endEditing:YES];
  // Check if there are unsaved changes (keybinds or sensitivity)
  BOOL hasKeybindChanges = self.stagedKeybinds.count > 0;
  BOOL hasSensitivityChanges = [self hasSensitivityChanges];

  if (hasKeybindChanges || hasSensitivityChanges) {
    NSString *message;
    if (hasKeybindChanges && hasSensitivityChanges) {
      message = @"You have unsaved keybind and sensitivity changes. What would "
                @"you like to do?";
    } else if (hasKeybindChanges) {
      message = @"You have unsaved keybind changes. What would you like to do?";
    } else {
      message =
          @"You have unsaved sensitivity changes. What would you like to do?";
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Unsaved Changes"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Save & Close"
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   // Save sensitivity changes if any
                                   if (hasSensitivityChanges) {
                                     [self saveButtonTapped:nil];
                                   }

                                   // Apply keybind changes if any
                                   if (hasKeybindChanges) {
                                     [self applyKeybindChangesTapped];
                                   }

                                   // Close after a brief delay to show the
                                   // success message
                                   dispatch_after(
                                       dispatch_time(DISPATCH_TIME_NOW,
                                                     0.5 * NSEC_PER_SEC),
                                       dispatch_get_main_queue(), ^{
                                         extern BOOL isPopupVisible;
                                         extern UIWindow *popupWindow;
                                         isPopupVisible = NO;
                                         popupWindow.hidden = YES;
                                         updateRedDotVisibility();
                                       });
                                 }]];

    [alert addAction:[UIAlertAction
                         actionWithTitle:@"Discard Changes"
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *_Nonnull action) {
                                   // Revert sensitivity changes
                                   if (hasSensitivityChanges) {
                                     [self revertSensitivityChanges];
                                     [self updateSensitivityDiscardButton];
                                     [self updateSensitivityFieldBorders];
                                   }

                                   // Clear staged keybind changes
                                   if (hasKeybindChanges) {
                                     [self.stagedKeybinds removeAllObjects];
                                     [self updateApplyChangesButton];
                                     [self refreshFortniteKeybinds];
                                   }

                                   extern BOOL isPopupVisible;
                                   extern UIWindow *popupWindow;
                                   isPopupVisible = NO;
                                   popupWindow.hidden = YES;
                                   updateRedDotVisibility();
                                 }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
  } else {
    // No unsaved changes, close normally
    extern BOOL isPopupVisible;
    extern UIWindow *popupWindow;
    isPopupVisible = NO;
    popupWindow.hidden = YES;
    [self pauseQuickStartVideos];

    // Update red dot visibility when popup is closed
    updateRedDotVisibility();
  }
}

// Check if sensitivity values have changed from original
- (BOOL)hasSensitivityChanges {
  float currentBaseXY = [self.baseXYField.text floatValue];
  float currentLookX = [self.lookXField.text floatValue];
  float currentLookY = [self.lookYField.text floatValue];
  float currentScopeX = [self.scopeXField.text floatValue];
  float currentScopeY = [self.scopeYField.text floatValue];
  float currentScale = [self.scaleField.text floatValue];

  // Compare with original values (using small epsilon for float comparison)
  float epsilon = 0.01f;
  return (fabsf(currentBaseXY - self.originalBaseXY) > epsilon ||
          fabsf(currentLookX - self.originalLookX) > epsilon ||
          fabsf(currentLookY - self.originalLookY) > epsilon ||
          fabsf(currentScopeX - self.originalScopeX) > epsilon ||
          fabsf(currentScopeY - self.originalScopeY) > epsilon ||
          fabsf(currentScale - self.originalScale) > epsilon);
}

// Revert sensitivity fields to original values
- (void)revertSensitivityChanges {
  self.baseXYField.text =
      [NSString stringWithFormat:@"%.1f", self.originalBaseXY];
  self.lookXField.text =
      [NSString stringWithFormat:@"%.1f", self.originalLookX];
  self.lookYField.text =
      [NSString stringWithFormat:@"%.1f", self.originalLookY];
  self.scopeXField.text =
      [NSString stringWithFormat:@"%.1f", self.originalScopeX];
  self.scopeYField.text =
      [NSString stringWithFormat:@"%.1f", self.originalScopeY];
  self.scaleField.text =
      [NSString stringWithFormat:@"%.1f", self.originalScale];

  // Restore global variables
  BASE_XY_SENSITIVITY = self.originalBaseXY;
  LOOK_SENSITIVITY_X = self.originalLookX;
  LOOK_SENSITIVITY_Y = self.originalLookY;
  SCOPE_SENSITIVITY_X = self.originalScopeX;
  SCOPE_SENSITIVITY_Y = self.originalScopeY;
  MACOS_TO_PC_SCALE = self.originalScale;

  recalculateSensitivities();
}

- (void)closeButtonHover:(UIHoverGestureRecognizer *)gesture {
  // Show X on hover, hide when not hovering (like macOS)
  if (gesture.state == UIGestureRecognizerStateBegan ||
      gesture.state == UIGestureRecognizerStateChanged) {
    // Mouse is over the button - show X
    [UIView animateWithDuration:0.15
                     animations:^{
                       self.closeX.alpha = 1.0;
                     }];
  } else if (gesture.state == UIGestureRecognizerStateEnded ||
             gesture.state == UIGestureRecognizerStateCancelled) {
    // Mouse left the button - hide X
    [UIView animateWithDuration:0.15
                     animations:^{
                       self.closeX.alpha = 0.0;
                     }];
  }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
  extern UIWindow *popupWindow;
  if (!popupWindow) return;

  UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
  CGRect screenBounds = scene ? scene.effectiveGeometry.coordinateSpace.bounds : CGRectMake(0, 0, 390, 844);

  // Use translation delta — move the window by exactly how much the finger moved,
  // then reset to zero so each Changed event gives only the incremental delta.
  // This avoids any coordinate space feedback loop caused by the window moving.
  CGPoint delta = [gesture translationInView:nil];
  [gesture setTranslation:CGPointZero inView:nil];

  CGRect newFrame = popupWindow.frame;
  newFrame.origin.x += delta.x;
  newFrame.origin.y += delta.y;

  // Constrain to screen bounds (keep at least 40px of panel visible)
  CGFloat minVisible = 40;
  newFrame.origin.x = MAX(-newFrame.size.width + minVisible,
                          MIN(screenBounds.size.width - minVisible, newFrame.origin.x));
  newFrame.origin.y = MAX(-newFrame.size.height + minVisible,
                          MIN(screenBounds.size.height - minVisible, newFrame.origin.y));

  popupWindow.frame = newFrame;
}

// Apply default settings
- (void)applyDefaultsTapped:(UIButton *)sender {
  self.baseXYField.text = @"6.4";
  self.lookXField.text = @"50.0";
  self.lookYField.text = @"50.0";
  self.scopeXField.text = @"50.0";
  self.scopeYField.text = @"50.0";
  self.scaleField.text = @"20.0";

  BASE_XY_SENSITIVITY = 6.4f;
  LOOK_SENSITIVITY_X = 50.0f;
  LOOK_SENSITIVITY_Y = 50.0f;
  SCOPE_SENSITIVITY_X = 50.0f;
  SCOPE_SENSITIVITY_Y = 50.0f;
  MACOS_TO_PC_SCALE = 20.0f;

  recalculateSensitivities();

  NSDictionary *settings = @{
    kBaseXYKey : @(BASE_XY_SENSITIVITY),
    kLookXKey : @(LOOK_SENSITIVITY_X),
    kLookYKey : @(LOOK_SENSITIVITY_Y),
    kScopeXKey : @(SCOPE_SENSITIVITY_X),
    kScopeYKey : @(SCOPE_SENSITIVITY_Y),
    kScaleKey : @(MACOS_TO_PC_SCALE)
  };

  [[NSUserDefaults standardUserDefaults] setObject:settings
                                            forKey:kSettingsKey];

  // Update original values after applying defaults
  self.originalBaseXY = BASE_XY_SENSITIVITY;
  self.originalLookX = LOOK_SENSITIVITY_X;
  self.originalLookY = LOOK_SENSITIVITY_Y;
  self.originalScopeX = SCOPE_SENSITIVITY_X;
  self.originalScopeY = SCOPE_SENSITIVITY_Y;
  self.originalScale = MACOS_TO_PC_SCALE;

  // Update UI to reflect no changes
  [self updateSensitivityFieldBorders];
  [self updateSensitivityDiscardButton];

  [self showFeedback:@"Defaults Applied & Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

// Reset all sensitivity settings to defaults with confirmation
- (void)resetAllSensitivityTapped {
  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:@"Reset All Sensitivity?"
                       message:@"This will reset all sensitivity settings to "
                               @"recommended defaults"
                preferredStyle:UIAlertControllerStyleAlert];

  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
  [alert addAction:[UIAlertAction
                       actionWithTitle:@"Reset All"
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_Nonnull action) {
                                 // Apply default values
                                 self.baseXYField.text = @"6.4";
                                 self.lookXField.text = @"50.0";
                                 self.lookYField.text = @"50.0";
                                 self.scopeXField.text = @"50.0";
                                 self.scopeYField.text = @"50.0";
                                 self.scaleField.text = @"20.0";

                                 BASE_XY_SENSITIVITY = 6.4f;
                                 LOOK_SENSITIVITY_X = 50.0f;
                                 LOOK_SENSITIVITY_Y = 50.0f;
                                 SCOPE_SENSITIVITY_X = 50.0f;
                                 SCOPE_SENSITIVITY_Y = 50.0f;
                                 MACOS_TO_PC_SCALE = 20.0f;

                                 recalculateSensitivities();

                                 NSDictionary *settings = @{
                                   kBaseXYKey : @(BASE_XY_SENSITIVITY),
                                   kLookXKey : @(LOOK_SENSITIVITY_X),
                                   kLookYKey : @(LOOK_SENSITIVITY_Y),
                                   kScopeXKey : @(SCOPE_SENSITIVITY_X),
                                   kScopeYKey : @(SCOPE_SENSITIVITY_Y),
                                   kScaleKey : @(MACOS_TO_PC_SCALE)
                                 };

                                 [[NSUserDefaults standardUserDefaults]
                                     setObject:settings
                                        forKey:kSettingsKey];

                                 // Update original values after applying
                                 // defaults
                                 self.originalBaseXY = BASE_XY_SENSITIVITY;
                                 self.originalLookX = LOOK_SENSITIVITY_X;
                                 self.originalLookY = LOOK_SENSITIVITY_Y;
                                 self.originalScopeX = SCOPE_SENSITIVITY_X;
                                 self.originalScopeY = SCOPE_SENSITIVITY_Y;
                                 self.originalScale = MACOS_TO_PC_SCALE;

                                 // Update UI to reflect no changes
                                 [self updateSensitivityFieldBorders];
                                 [self updateSensitivityDiscardButton];

                                 [self showFeedback:
                                           @"All sensitivity reset to defaults"
                                              color:[UIColor colorWithRed:0.3
                                                                    green:0.9
                                                                     blue:0.3
                                                                    alpha:1.0]];
                               }]];

  [self presentViewController:alert animated:YES completion:nil];
}

// Save settings
- (void)saveButtonTapped:(UIButton *)sender {
  [self.view endEditing:YES];
  BASE_XY_SENSITIVITY = [self.baseXYField.text floatValue];
  LOOK_SENSITIVITY_X = [self.lookXField.text floatValue];
  LOOK_SENSITIVITY_Y = [self.lookYField.text floatValue];
  SCOPE_SENSITIVITY_X = [self.scopeXField.text floatValue];
  SCOPE_SENSITIVITY_Y = [self.scopeYField.text floatValue];
  MACOS_TO_PC_SCALE = [self.scaleField.text floatValue];

  recalculateSensitivities();

  NSDictionary *settings = @{
    kBaseXYKey : @(BASE_XY_SENSITIVITY),
    kLookXKey : @(LOOK_SENSITIVITY_X),
    kLookYKey : @(LOOK_SENSITIVITY_Y),
    kScopeXKey : @(SCOPE_SENSITIVITY_X),
    kScopeYKey : @(SCOPE_SENSITIVITY_Y),
    kScaleKey : @(MACOS_TO_PC_SCALE)
  };

  [[NSUserDefaults standardUserDefaults] setObject:settings
                                            forKey:kSettingsKey];

  // Update original values after successful save
  self.originalBaseXY = BASE_XY_SENSITIVITY;
  self.originalLookX = LOOK_SENSITIVITY_X;
  self.originalLookY = LOOK_SENSITIVITY_Y;
  self.originalScopeX = SCOPE_SENSITIVITY_X;
  self.originalScopeY = SCOPE_SENSITIVITY_Y;
  self.originalScale = MACOS_TO_PC_SCALE;

  // Update UI to reflect no changes
  [self updateSensitivityFieldBorders];
  [self updateSensitivityDiscardButton];

  [self showFeedback:@"Settings Saved"
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

// Show feedback message with animation
- (void)showFeedback:(NSString *)message color:(UIColor *)color {
  // Create center toast notification — height auto-fits the text
  CGFloat toastWidth = 240;
  CGFloat toastPadX = 16;
  CGFloat toastPadY = 14; // generous vertical breathing room

  // Measure the label text first so the toast can size itself around it
  NSString *fullText = [NSString stringWithFormat:@"%@ ✅", message];
  UILabel *messageLabel = [[UILabel alloc] init];
  messageLabel.text = fullText;
  messageLabel.textColor = color;
  messageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
  messageLabel.textAlignment = NSTextAlignmentCenter;
  messageLabel.numberOfLines = 0;

  // NSAttributedString for line-height
  NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
  para.lineSpacing = 4;
  para.alignment = NSTextAlignmentCenter;
  NSAttributedString *attrText =
      [[NSAttributedString alloc] initWithString:fullText
                                      attributes:@{
                                        NSFontAttributeName : messageLabel.font,
                                        NSParagraphStyleAttributeName : para
                                      }];
  messageLabel.attributedText = attrText;

  CGFloat labelWidth = toastWidth - toastPadX * 2;
  CGFloat labelHeight =
      [messageLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)].height;
  CGFloat toastHeight = labelHeight + toastPadY * 2;

  CGFloat centerX = self.view.bounds.size.width / 2 - toastWidth / 2;
  CGFloat centerY = self.view.bounds.size.height / 2 - toastHeight / 2;

  UIView *toast = [[UIView alloc]
      initWithFrame:CGRectMake(centerX, centerY, toastWidth, toastHeight)];
  toast.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
  toast.layer.cornerRadius = 12;
  toast.layer.borderWidth = 0.5;
  toast.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
  toast.alpha = 0;

  messageLabel.frame =
      CGRectMake(toastPadX, toastPadY, labelWidth, labelHeight);
  [toast addSubview:messageLabel];

  [self.view addSubview:toast];

  // Animate in
  [UIView animateWithDuration:0.3
      animations:^{
        toast.alpha = 1.0;
      }
      completion:^(BOOL finished) {
        // Hold for 2 seconds then fade out
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                         [UIView animateWithDuration:0.3
                             animations:^{
                               toast.alpha = 0;
                             }
                             completion:^(BOOL finished) {
                               [toast removeFromSuperview];
                             }];
                       });
      }];
}

// Validate text input
- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)string {
  // Static sets allocated once — not on every keystroke
  static NSCharacterSet *invalidChars = nil;
  if (!invalidChars) {
    NSCharacterSet *allowedChars =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    invalidChars = [allowedChars invertedSet];
  }

  if ([string rangeOfCharacterFromSet:invalidChars].location != NSNotFound) {
    return NO;
  }

  if ([textField.text containsString:@"."] && [string isEqualToString:@"."]) {
    return NO;
  }

  return YES;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Folder selection for Fortnite data directory
- (void)selectFolderTapped:(UIButton *)sender {
  if (@available(iOS 14.0, *)) {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[ UTTypeFolder ]
                                asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

// Text field change monitoring for sensitivity fields (called on every
// keystroke)
- (void)sensitivityFieldChanged:(UITextField *)textField {
  [self updateSensitivityDiscardButton];
  [self updateSensitivityFieldBorders];
}

// Update discard sensitivity button based on changes
- (void)updateSensitivityDiscardButton {
  int changeCount = 0;
  static float epsilon = 0.01f;

  if (fabsf([self.baseXYField.text floatValue] - self.originalBaseXY) > epsilon)
    changeCount++;
  if (fabsf([self.lookXField.text floatValue] - self.originalLookX) > epsilon)
    changeCount++;
  if (fabsf([self.lookYField.text floatValue] - self.originalLookY) > epsilon)
    changeCount++;
  if (fabsf([self.scopeXField.text floatValue] - self.originalScopeX) > epsilon)
    changeCount++;
  if (fabsf([self.scopeYField.text floatValue] - self.originalScopeY) > epsilon)
    changeCount++;
  if (fabsf([self.scaleField.text floatValue] - self.originalScale) > epsilon)
    changeCount++;

  // Always update button titles (cheap string set)
  [self.applySensitivityButton
      setTitle:[NSString stringWithFormat:@"Apply Changes (%d)", changeCount]
      forState:UIControlStateNormal];
  [self.discardSensitivityButton
      setTitle:[NSString stringWithFormat:@"Discard Changes (%d)", changeCount]
      forState:UIControlStateNormal];

  // Only animate when the enabled/disabled state actually flips — not on every
  // keystroke
  BOOL shouldEnable = (changeCount > 0);
  if (shouldEnable != self.applySensitivityButton.enabled) {
    self.discardSensitivityButton.enabled = shouldEnable;
    self.applySensitivityButton.enabled = shouldEnable;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.discardSensitivityButton.alpha =
                           shouldEnable ? 1.0 : 0.3;
                       self.applySensitivityButton.alpha =
                           shouldEnable ? 1.0 : 0.5;
                     }];
  }
}

// Helper to apply "Custom vs Default" styling (based on SAVED value)
- (void)applyStyleToField:(UITextField *)field
                    saved:(float)savedVal
               defaultVal:(float)defaultVal {
  float epsilon = 0.01f;
  BOOL isNotDefault = fabsf(savedVal - defaultVal) > epsilon;

  if (isNotDefault) {
    // Custom: White background, Black text (matching keybinds)
    field.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    field.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
  } else {
    // Default: Dark background, White text
    field.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    field.textColor = [UIColor whiteColor];
  }
}

// Update yellow borders and background/text colors on sensitivity fields
- (void)updateSensitivityFieldBorders {
  float epsilon = 0.01f;
  UIColor *yellowBorder = [UIColor colorWithRed:1.0
                                          green:0.9
                                           blue:0.3
                                          alpha:1.0];
  UIColor *normalBorder = [UIColor colorWithWhite:0.25 alpha:0.4];

  // Base XY field
  float baseVal = [self.baseXYField.text floatValue];
  BOOL baseChanged = fabsf(baseVal - self.originalBaseXY) > epsilon;
  self.baseXYField.layer.borderWidth = baseChanged ? 2.5 : 0.5;
  self.baseXYField.layer.borderColor =
      baseChanged ? yellowBorder.CGColor : normalBorder.CGColor;
  [self applyStyleToField:self.baseXYField
                    saved:self.originalBaseXY
               defaultVal:6.4f];

  // Look X field
  float lookXVal = [self.lookXField.text floatValue];
  BOOL lookXChanged = fabsf(lookXVal - self.originalLookX) > epsilon;
  self.lookXField.layer.borderWidth = lookXChanged ? 2.5 : 0.5;
  self.lookXField.layer.borderColor =
      lookXChanged ? yellowBorder.CGColor : normalBorder.CGColor;
  [self applyStyleToField:self.lookXField
                    saved:self.originalLookX
               defaultVal:50.0f];

  // Look Y field
  float lookYVal = [self.lookYField.text floatValue];
  BOOL lookYChanged = fabsf(lookYVal - self.originalLookY) > epsilon;
  self.lookYField.layer.borderWidth = lookYChanged ? 2.5 : 0.5;
  self.lookYField.layer.borderColor =
      lookYChanged ? yellowBorder.CGColor : normalBorder.CGColor;
  [self applyStyleToField:self.lookYField
                    saved:self.originalLookY
               defaultVal:50.0f];

  // Scope X field
  float scopeXVal = [self.scopeXField.text floatValue];
  BOOL scopeXChanged = fabsf(scopeXVal - self.originalScopeX) > epsilon;
  self.scopeXField.layer.borderWidth = scopeXChanged ? 2.5 : 0.5;
  self.scopeXField.layer.borderColor =
      scopeXChanged ? yellowBorder.CGColor : normalBorder.CGColor;
  [self applyStyleToField:self.scopeXField
                    saved:self.originalScopeX
               defaultVal:50.0f];

  // Scope Y field
  float scopeYVal = [self.scopeYField.text floatValue];
  BOOL scopeYChanged = fabsf(scopeYVal - self.originalScopeY) > epsilon;
  self.scopeYField.layer.borderWidth = scopeYChanged ? 2.5 : 0.5;
  self.scopeYField.layer.borderColor =
      scopeYChanged ? yellowBorder.CGColor : normalBorder.CGColor;
  [self applyStyleToField:self.scopeYField
                    saved:self.originalScopeY
               defaultVal:50.0f];

  // Scale field
  float scaleVal = [self.scaleField.text floatValue];
  BOOL scaleChanged = fabsf(scaleVal - self.originalScale) > epsilon;
  self.scaleField.layer.borderWidth = scaleChanged ? 2.5 : 0.5;
  self.scaleField.layer.borderColor =
      scaleChanged ? yellowBorder.CGColor : normalBorder.CGColor;
  [self applyStyleToField:self.scaleField
                    saved:self.originalScale
               defaultVal:20.0f];
}

// Discard sensitivity changes
- (void)discardSensitivityChangesTapped {
  [self.view endEditing:YES];
  if (![self hasSensitivityChanges])
    return;

  // Revert to saved values
  [self revertSensitivityChanges];

  // Update buttons and borders
  [self updateSensitivityDiscardButton];
  [self updateSensitivityFieldBorders];

  // Show feedback
  [self showFeedback:@"Changes Discarded"
               color:[UIColor colorWithRed:1.0 green:0.9 blue:0.3 alpha:1.0]];
}

// Reset a single sensitivity section to its default values
// accessibilityLabel: "fieldKey:defaultValue,..." — accessibilityHint: section
// title
- (void)resetSectionTapped:(UIButton *)sender {
  NSString *encoded = sender.accessibilityLabel;
  if (!encoded || encoded.length == 0)
    return;

  NSString *sectionTitle = sender.accessibilityHint ?: @"Section";

  // Safe field lookup — avoids KVC crashes for unknown keys
  NSDictionary *fieldMap = @{
    @"baseXYField" : self.baseXYField,
    @"lookXField" : self.lookXField,
    @"lookYField" : self.lookYField,
    @"scopeXField" : self.scopeXField,
    @"scopeYField" : self.scopeYField,
    @"scaleField" : self.scaleField,
  };

  NSMutableArray *defaultStrings = [NSMutableArray array];
  NSArray *pairs = [encoded componentsSeparatedByString:@","];
  for (NSString *pair in pairs) {
    // Split on first ":" only so decimal points in the value are safe
    NSRange colonRange = [pair rangeOfString:@":"];
    if (colonRange.location == NSNotFound)
      continue;
    NSString *fieldKey = [pair substringToIndex:colonRange.location];
    NSString *valStr = [pair substringFromIndex:colonRange.location + 1];
    float defaultVal = [valStr floatValue];

    UITextField *field = fieldMap[fieldKey];
    if (field) {
      field.text = [NSString stringWithFormat:@"%.1f", defaultVal];
      [defaultStrings
          addObject:[NSString stringWithFormat:@"%.1f", defaultVal]];
    }

    // Apply default to the corresponding global and originalXxx so the yellow
    // border clears and the value is persisted immediately.
    if ([fieldKey isEqualToString:@"baseXYField"]) {
      BASE_XY_SENSITIVITY = defaultVal;
      self.originalBaseXY = defaultVal;
    } else if ([fieldKey isEqualToString:@"lookXField"]) {
      LOOK_SENSITIVITY_X = defaultVal;
      self.originalLookX = defaultVal;
    } else if ([fieldKey isEqualToString:@"lookYField"]) {
      LOOK_SENSITIVITY_Y = defaultVal;
      self.originalLookY = defaultVal;
    } else if ([fieldKey isEqualToString:@"scopeXField"]) {
      SCOPE_SENSITIVITY_X = defaultVal;
      self.originalScopeX = defaultVal;
    } else if ([fieldKey isEqualToString:@"scopeYField"]) {
      SCOPE_SENSITIVITY_Y = defaultVal;
      self.originalScopeY = defaultVal;
    } else if ([fieldKey isEqualToString:@"scaleField"]) {
      MACOS_TO_PC_SCALE = defaultVal;
      self.originalScale = defaultVal;
    }
  }

  // Persist the full current state (including the newly reset fields) to
  // NSUserDefaults
  recalculateSensitivities();
  NSDictionary *settings = @{
    kBaseXYKey : @(BASE_XY_SENSITIVITY),
    kLookXKey : @(LOOK_SENSITIVITY_X),
    kLookYKey : @(LOOK_SENSITIVITY_Y),
    kScopeXKey : @(SCOPE_SENSITIVITY_X),
    kScopeYKey : @(SCOPE_SENSITIVITY_Y),
    kScaleKey : @(MACOS_TO_PC_SCALE)
  };
  [[NSUserDefaults standardUserDefaults] setObject:settings
                                            forKey:kSettingsKey];

  // Refresh border highlights and discard button count
  [self updateSensitivityDiscardButton];
  [self updateSensitivityFieldBorders];

  // e.g. "Hip-Fire (Look) reset to 50.0 / 50.0"
  NSString *defaultsStr = [defaultStrings componentsJoinedByString:@" / "];
  NSString *feedback =
      [NSString stringWithFormat:@"%@ reset to %@", sectionTitle, defaultsStr];
  [self showFeedback:feedback
               color:[UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0]];
}

// Export settings to JSON file
- (void)exportSettings {
  // Gather all settings
  NSMutableDictionary *exportData = [NSMutableDictionary dictionary];

  // Sensitivity settings
  exportData[@"sensitivity"] = @{
    @"baseXY" : @(BASE_XY_SENSITIVITY),
    @"lookX" : @(LOOK_SENSITIVITY_X),
    @"lookY" : @(LOOK_SENSITIVITY_Y),
    @"scopeX" : @(SCOPE_SENSITIVITY_X),
    @"scopeY" : @(SCOPE_SENSITIVITY_Y),
    @"scale" : @(MACOS_TO_PC_SCALE)
  };

  // Fortnite Default Keybinds (from keybinds tab - BUILDING, MOVEMENT, etc.)
  NSDictionary *fortniteBinds = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:@"fortniteKeybinds"];
  if (fortniteBinds && fortniteBinds.count > 0) {
    // Ensure values are JSON-compatible (convert NSNumbers to integers/strings)
    NSMutableDictionary *cleanedFortniteBinds =
        [NSMutableDictionary dictionary];
    for (NSString *action in fortniteBinds) {
      id value = fortniteBinds[action];
      if ([value isKindOfClass:[NSNumber class]]) {
        cleanedFortniteBinds[action] = value; // NSNumber is JSON compatible
      } else if ([value isKindOfClass:[NSString class]]) {
        cleanedFortniteBinds[action] =
            @([value integerValue]); // Convert string to number
      }
    }
    exportData[@"fortniteKeybinds"] = cleanedFortniteBinds;
  }

  // Custom Keybinds/Remaps (from keybinds tab - advanced custom section)
  // Try both: the global keyRemappings dictionary and UserDefaults
  NSMutableDictionary *customRemaps = [NSMutableDictionary dictionary];

  // Get from UserDefaults (these should already be string keys)
  NSDictionary *savedRemaps =
      [[NSUserDefaults standardUserDefaults] dictionaryForKey:kKeyRemapKey];
  if (savedRemaps && savedRemaps.count > 0) {
    // Convert to string keys to ensure JSON compatibility
    for (id key in savedRemaps) {
      NSString *stringKey =
          [key isKindOfClass:[NSString class]] ? key : [key stringValue];
      id value = savedRemaps[key];
      NSString *stringValue =
          [value isKindOfClass:[NSString class]] ? value : [value stringValue];
      customRemaps[stringKey] = stringValue;
    }
  }

  // Also get from global keyRemappings in case UserDefaults isn't synced yet
  if (keyRemappings && keyRemappings.count > 0) {
    for (NSNumber *sourceKey in keyRemappings) {
      NSNumber *targetKey = keyRemappings[sourceKey];
      // Convert NSNumber to string for JSON compatibility
      NSString *sourceKeyStr = [sourceKey stringValue];
      NSString *targetKeyStr = [targetKey stringValue];
      customRemaps[sourceKeyStr] = targetKeyStr;
    }
  }

  if (customRemaps.count > 0) {
    exportData[@"customRemaps"] = customRemaps;
  }

  // Metadata
  exportData[@"version"] = @"1.0";
  exportData[@"exportDate"] = [[NSDate date] description];

  // Convert to JSON
  NSError *error = nil;
  NSData *jsonData =
      [NSJSONSerialization dataWithJSONObject:exportData
                                      options:NSJSONWritingPrettyPrinted
                                        error:&error];

  if (error || !jsonData) {
    [self showFeedback:@"Export Failed" color:[UIColor redColor]];
    return;
  }

  // Store data for saving
  self.exportData = jsonData;

  // Generate filename with timestamp
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
  NSString *timestamp = [formatter stringFromDate:[NSDate date]];
  self.exportFileName =
      [NSString stringWithFormat:@"FnMacTweak_Settings_%@.json", timestamp];

  // Create temporary file URL
  NSString *tempPath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:self.exportFileName];
  NSURL *tempURL = [NSURL fileURLWithPath:tempPath];

  // Write temporary file
  BOOL writeSuccess = [self.exportData writeToURL:tempURL atomically:YES];
  if (!writeSuccess) {
    [self showFeedback:@"Export Failed" color:[UIColor redColor]];
    return;
  }

  // Present document picker to select save location
  if (@available(iOS 14.0, *)) {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForExportingURLs:@[ tempURL ]
                          asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

// Import settings from JSON file
- (void)importSettings {
  if (@available(iOS 14.0, *)) {
    // Create document picker for JSON files - use both JSON and plain text
    // types
    NSArray *contentTypes = @[ UTTypeJSON ];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:contentTypes
                                asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

// Handle imported file or export completion
- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if (urls.count == 0)
    return;

  NSURL *url = urls.firstObject;
  NSString *pathExtension = url.pathExtension.lowercaseString;

  // Check if this is a settings file (JSON) - could be import or export
  if ([pathExtension isEqualToString:@"json"]) {
    // Determine if this is export completion or import by checking if the file
    // is in a temp/export location Export completion: URL will have a new
    // location that's not in temp (user chose save location) Import: URL will
    // be from user's file system (they're selecting an existing file)

    // We can distinguish by checking the directory mode
    // If it's from the export picker, the URL path won't be in
    // NSTemporaryDirectory and won't be accessible for reading without security
    // scoped access

    // Try to access - if we can start security scoped access, it's an import
    if ([url startAccessingSecurityScopedResource]) {
      NSError *error = nil;
      NSData *jsonData = [NSData dataWithContentsOfURL:url
                                               options:0
                                                 error:&error];
      [url stopAccessingSecurityScopedResource];

      if (error || !jsonData) {
        [self showFeedback:@"Import Failed" color:[UIColor redColor]];
        return;
      }

      NSDictionary *importData =
          [NSJSONSerialization JSONObjectWithData:jsonData
                                          options:0
                                            error:&error];

      if (error || !importData) {
        [self showFeedback:@"Invalid Settings File" color:[UIColor redColor]];
        return;
      }

      // Apply sensitivity settings
      if (importData[@"sensitivity"]) {
        NSDictionary *sensitivity = importData[@"sensitivity"];
        BASE_XY_SENSITIVITY = [sensitivity[@"baseXY"] floatValue] ?: 6.4f;
        LOOK_SENSITIVITY_X = [sensitivity[@"lookX"] floatValue] ?: 50.0f;
        LOOK_SENSITIVITY_Y = [sensitivity[@"lookY"] floatValue] ?: 50.0f;
        SCOPE_SENSITIVITY_X = [sensitivity[@"scopeX"] floatValue] ?: 50.0f;
        SCOPE_SENSITIVITY_Y = [sensitivity[@"scopeY"] floatValue] ?: 50.0f;
        MACOS_TO_PC_SCALE = [sensitivity[@"scale"] floatValue] ?: 20.0f;

        // Recalculate and save
        recalculateSensitivities();
        NSDictionary *settings = @{
          kBaseXYKey : @(BASE_XY_SENSITIVITY),
          kLookXKey : @(LOOK_SENSITIVITY_X),
          kLookYKey : @(LOOK_SENSITIVITY_Y),
          kScopeXKey : @(SCOPE_SENSITIVITY_X),
          kScopeYKey : @(SCOPE_SENSITIVITY_Y),
          kScaleKey : @(MACOS_TO_PC_SCALE)
        };
        [[NSUserDefaults standardUserDefaults] setObject:settings
                                                  forKey:kSettingsKey];

        // Update UI fields
        self.baseXYField.text =
            [NSString stringWithFormat:@"%.1f", BASE_XY_SENSITIVITY];
        self.lookXField.text =
            [NSString stringWithFormat:@"%.1f", LOOK_SENSITIVITY_X];
        self.lookYField.text =
            [NSString stringWithFormat:@"%.1f", LOOK_SENSITIVITY_Y];
        self.scopeXField.text =
            [NSString stringWithFormat:@"%.1f", SCOPE_SENSITIVITY_X];
        self.scopeYField.text =
            [NSString stringWithFormat:@"%.1f", SCOPE_SENSITIVITY_Y];
        self.scaleField.text =
            [NSString stringWithFormat:@"%.1f", MACOS_TO_PC_SCALE];

        // Update original values
        self.originalBaseXY = BASE_XY_SENSITIVITY;
        self.originalLookX = LOOK_SENSITIVITY_X;
        self.originalLookY = LOOK_SENSITIVITY_Y;
        self.originalScopeX = SCOPE_SENSITIVITY_X;
        self.originalScopeY = SCOPE_SENSITIVITY_Y;
        self.originalScale = MACOS_TO_PC_SCALE;

        [self updateSensitivityDiscardButton];
        [self updateSensitivityFieldBorders];
      }

      // Apply Fortnite Default Keybinds
      if (importData[@"fortniteKeybinds"]) {
        NSDictionary *fortniteBinds = importData[@"fortniteKeybinds"];
        [[NSUserDefaults standardUserDefaults] setObject:fortniteBinds
                                                  forKey:@"fortniteKeybinds"];
        // NSUserDefaults auto-syncs — explicit synchronize removed
        loadFortniteKeybinds();
        [self refreshFortniteKeybinds]; // Refresh UI to show imported keybinds
      }

      // Apply Custom Remaps
      if (importData[@"customRemaps"]) {
        NSDictionary *customRemaps = importData[@"customRemaps"];
        [[NSUserDefaults standardUserDefaults] setObject:customRemaps
                                                  forKey:kKeyRemapKey];
        // NSUserDefaults auto-syncs — explicit synchronize removed
        loadKeyRemappings();
        [self refreshKeyRemapRows];
        [self updateApplyChangesButton];
      }

      // Backward compatibility: handle old "keybinds" key (treat as custom
      // remaps)
      if (importData[@"keybinds"] && !importData[@"customRemaps"]) {
        NSDictionary *keybinds = importData[@"keybinds"];
        [[NSUserDefaults standardUserDefaults] setObject:keybinds
                                                  forKey:kKeyRemapKey];
        // NSUserDefaults auto-syncs — explicit synchronize removed
        loadKeyRemappings();
        [self refreshKeyRemapRows];
        [self updateApplyChangesButton];
      }

      [[NSUserDefaults standardUserDefaults] synchronize];
      [self showFeedback:@"Settings Imported Successfully"
                   color:[UIColor colorWithRed:0.3
                                         green:0.9
                                          blue:0.3
                                         alpha:1.0]];
    } else {
      // Export completion (couldn't get security scoped access - it's the
      // export result)
      [self showFeedback:@"Settings Exported Successfully"
                   color:[UIColor colorWithRed:0.3
                                         green:0.9
                                          blue:0.3
                                         alpha:1.0]];
    }
  } else {
    // Folder selection (Container tab - original behavior)
    if ([url startAccessingSecurityScopedResource]) {
      NSError *error = nil;
      NSURLBookmarkCreationOptions options =
          (NSURLBookmarkCreationOptions)(1 << 11);
      NSData *bookmark = [url bookmarkDataWithOptions:options
                       includingResourceValuesForKeys:nil
                                        relativeToURL:nil
                                                error:&error];

      if (bookmark) {
        [[NSUserDefaults standardUserDefaults]
            setObject:bookmark
               forKey:@"fnmactweak.datafolder"];
        // NSUserDefaults auto-syncs — explicit synchronize removed

        [self showFeedback:@"Restarting..."
                     color:[UIColor colorWithRed:1.0
                                           green:0.5
                                            blue:0.0
                                           alpha:1.0]];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
                         exit(0);
                       });
      }

      [url stopAccessingSecurityScopedResource];
    }
  }
}

// Handle export/import cancellation
- (void)documentPickerWasCancelled:
    (UIDocumentPickerViewController *)controller {
  // Just dismiss, no feedback needed for cancel
}

@end
