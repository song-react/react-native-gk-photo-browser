#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <GKPhotoBrowser/GKPhotoBrowser.h>
#import <SDWebImage/SDWebImageDownloader.h>
#import <UIKit/UIKit.h>

#include "GKPhotoBrowserImpl.hpp"

using namespace margelo::nitro::gkphotobrowser;

static NSString *const GKRNPhotoBrowserForwardNotification = @"gkPhotoBrowserForward";

template <typename Fn>
static inline void GKRNRunOnMainSync(Fn &&fn) {
  if ([NSThread isMainThread]) {
    fn();
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    fn();
  });
}

static NSString *_Nullable GKRNStringFromOptional(const std::optional<std::string> &value) {
  if (!value.has_value()) return nil;
  return [[NSString alloc] initWithUTF8String:value->c_str()];
}

static NSURL *_Nullable GKRNMakeURL(NSString *value) {
  if (value.length == 0) return nil;
  if ([value hasPrefix:@"/"]) {
    return [NSURL fileURLWithPath:value];
  }

  NSURL *url = [NSURL URLWithString:value];
  if (url != nil) return url;

  NSString *encoded = [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
  if (encoded.length == 0) return nil;
  return [NSURL URLWithString:encoded];
}

static UIImage *_Nullable GKRNLoadImage(NSString *value) {
  NSURL *url = GKRNMakeURL(value);
  if (url == nil) return nil;

  if (url.isFileURL) {
    return [UIImage imageWithContentsOfFile:url.path];
  }

  NSData *data = [NSData dataWithContentsOfURL:url];
  if (data == nil) return nil;
  return [UIImage imageWithData:data];
}

static NSDictionary<NSString *, NSString *> *_Nullable GKRNParseHeadersJson(NSString *json) {
  if (json.length == 0) return nil;
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) return nil;

  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error != nil || ![object isKindOfClass:[NSDictionary class]]) return nil;

  NSDictionary *raw = (NSDictionary *)object;
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionaryWithCapacity:raw.count];
  [raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
    if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
      headers[(NSString *)key] = (NSString *)value;
    }
  }];
  return headers.count > 0 ? headers : nil;
}

static UIViewController *_Nullable GKRNTopViewController(UIViewController *_Nullable base) {
  if ([base isKindOfClass:[UINavigationController class]]) {
    UINavigationController *navigation = (UINavigationController *)base;
    return GKRNTopViewController(navigation.visibleViewController);
  }
  if ([base isKindOfClass:[UITabBarController class]]) {
    UITabBarController *tab = (UITabBarController *)base;
    return GKRNTopViewController(tab.selectedViewController);
  }
  if (base.presentedViewController != nil) {
    return GKRNTopViewController(base.presentedViewController);
  }
  return base;
}

static UIViewController *_Nullable GKRNCurrentTopViewController(void) {
  UIWindow *keyWindow = nil;
  NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;
  for (UIScene *scene in scenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    for (UIWindow *window in windowScene.windows) {
      if (window.isKeyWindow) {
        keyWindow = window;
        break;
      }
    }
    if (keyWindow != nil) break;
  }
  if (keyWindow == nil) {
    keyWindow = UIApplication.sharedApplication.windows.lastObject;
  }
  return GKRNTopViewController(keyWindow.rootViewController);
}

@interface GKRNPhotoBrowserCover : NSObject <GKCoverViewProtocol>
@property(nonatomic, weak, nullable) GKPhotoBrowser *browser;
@property(nonatomic, weak, nullable) GKPhoto *photo;
@property(nonatomic, assign) BOOL showCloseButton;
@property(nonatomic, assign) BOOL showDownloadButton;
@property(nonatomic, assign) BOOL showForwardButton;
- (void)setActionButtonsHiddenByPan:(BOOL)hidden;
- (void)setActionButtonsHiddenByDismiss:(BOOL)hidden;
@end

@interface GKRNAVPlayerView : UIView
@end

@implementation GKRNAVPlayerView
+ (Class)layerClass {
  return AVPlayerLayer.class;
}
@end

static void *GKRNPlayerStatusContext = &GKRNPlayerStatusContext;
static void *GKRNPlayerBufferEmptyContext = &GKRNPlayerBufferEmptyContext;
static void *GKRNPlayerKeepUpContext = &GKRNPlayerKeepUpContext;
static void *GKRNPlayerPresentationSizeContext = &GKRNPlayerPresentationSizeContext;

@interface GKRNAVPlayerManager : NSObject <GKVideoPlayerProtocol>
@property(nonatomic, weak, nullable) GKPhotoBrowser *browser;
@property(nonatomic, weak, nullable) GKPhoto *photo;
@property(nonatomic, weak, nullable) UIImage *coverImage;
@property(nonatomic, strong, nullable) UIView *videoPlayView;
@property(nonatomic, strong, nullable) NSURL *assetURL;
@property(nonatomic, strong, nullable) NSError *error;
@property(nonatomic, copy) void (^playerStatusChange)(id<GKVideoPlayerProtocol> mgr, GKVideoPlayerStatus status);
@property(nonatomic, copy) void (^playerPlayTimeChange)(id<GKVideoPlayerProtocol> mgr, NSTimeInterval currentTime, NSTimeInterval totalTime);
@property(nonatomic, copy) void (^playerGetVideoSize)(id<GKVideoPlayerProtocol> mgr, CGSize size);
@property(nonatomic, assign, readwrite) BOOL isPlaying;
@property(nonatomic, assign, readwrite) NSTimeInterval currentTime;
@property(nonatomic, assign, readwrite) NSTimeInterval totalTime;
@property(nonatomic, assign, readwrite) GKVideoPlayerStatus status;
@property(nonatomic, strong, nullable) AVPlayer *player;
@property(nonatomic, strong, nullable) AVPlayerItem *observingItem;
@property(nonatomic, strong, nullable) id timeObserver;
@property(nonatomic, strong, nullable) id endObserver;
@property(nonatomic, strong, nullable) id resignActiveObserver;
@property(nonatomic, strong, nullable) id didBecomeActiveObserver;
@property(nonatomic, strong, nullable) NSURLSessionDownloadTask *downloadTask;
@property(nonatomic, assign) BOOL shouldPlayWhenReady;
@property(nonatomic, assign) BOOL wasPlayingBeforeBackground;
@property(nonatomic, assign) NSTimeInterval seekTime;
@property(nonatomic, copy, nullable) void (^seekCompletion)(BOOL finished);
@end

@interface GKPhotoBrowserDelegateProxy : NSObject <GKPhotoBrowserDelegate>
@property(nonatomic, assign) void *owner;
@end

namespace margelo::nitro::gkphotobrowser {
class GKPhotoBrowserRuntime {
 public:
  GKPhotoBrowserRuntime();
  ~GKPhotoBrowserRuntime();

  void show(const BrowserConfig &config,
            const std::function<void()> &onDismiss,
            const std::function<void(double)> &onDownload,
            const std::function<void(double)> &onForward);
  void dismiss();

  void handleDownload(NSInteger index);
  void handleForward(NSInteger index);
  void handleDidDisappear();
  void handlePanBegin();
  void handlePanEnded(BOOL willDisappear);
  void handleDismissWillStart();

 private:
  void showOnMain(const BrowserConfig &config,
                  const std::function<void()> &onDismiss,
                  const std::function<void(double)> &onDownload,
                  const std::function<void(double)> &onForward);
  void dismissOnMain();
  GKPhoto *_Nullable makePhoto(const BrowserImage &image);
  void installImageHeaders(const std::vector<BrowserImage> &images);
  void installForwardObserver();
  void removeForwardObserver();
  GKPhotoBrowserShowStyle mapShowStyle(const std::optional<std::string> &value);
  GKPhotoBrowserHideStyle mapHideStyle(const std::optional<std::string> &value);
  GKPhotoBrowserLoadStyle mapLoadStyle(const std::optional<std::string> &value);

 private:
  __strong GKPhotoBrowser *browser_ = nil;
  __strong GKPhotoBrowserDelegateProxy *delegateProxy_ = nil;
  __strong id forwardObserver_ = nil;
  __strong GKRNPhotoBrowserCover *cover_ = nil;
  std::function<void()> onDismissCallback_;
  std::function<void(double)> onDownloadCallback_;
  std::function<void(double)> onForwardCallback_;
  bool shouldNotifyDismiss_ = true;
};
} // namespace margelo::nitro::gkphotobrowser

static inline margelo::nitro::gkphotobrowser::GKPhotoBrowserRuntime *_Nullable GKRNRuntimeFromOwner(void *owner) {
  return static_cast<margelo::nitro::gkphotobrowser::GKPhotoBrowserRuntime *>(owner);
}

@implementation GKPhotoBrowserDelegateProxy
- (void)photoBrowser:(GKPhotoBrowser *)browser onSaveBtnClick:(NSInteger)index image:(UIImage *)image {
  auto *owner = GKRNRuntimeFromOwner(self.owner);
  if (owner != nullptr) {
    owner->handleDownload(index);
  }
}

- (void)photoBrowser:(GKPhotoBrowser *)browser didDisappearAtIndex:(NSInteger)index {
  auto *owner = GKRNRuntimeFromOwner(self.owner);
  if (owner != nullptr) {
    owner->handleDidDisappear();
  }
}

- (void)photoBrowser:(GKPhotoBrowser *)browser panBeginWithIndex:(NSInteger)index {
  auto *owner = GKRNRuntimeFromOwner(self.owner);
  if (owner != nullptr) {
    owner->handlePanBegin();
  }
}

- (void)photoBrowser:(GKPhotoBrowser *)browser panEndedWithIndex:(NSInteger)index willDisappear:(BOOL)disappear {
  auto *owner = GKRNRuntimeFromOwner(self.owner);
  if (owner != nullptr) {
    owner->handlePanEnded(disappear);
  }
}

- (void)photoBrowser:(GKPhotoBrowser *)browser singleTapWithIndex:(NSInteger)index {
  auto *owner = GKRNRuntimeFromOwner(self.owner);
  if (owner != nullptr) {
    owner->handleDismissWillStart();
  }
}
@end

namespace margelo::nitro::gkphotobrowser {

GKPhotoBrowserRuntime::GKPhotoBrowserRuntime() {
  delegateProxy_ = [GKPhotoBrowserDelegateProxy new];
  delegateProxy_.owner = this;
}

GKPhotoBrowserRuntime::~GKPhotoBrowserRuntime() {
  GKRNRunOnMainSync([this] {
    delegateProxy_.owner = nullptr;
    removeForwardObserver();
    browser_ = nil;
    cover_ = nil;
    onDismissCallback_ = nullptr;
    onDownloadCallback_ = nullptr;
    onForwardCallback_ = nullptr;
  });
}

void GKPhotoBrowserRuntime::show(const BrowserConfig &config,
                                 const std::function<void()> &onDismiss,
                                 const std::function<void(double)> &onDownload,
                                 const std::function<void(double)> &onForward) {
  BrowserConfig configCopy = config;
  auto onDismissCopy = onDismiss;
  auto onDownloadCopy = onDownload;
  auto onForwardCopy = onForward;

  GKRNRunOnMainSync([this, configCopy, onDismissCopy, onDownloadCopy, onForwardCopy] {
    showOnMain(configCopy, onDismissCopy, onDownloadCopy, onForwardCopy);
  });
}

void GKPhotoBrowserRuntime::dismiss() {
  GKRNRunOnMainSync([this] {
    dismissOnMain();
  });
}

void GKPhotoBrowserRuntime::showOnMain(const BrowserConfig &config,
                                       const std::function<void()> &onDismiss,
                                       const std::function<void(double)> &onDownload,
                                       const std::function<void(double)> &onForward) {
  shouldNotifyDismiss_ = true;
  onDismissCallback_ = onDismiss;
  onDownloadCallback_ = onDownload;
  onForwardCallback_ = onForward;

  if (browser_ != nil) {
    shouldNotifyDismiss_ = false;
    [browser_ dismiss];
    shouldNotifyDismiss_ = true;
    browser_ = nil;
  }

  NSMutableArray<GKPhoto *> *photos = [NSMutableArray arrayWithCapacity:config.images.size()];
  for (const BrowserImage &image : config.images) {
    GKPhoto *photo = makePhoto(image);
    if (photo != nil) {
      [photos addObject:photo];
    }
  }

  UIViewController *viewController = GKRNCurrentTopViewController();
  if (photos.count == 0 || viewController == nil) {
    if (onDismissCallback_) {
      onDismissCallback_();
    }
    return;
  }

  NSInteger index = (NSInteger)config.currentIndex.value_or(0);
  if (index < 0) index = 0;
  if (index >= photos.count) index = photos.count - 1;

  GKPhotoBrowser *browser = [[GKPhotoBrowser alloc] initWithPhotos:photos currentIndex:index];
  GKPhotoBrowserConfigure *configure = browser.configure;
  browser.delegate = delegateProxy_;

  configure.showStyle = mapShowStyle(config.showStyle);
  configure.hideStyle = mapHideStyle(config.hideStyle);
  configure.loadStyle = mapLoadStyle(config.loadStyle);
  configure.originLoadStyle = mapLoadStyle(config.originLoadStyle);
  configure.maxZoomScale = (CGFloat)config.maxZoomScale.value_or(20);
  configure.doubleZoomScale = (CGFloat)config.doubleZoomScale.value_or(2);
  configure.hidesCountLabel = config.hidesCountLabel.value_or(true);
  configure.hidesPageControl = !config.showsPageControl.value_or(true);
  configure.hidesSavedBtn = !config.showDownloadButton.value_or(false);
  configure.isAdaptiveSafeArea = config.isAdaptiveSafeArea.value_or(false);
  configure.isFollowSystemRotation = config.isFollowSystemRotation.value_or(false);

  GKRNAVPlayerManager *playerManager = [GKRNAVPlayerManager new];
  [configure setupVideoPlayerProtocol:playerManager];

  GKRNPhotoBrowserCover *cover = [GKRNPhotoBrowserCover new];
  cover.showCloseButton = config.showCloseButton.value_or(true);
  cover.showDownloadButton = config.showDownloadButton.value_or(false);
  cover.showForwardButton = config.showForwardButton.value_or(false);
  [configure setupCoverProtocol:cover];
  cover_ = cover;

  installImageHeaders(config.images);
  browser_ = browser;
  installForwardObserver();

  [browser showFromVC:viewController];
}

void GKPhotoBrowserRuntime::dismissOnMain() {
  removeForwardObserver();
  [cover_ setActionButtonsHiddenByDismiss:YES];
  [browser_ dismiss];
  browser_ = nil;
  cover_ = nil;
}

GKPhoto *_Nullable GKPhotoBrowserRuntime::makePhoto(const BrowserImage &image) {
  GKPhoto *photo = [GKPhoto new];
  NSURL *videoURL = nil;
  NSDictionary<NSString *, NSString *> *headers = nil;

  NSString *videoUri = GKRNStringFromOptional(image.videoUri);
  if (videoUri.length > 0) {
    videoURL = GKRNMakeURL(videoUri);
  }

  NSString *headersJson = GKRNStringFromOptional(image.headersJson);
  if (headersJson.length > 0) {
    headers = GKRNParseHeadersJson(headersJson);
  }

  if (image.sourceFrame.has_value()) {
    const BrowserRect &source = image.sourceFrame.value();
    photo.sourceFrame = CGRectMake(source.x, source.y, source.width, source.height);
  }

  NSString *placeholderPath = GKRNStringFromOptional(image.placeholderPath);
  if (placeholderPath.length > 0) {
    UIImage *placeholder = GKRNLoadImage(placeholderPath);
    if (placeholder != nil) {
      photo.placeholderImage = placeholder;
    }
  }

  NSString *localPath = GKRNStringFromOptional(image.localPath);
  if (localPath.length > 0) {
    UIImage *localImage = GKRNLoadImage(localPath);
    if (localImage != nil) {
      photo.image = localImage;
    }
  } else {
    NSString *uri = GKRNStringFromOptional(image.uri);
    if (uri.length > 0) {
      NSURL *url = GKRNMakeURL(uri);
      if (url != nil) {
        if (url.isFileURL) {
          UIImage *fileImage = [UIImage imageWithContentsOfFile:url.path];
          if (fileImage != nil) {
            photo.image = fileImage;
          }
        } else {
          photo.url = url;
        }
      }
    }
  }

  NSString *originUri = GKRNStringFromOptional(image.originUri);
  if (originUri.length > 0) {
    NSURL *originURL = GKRNMakeURL(originUri);
    if (originURL != nil) {
      photo.originUrl = originURL;
    }
  }

  if (videoURL != nil) {
    photo.videoUrl = videoURL;
    photo.autoPlay = image.autoPlay.value_or(true);
  }

  if (headers.count > 0) {
    photo.extraInfo = @{@"headers": headers};
  }

  if (photo.image == nil && photo.url == nil && photo.originUrl == nil && photo.videoUrl == nil) {
    return nil;
  }

  return photo;
}

void GKPhotoBrowserRuntime::installImageHeaders(const std::vector<BrowserImage> &images) {
  NSDictionary<NSString *, NSString *> *headers = nil;

  for (const BrowserImage &image : images) {
    NSString *headersJson = GKRNStringFromOptional(image.headersJson);
    if (headersJson.length == 0) continue;
    headers = GKRNParseHeadersJson(headersJson);
    if (headers.count > 0) break;
  }

  if (headers.count == 0) return;

  SDWebImageDownloader *downloader = SDWebImageDownloader.sharedDownloader;
  [headers enumerateKeysAndObjectsUsingBlock:^(NSString *field, NSString *value, BOOL *stop) {
    [downloader setValue:value forHTTPHeaderField:field];
  }];
}

void GKPhotoBrowserRuntime::installForwardObserver() {
  removeForwardObserver();
  __weak GKPhotoBrowser *weakBrowser = browser_;
  forwardObserver_ = [NSNotificationCenter.defaultCenter
      addObserverForName:GKRNPhotoBrowserForwardNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *notification) {
                GKPhotoBrowser *browser = weakBrowser;
                if (browser == nil || notification.object != browser) return;
                NSNumber *index = notification.userInfo[@"index"];
                if (![index isKindOfClass:NSNumber.class]) return;
                handleForward(index.integerValue);
              }];
}

void GKPhotoBrowserRuntime::removeForwardObserver() {
  if (forwardObserver_ != nil) {
    [NSNotificationCenter.defaultCenter removeObserver:forwardObserver_];
    forwardObserver_ = nil;
  }
}

GKPhotoBrowserShowStyle GKPhotoBrowserRuntime::mapShowStyle(const std::optional<std::string> &value) {
  const std::string style = value.value_or("zoom");
  if (style == "none") return GKPhotoBrowserShowStyleNone;
  if (style == "push") return GKPhotoBrowserShowStylePush;
  return GKPhotoBrowserShowStyleZoom;
}

GKPhotoBrowserHideStyle GKPhotoBrowserRuntime::mapHideStyle(const std::optional<std::string> &value) {
  const std::string style = value.value_or("zoomScale");
  if (style == "zoom") return GKPhotoBrowserHideStyleZoom;
  if (style == "zoomSlide") return GKPhotoBrowserHideStyleZoomSlide;
  return GKPhotoBrowserHideStyleZoomScale;
}

GKPhotoBrowserLoadStyle GKPhotoBrowserRuntime::mapLoadStyle(const std::optional<std::string> &value) {
  const std::string style = value.value_or("indeterminate");
  if (style == "indeterminate") return GKPhotoBrowserLoadStyleIndeterminate;
  if (style == "indeterminateMask") return GKPhotoBrowserLoadStyleIndeterminateMask;
  if (style == "determinate") return GKPhotoBrowserLoadStyleDeterminate;
  return GKPhotoBrowserLoadStyleCustom;
}

void GKPhotoBrowserRuntime::handleDownload(NSInteger index) {
  if (onDownloadCallback_) {
    onDownloadCallback_((double)index);
  }
}

void GKPhotoBrowserRuntime::handleForward(NSInteger index) {
  if (onForwardCallback_) {
    onForwardCallback_((double)index);
  }
}

void GKPhotoBrowserRuntime::handleDidDisappear() {
  removeForwardObserver();
  browser_ = nil;
  cover_ = nil;
  if (shouldNotifyDismiss_ && onDismissCallback_) {
    onDismissCallback_();
  }
}

void GKPhotoBrowserRuntime::handlePanBegin() {
  [cover_ setActionButtonsHiddenByPan:YES];
}

void GKPhotoBrowserRuntime::handlePanEnded(BOOL willDisappear) {
  if (willDisappear) return;
  [cover_ setActionButtonsHiddenByPan:NO];
}

void GKPhotoBrowserRuntime::handleDismissWillStart() {
  [cover_ setActionButtonsHiddenByDismiss:YES];
}

GKPhotoBrowserImpl::GKPhotoBrowserImpl()
    : HybridObject(TAG), runtime_(std::make_unique<GKPhotoBrowserRuntime>()) {}

GKPhotoBrowserImpl::~GKPhotoBrowserImpl() = default;

void GKPhotoBrowserImpl::show(const BrowserConfig &config,
                              const std::function<void()> &onDismiss,
                              const std::function<void(double)> &onDownload,
                              const std::function<void(double)> &onForward) {
  runtime_->show(config, onDismiss, onDownload, onForward);
}

void GKPhotoBrowserImpl::dismiss() {
  runtime_->dismiss();
}

} // namespace margelo::nitro::gkphotobrowser

@implementation GKRNPhotoBrowserCover {
  UILabel *_countLabel;
  UIPageControl *_pageControl;
  UIButton *_closeButton;
  UIButton *_downloadButton;
  UIButton *_forwardButton;
  BOOL _actionButtonsHiddenByPan;
  BOOL _actionButtonsHiddenByDismiss;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _showCloseButton = YES;
    _showDownloadButton = NO;
    _showForwardButton = NO;
    _actionButtonsHiddenByPan = NO;
    _actionButtonsHiddenByDismiss = NO;

    _countLabel = [UILabel new];
    _countLabel.textColor = UIColor.whiteColor;
    _countLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _countLabel.textAlignment = NSTextAlignmentCenter;
    _countLabel.bounds = CGRectMake(0, 0, 96, 30);

    _pageControl = [UIPageControl new];
    _pageControl.hidesForSinglePage = YES;
    _pageControl.enabled = NO;
    if (@available(iOS 14.0, *)) {
      _pageControl.backgroundStyle = UIPageControlBackgroundStyleMinimal;
    }

    _closeButton = [self makeButtonWithSystemName:@"xmark"];
    _downloadButton = [self makeButtonWithSystemName:@"arrow.down.to.line"];
    _forwardButton = [self makeButtonWithSystemName:@"arrowshape.turn.up.right.fill"];
  }
  return self;
}

- (void)addCoverToView:(UIView *)view {
  if (view == nil) return;

  [view addSubview:_countLabel];
  [view addSubview:_pageControl];
  [view addSubview:_closeButton];
  [view addSubview:_downloadButton];
  [view addSubview:_forwardButton];

  [_closeButton addTarget:self action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
  [_downloadButton addTarget:self action:@selector(onDownload) forControlEvents:UIControlEventTouchUpInside];
  [_forwardButton addTarget:self action:@selector(onForward) forControlEvents:UIControlEventTouchUpInside];

  _pageControl.numberOfPages = self.browser.photos.count;
}

- (void)updateLayoutWithFrame:(CGRect)frame {
  const CGFloat horizontalInset = 15.0;
  const CGFloat topOffset = 4.0;
  const CGFloat buttonSize = 40.0;
  const CGFloat buttonGap = 20.0;
  UIEdgeInsets safeInsets = [self resolvedSafeAreaInsets];
  CGFloat topY = safeInsets.top + topOffset;

  _closeButton.frame = CGRectMake(horizontalInset, topY, buttonSize, buttonSize);
  _forwardButton.frame = CGRectMake(CGRectGetWidth(frame) - horizontalInset - buttonSize, topY, buttonSize, buttonSize);
  _downloadButton.frame = CGRectMake(CGRectGetMinX(_forwardButton.frame) - buttonGap - buttonSize, topY, buttonSize, buttonSize);

  _countLabel.center = CGPointMake(CGRectGetWidth(frame) * 0.5, topY + buttonSize * 0.5);

  CGSize pageSize = [_pageControl sizeForNumberOfPages:self.browser.photos.count];
  _pageControl.bounds = CGRectMake(0, 0, pageSize.width, pageSize.height);
  _pageControl.center = CGPointMake(CGRectGetWidth(frame) * 0.5, CGRectGetHeight(frame) - safeInsets.bottom - 22.0);
}

- (void)updateCoverWithCount:(NSInteger)count index:(NSInteger)index {
  _countLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)(index + 1), (long)count];
  _pageControl.currentPage = index;
}

- (void)updateCoverWithPhoto:(GKPhoto *)photo {
  self.photo = photo;

  if (self.browser.configure.hidesCountLabel) {
    _countLabel.hidden = YES;
  } else {
    _countLabel.hidden = self.browser.photos.count <= 1 || photo.isVideo;
  }

  if (self.browser.configure.hidesPageControl) {
    _pageControl.hidden = YES;
  } else {
    _pageControl.hidden = self.browser.photos.count <= 1 || photo.isVideo;
  }

  [self applyActionButtonsHiddenState];
}

- (void)setActionButtonsHiddenByPan:(BOOL)hidden {
  _actionButtonsHiddenByPan = hidden;
  [self applyActionButtonsHiddenState];
}

- (void)setActionButtonsHiddenByDismiss:(BOOL)hidden {
  _actionButtonsHiddenByDismiss = hidden;
  [self applyActionButtonsHiddenState];
}

- (void)applyActionButtonsHiddenState {
  BOOL shouldHideAll = _actionButtonsHiddenByPan || _actionButtonsHiddenByDismiss;
  _closeButton.hidden = shouldHideAll || !self.showCloseButton;
  _downloadButton.hidden = shouldHideAll || !self.showDownloadButton;
  _forwardButton.hidden = shouldHideAll || !self.showForwardButton;
}

- (UIEdgeInsets)resolvedSafeAreaInsets {
  UIEdgeInsets browserViewInsets = self.browser.view.safeAreaInsets;
  UIEdgeInsets browserWindowInsets = self.browser.view.window.safeAreaInsets;

  UIEdgeInsets keyWindowInsets = UIEdgeInsetsZero;
  CGFloat statusBarHeight = 0;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (windowScene.statusBarManager != nil) {
      statusBarHeight = MAX(statusBarHeight, CGRectGetHeight(windowScene.statusBarManager.statusBarFrame));
    }
    for (UIWindow *window in windowScene.windows) {
      if (window.isKeyWindow) {
        keyWindowInsets = window.safeAreaInsets;
        break;
      }
    }
  }

  return UIEdgeInsetsMake(MAX(MAX(browserViewInsets.top, browserWindowInsets.top), MAX(keyWindowInsets.top, statusBarHeight)),
                          MAX(MAX(browserViewInsets.left, browserWindowInsets.left), keyWindowInsets.left),
                          MAX(MAX(browserViewInsets.bottom, browserWindowInsets.bottom), keyWindowInsets.bottom),
                          MAX(MAX(browserViewInsets.right, browserWindowInsets.right), keyWindowInsets.right));
}

- (UIButton *)makeButtonWithSystemName:(NSString *)systemName {
  const CGFloat buttonSize = 40.0;
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  button.tintColor = UIColor.whiteColor;
  button.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.64];
  button.layer.cornerRadius = buttonSize * 0.5;
  button.clipsToBounds = YES;
  UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
  UIImage *image = [[UIImage systemImageNamed:systemName] imageByApplyingSymbolConfiguration:configuration];
  [button setImage:image forState:UIControlStateNormal];
  return button;
}

- (void)onClose {
  [self setActionButtonsHiddenByDismiss:YES];
  [self.browser dismiss];
}

- (void)onDownload {
  if (self.browser == nil) return;
  id<GKPhotoBrowserDelegate> delegate = self.browser.delegate;
  if ([delegate respondsToSelector:@selector(photoBrowser:onSaveBtnClick:image:)]) {
    UIImage *image = self.browser.curPhotoView.imageView.image;
    [delegate photoBrowser:self.browser onSaveBtnClick:self.browser.currentIndex image:image];
  }
}

- (void)onForward {
  if (self.browser == nil) return;
  [NSNotificationCenter.defaultCenter postNotificationName:GKRNPhotoBrowserForwardNotification
                                                    object:self.browser
                                                  userInfo:@{@"index" : @(self.browser.currentIndex)}];
}
@end

@implementation GKRNAVPlayerManager

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _videoPlayView = [GKRNAVPlayerView new];
    _status = GKVideoPlayerStatusPrepared;
    _isPlaying = NO;
    _currentTime = 0;
    _totalTime = 0;
    _shouldPlayWhenReady = NO;
    _wasPlayingBeforeBackground = NO;
    _seekTime = 0;
  }
  return self;
}

- (void)dealloc {
  [self gk_stop];
}

- (void)setStatus:(GKVideoPlayerStatus)status {
  _status = status;
  if (self.playerStatusChange != nil) {
    self.playerStatusChange(self, status);
  }
}

- (void)gk_prepareToPlay {
  if (self.assetURL == nil) return;
  [self gk_stop];
  self.status = GKVideoPlayerStatusPrepared;
  [self preparePlayableURLFromURL:self.assetURL];
}

- (void)gk_play {
  if (self.player == nil) {
    self.shouldPlayWhenReady = YES;
    return;
  }
  [self.player play];
  self.isPlaying = YES;
  if (self.status != GKVideoPlayerStatusPrepared) {
    self.status = GKVideoPlayerStatusPlaying;
  }
}

- (void)gk_replay {
  __weak GKRNAVPlayerManager *weakSelf = self;
  [self gk_seekToTime:0
    completionHandler:^(BOOL finished) {
      __strong GKRNAVPlayerManager *strongSelf = weakSelf;
      if (strongSelf == nil) return;
      strongSelf.currentTime = 0;
      if (strongSelf.playerPlayTimeChange != nil) {
        strongSelf.playerPlayTimeChange(strongSelf, strongSelf.currentTime, strongSelf.totalTime);
      }
      [strongSelf gk_play];
      strongSelf.status = GKVideoPlayerStatusPlaying;
    }];
}

- (void)gk_pause {
  if (!self.isPlaying) return;
  [self.player pause];
  [self.player.currentItem cancelPendingSeeks];
  self.isPlaying = NO;
  self.status = GKVideoPlayerStatusPaused;
}

- (void)gk_stop {
  [self.downloadTask cancel];
  self.downloadTask = nil;
  self.shouldPlayWhenReady = NO;

  if (self.timeObserver != nil && self.player != nil) {
    [self.player removeTimeObserver:self.timeObserver];
  }
  self.timeObserver = nil;

  [self removeItemObservers];

  if (self.endObserver != nil) {
    [NSNotificationCenter.defaultCenter removeObserver:self.endObserver];
  }
  if (self.resignActiveObserver != nil) {
    [NSNotificationCenter.defaultCenter removeObserver:self.resignActiveObserver];
  }
  if (self.didBecomeActiveObserver != nil) {
    [NSNotificationCenter.defaultCenter removeObserver:self.didBecomeActiveObserver];
  }
  self.endObserver = nil;
  self.resignActiveObserver = nil;
  self.didBecomeActiveObserver = nil;

  [self.player pause];
  self.player = nil;

  AVPlayerLayer *layer = (AVPlayerLayer *)self.videoPlayView.layer;
  layer.player = nil;

  self.currentTime = 0;
  self.totalTime = 0;
  self.isPlaying = NO;
  self.seekTime = 0;
  self.seekCompletion = nil;
}

- (void)gk_seekToTime:(NSTimeInterval)time completionHandler:(void (^)(BOOL))completionHandler {
  if (self.player == nil || self.totalTime <= 0) {
    self.seekTime = time;
    self.seekCompletion = completionHandler;
    return;
  }

  [self.player.currentItem cancelPendingSeeks];
  CMTimeScale scale = self.player.currentItem.asset.duration.timescale;
  if (scale <= 0) scale = 600;
  CMTime cmTime = CMTimeMakeWithSeconds(time, scale);
  [self.player seekToTime:cmTime completionHandler:completionHandler ?: ^(BOOL finished) {
  }];
}

- (void)gk_updateFrame:(CGRect)frame {
  self.videoPlayView.frame = frame;
}

- (void)gk_setMute:(BOOL)mute {
  self.player.muted = mute;
}

- (void)preparePlayableURLFromURL:(NSURL *)url {
  if (url.isFileURL) {
    [self setupPlayerWithURL:url];
    return;
  }

  NSURL *cacheURL = [self cachedVideoURLForURL:url];
  if ([NSFileManager.defaultManager fileExistsAtPath:cacheURL.path]) {
    [self setupPlayerWithURL:cacheURL];
    return;
  }

  self.status = GKVideoPlayerStatusBuffering;

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.timeoutInterval = 300;
  NSDictionary<NSString *, NSString *> *headers = [self headersFromPhoto];
  [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
    [request setValue:value forHTTPHeaderField:key];
  }];

  __weak GKRNAVPlayerManager *weakSelf = self;
  self.downloadTask = [NSURLSession.sharedSession
      downloadTaskWithRequest:request
            completionHandler:^(NSURL *tempURL, NSURLResponse *response, NSError *error) {
              __strong GKRNAVPlayerManager *strongSelf = weakSelf;
              if (strongSelf == nil) return;

              NSInteger statusCode = -1;
              if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = ((NSHTTPURLResponse *)response).statusCode;
              }

              if (statusCode != -1 && (statusCode < 200 || statusCode > 299)) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  NSLog(@"[GKRNAVPlayerManager] download http error url=%@ status=%ld", url.absoluteString, (long)statusCode);
                  [strongSelf setupRemotePlayerWithURL:url];
                });
                return;
              }

              if (error != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  strongSelf.error = error;
                  NSLog(@"[GKRNAVPlayerManager] download failed url=%@ error=%@", url.absoluteString, error.localizedDescription);
                  [strongSelf setupRemotePlayerWithURL:url];
                });
                return;
              }

              if (tempURL == nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                  NSLog(@"[GKRNAVPlayerManager] download temp file missing url=%@", url.absoluteString);
                  [strongSelf setupRemotePlayerWithURL:url];
                });
                return;
              }

              NSError *ioError = nil;
              NSURL *cacheDir = cacheURL.URLByDeletingLastPathComponent;
              [NSFileManager.defaultManager createDirectoryAtURL:cacheDir
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&ioError];
              if (ioError == nil && [NSFileManager.defaultManager fileExistsAtPath:cacheURL.path]) {
                [NSFileManager.defaultManager removeItemAtURL:cacheURL error:&ioError];
              }
              if (ioError == nil) {
                [NSFileManager.defaultManager copyItemAtURL:tempURL toURL:cacheURL error:&ioError];
              }

              dispatch_async(dispatch_get_main_queue(), ^{
                if (ioError != nil) {
                  strongSelf.error = ioError;
                  NSLog(@"[GKRNAVPlayerManager] cache failed url=%@ error=%@", url.absoluteString, ioError.localizedDescription);
                  [strongSelf setupRemotePlayerWithURL:url];
                } else {
                  [strongSelf setupPlayerWithURL:cacheURL];
                }
              });
            }];

  [self.downloadTask resume];
}

- (void)setupPlayerWithURL:(NSURL *)playURL {
  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:[self makeAssetForURL:playURL]];
  AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
  player.muted = self.browser.configure.isVideoMutedPlay;
  self.player = player;

  AVPlayerLayer *layer = (AVPlayerLayer *)self.videoPlayView.layer;
  layer.player = player;
  layer.videoGravity = AVLayerVideoGravityResizeAspect;

  [self addItemObservers:item];

  if (self.shouldPlayWhenReady) {
    [self gk_play];
  }
}

- (void)setupRemotePlayerWithURL:(NSURL *)remoteURL {
  NSLog(@"[GKRNAVPlayerManager] fallback remote playback url=%@", remoteURL.absoluteString);
  [self setupPlayerWithURL:remoteURL];
}

- (NSURL *)cachedVideoURLForURL:(NSURL *)url {
  NSString *ext = url.pathExtension.length > 0 ? url.pathExtension : @"mp4";
  NSString *key = [NSString stringWithFormat:@"%llu", (unsigned long long)llabs((long long)url.absoluteString.hash)];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gk_photo_browser_video"];
  path = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", key, ext]];
  return [NSURL fileURLWithPath:path];
}

- (AVURLAsset *)makeAssetForURL:(NSURL *)url {
  NSDictionary<NSString *, NSString *> *headers = [self headersFromPhoto];
  if (url.isFileURL || headers.count == 0) {
    return [AVURLAsset URLAssetWithURL:url options:nil];
  }
  return [AVURLAsset URLAssetWithURL:url options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
}

- (NSDictionary<NSString *, NSString *> *)headersFromPhoto {
  if (![self.photo.extraInfo isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  NSDictionary *info = (NSDictionary *)self.photo.extraInfo;
  NSDictionary *headers = info[@"headers"];
  if (![headers isKindOfClass:NSDictionary.class]) {
    return nil;
  }
  return (NSDictionary<NSString *, NSString *> *)headers;
}

- (void)addItemObservers:(AVPlayerItem *)item {
  [self removeItemObservers];
  self.observingItem = item;

  [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:GKRNPlayerStatusContext];
  [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:GKRNPlayerBufferEmptyContext];
  [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:GKRNPlayerKeepUpContext];
  [item addObserver:self forKeyPath:@"presentationSize" options:NSKeyValueObservingOptionNew context:GKRNPlayerPresentationSizeContext];

  __weak GKRNAVPlayerManager *weakSelf = self;
  self.endObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                  object:item
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *note) {
                __strong GKRNAVPlayerManager *strongSelf = weakSelf;
                if (strongSelf == nil) return;
                if (strongSelf.status != GKVideoPlayerStatusEnded) {
                  strongSelf.status = GKVideoPlayerStatusEnded;
                  strongSelf.isPlaying = NO;
                  [strongSelf gk_seekToTime:0 completionHandler:nil];
                }
              }];

  self.resignActiveObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:UIApplicationWillResignActiveNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *note) {
                __strong GKRNAVPlayerManager *strongSelf = weakSelf;
                if (strongSelf == nil) return;
                strongSelf.wasPlayingBeforeBackground = strongSelf.isPlaying;
                [strongSelf gk_pause];
              }];

  self.didBecomeActiveObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:UIApplicationDidBecomeActiveNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *note) {
                __strong GKRNAVPlayerManager *strongSelf = weakSelf;
                if (strongSelf == nil) return;
                if (strongSelf.wasPlayingBeforeBackground) {
                  [strongSelf gk_play];
                }
              }];
}

- (void)removeItemObservers {
  if (self.observingItem != nil) {
    @try {
      [self.observingItem removeObserver:self forKeyPath:@"status" context:GKRNPlayerStatusContext];
      [self.observingItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:GKRNPlayerBufferEmptyContext];
      [self.observingItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:GKRNPlayerKeepUpContext];
      [self.observingItem removeObserver:self forKeyPath:@"presentationSize" context:GKRNPlayerPresentationSizeContext];
    } @catch (NSException *exception) {
      // Ignore duplicated remove in edge cases.
    }
    self.observingItem = nil;
  }
}

- (void)installTimeObserver {
  if (self.timeObserver != nil || self.player == nil) return;

  __weak GKRNAVPlayerManager *weakSelf = self;
  self.timeObserver = [self.player
      addPeriodicTimeObserverForInterval:CMTimeMake(1, 10)
                                   queue:dispatch_get_main_queue()
                              usingBlock:^(CMTime time) {
                                __strong GKRNAVPlayerManager *strongSelf = weakSelf;
                                if (strongSelf == nil) return;
                                double seconds = CMTimeGetSeconds(time);
                                strongSelf.currentTime = isfinite(seconds) ? seconds : 0;
                                if (strongSelf.playerPlayTimeChange != nil) {
                                  strongSelf.playerPlayTimeChange(strongSelf, strongSelf.currentTime, strongSelf.totalTime);
                                }
                              }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if (context == GKRNPlayerStatusContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (item.status == AVPlayerItemStatusReadyToPlay) {
      self.status = GKVideoPlayerStatusPlaying;
      double duration = CMTimeGetSeconds(item.duration);
      self.totalTime = isfinite(duration) ? duration : 0;
      [self installTimeObserver];

      if (self.seekTime > 0) {
        NSTimeInterval seekTime = self.seekTime;
        void (^completion)(BOOL) = self.seekCompletion;
        self.seekTime = 0;
        self.seekCompletion = nil;
        [self gk_seekToTime:seekTime completionHandler:completion];
      }
    } else if (item.status == AVPlayerItemStatusFailed) {
      self.error = item.error;
      NSLog(@"[GKRNAVPlayerManager] playback failed url=%@ error=%@",
            self.assetURL.absoluteString ?: @"nil",
            item.error.localizedDescription ?: @"unknown");
      self.status = GKVideoPlayerStatusFailed;
    }
    return;
  }

  if (context == GKRNPlayerBufferEmptyContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (self.status != GKVideoPlayerStatusPaused && self.status != GKVideoPlayerStatusEnded && item.playbackBufferEmpty) {
      self.status = GKVideoPlayerStatusBuffering;
    }
    return;
  }

  if (context == GKRNPlayerKeepUpContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (self.status != GKVideoPlayerStatusPaused && self.status != GKVideoPlayerStatusEnded && item.playbackLikelyToKeepUp) {
      self.status = GKVideoPlayerStatusPlaying;
      if (self.isPlaying) {
        [self.player play];
      }
    }
    return;
  }

  if (context == GKRNPlayerPresentationSizeContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (self.playerGetVideoSize != nil) {
      self.playerGetVideoSize(self, item.presentationSize);
    }
    return;
  }

  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

@end
