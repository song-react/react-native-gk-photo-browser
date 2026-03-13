import Foundation
import GKPhotoBrowser
import SDWebImage
import UIKit

public final class GKPhotoBrowserImpl: HybridGKPhotoBrowserSpec {
  private var browser: GKPhotoBrowser?
  private var onDismissCallback: (() -> Void)?
  private var onDownloadCallback: ((Double) -> Void)?
  private var onForwardCallback: ((Double) -> Void)?
  private var shouldNotifyDismiss = true
  private let delegateProxy = GKPhotoBrowserDelegateProxy()
  private var forwardObserver: NSObjectProtocol?
  private weak var cover: GKRNPhotoBrowserCover?

  public override init() {
    super.init()
    delegateProxy.owner = self
  }

  public func show(
    config: BrowserConfig,
    onDismiss: @escaping () -> Void,
    onDownload: @escaping (Double) -> Void,
    onForward: @escaping (Double) -> Void
  ) throws {
    DispatchQueue.main.async {
      self.shouldNotifyDismiss = true
      self.onDismissCallback = onDismiss
      self.onDownloadCallback = onDownload
      self.onForwardCallback = onForward

      if let current = self.browser {
        self.shouldNotifyDismiss = false
        current.dismiss()
        self.shouldNotifyDismiss = true
        self.browser = nil
      }

      let photos = config.images.compactMap(self.makePhoto)
      guard !photos.isEmpty, let viewController = self.topViewController() else {
        onDismiss()
        return
      }

      let browser = GKPhotoBrowser(photos: photos, currentIndex: Int(config.currentIndex ?? 0))
      let configure = browser.configure
      browser.delegate = self.delegateProxy
      configure.showStyle = self.mapShowStyle(config.showStyle)
      configure.hideStyle = self.mapHideStyle(config.hideStyle)
      configure.loadStyle = self.mapLoadStyle(config.loadStyle)
      configure.originLoadStyle = self.mapLoadStyle(config.originLoadStyle)
      configure.maxZoomScale = CGFloat(config.maxZoomScale ?? 20)
      configure.doubleZoomScale = CGFloat(config.doubleZoomScale ?? 2)
      configure.hidesCountLabel = config.hidesCountLabel ?? true
      configure.hidesPageControl = !(config.showsPageControl ?? true)
      configure.hidesSavedBtn = !(config.showDownloadButton ?? false)
      configure.isAdaptiveSafeArea = config.isAdaptiveSafeArea ?? false
      configure.isFollowSystemRotation = config.isFollowSystemRotation ?? false
      configure.setupVideoPlayerProtocol(GKRNAVPlayerManager())

      let cover = GKRNPhotoBrowserCover()
      cover.showCloseButton = config.showCloseButton ?? true
      cover.showDownloadButton = config.showDownloadButton ?? false
      cover.showForwardButton = config.showForwardButton ?? false
      configure.setupCover(cover)
      self.cover = cover

      self.installImageHeaders(from: config.images)
      self.installForwardObserver()

      self.browser = browser
      browser.show(fromVC: viewController)
    }
  }

  public func dismiss() throws {
    DispatchQueue.main.async {
      self.removeForwardObserver()
      self.cover?.setActionButtonsHiddenByDismiss(true)
      self.browser?.dismiss()
      self.browser = nil
      self.cover = nil
    }
  }
}

private extension GKPhotoBrowserImpl {
  func makePhoto(_ image: BrowserImage) -> GKPhoto? {
    let photo = GKPhoto()
    let videoURL = image.videoUri.flatMap(makeURL)
    let headers = image.headersJson.flatMap(parseHeaders)

    if let sourceFrame = image.sourceFrame {
      photo.sourceFrame = CGRect(
        x: sourceFrame.x,
        y: sourceFrame.y,
        width: sourceFrame.width,
        height: sourceFrame.height
      )
    }

    if let placeholderPath = image.placeholderPath,
       let placeholder = loadImage(from: placeholderPath) {
      photo.placeholderImage = placeholder
    }

    if let localPath = image.localPath,
       let image = loadImage(from: localPath) {
      photo.image = image
    } else if let uri = image.uri, let url = makeURL(from: uri) {
      if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
        photo.image = image
      } else {
        photo.url = url
      }
    }

    if let originUri = image.originUri, let originUrl = makeURL(from: originUri) {
      photo.originUrl = originUrl
    }

    if let videoURL {
      photo.videoUrl = videoURL
      photo.isAutoPlay = image.autoPlay ?? true
    }

    if let headers, !headers.isEmpty {
      photo.extraInfo = ["headers": headers]
    }

    if photo.image == nil && photo.url == nil && photo.originUrl == nil && photo.videoUrl == nil {
      return nil
    }

    return photo
  }

  func makeURL(from value: String) -> URL? {
    if value.hasPrefix("/") {
      return URL(fileURLWithPath: value)
    }
    if let url = URL(string: value) {
      return url
    }
    if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
      return URL(string: encoded)
    }
    return nil
  }

  func loadImage(from value: String) -> UIImage? {
    guard let url = makeURL(from: value) else {
      return nil
    }
    if url.isFileURL {
      return UIImage(contentsOfFile: url.path)
    }
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    return UIImage(data: data)
  }

  func parseHeaders(_ json: String) -> [String: String]? {
    guard let data = json.data(using: .utf8) else {
      return nil
    }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
  }

  func installImageHeaders(from images: [BrowserImage]) {
    let headers = images.compactMap { $0.headersJson }.compactMap(parseHeaders).first(where: { !$0.isEmpty })
    guard let headers else { return }
    let downloader = SDWebImageDownloader.shared
    for (field, value) in headers {
      downloader.setValue(value, forHTTPHeaderField: field)
    }
  }

  func installForwardObserver() {
    removeForwardObserver()
    forwardObserver = NotificationCenter.default.addObserver(
      forName: .gkPhotoBrowserForward,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let self,
        let browser = notification.object as? GKPhotoBrowser,
        browser === self.browser,
        let index = notification.userInfo?["index"] as? Int
      else {
        return
      }
      self.handleForward(index: index)
    }
  }

  func removeForwardObserver() {
    if let forwardObserver {
      NotificationCenter.default.removeObserver(forwardObserver)
    }
    forwardObserver = nil
  }

  func mapShowStyle(_ value: String?) -> GKPhotoBrowserShowStyle {
    switch value ?? "zoom" {
    case "none":
      return .none
    case "push":
      return .push
    case "zoom":
      return .zoom
    default:
      return .zoom
    }
  }

  func mapHideStyle(_ value: String?) -> GKPhotoBrowserHideStyle {
    switch value ?? "zoomScale" {
    case "zoom":
      return .zoom
    case "zoomSlide":
      return .zoomSlide
    case "zoomScale":
      return .zoomScale
    default:
      return .zoomScale
    }
  }

  func mapLoadStyle(_ value: String?) -> GKPhotoBrowserLoadStyle {
    switch value ?? "indeterminate" {
    case "indeterminate":
      return .indeterminate
    case "indeterminateMask":
      return .indeterminateMask
    case "determinate":
      return .determinate
    case "custom":
      return .custom
    default:
      return .custom
    }
  }

  func topViewController(
    base: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .last(where: \.isKeyWindow)?.rootViewController
  ) -> UIViewController? {
    if let navigation = base as? UINavigationController {
      return topViewController(base: navigation.visibleViewController)
    }
    if let tab = base as? UITabBarController {
      return topViewController(base: tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }

  func handleDownload(index: Int) {
    onDownloadCallback?(Double(index))
  }

  func handleForward(index: Int) {
    onForwardCallback?(Double(index))
  }

  func handleDidDisappear() {
    removeForwardObserver()
    browser = nil
    cover = nil
    if shouldNotifyDismiss {
      onDismissCallback?()
    }
  }

  func handlePanBegin() {
    cover?.setActionButtonsHiddenByPan(true)
  }

  func handlePanEnded(willDisappear: Bool) {
    if willDisappear { return }
    cover?.setActionButtonsHiddenByPan(false)
  }

  func handleDismissWillStart() {
    cover?.setActionButtonsHiddenByDismiss(true)
  }
}

private final class GKPhotoBrowserDelegateProxy: NSObject, GKPhotoBrowserDelegate {
  weak var owner: GKPhotoBrowserImpl?

  func photoBrowser(_ browser: GKPhotoBrowser!, onSaveBtnClick index: Int, image: UIImage!) {
    owner?.handleDownload(index: index)
  }

  func photoBrowser(_ browser: GKPhotoBrowser!, didDisappearAt index: Int) {
    owner?.handleDidDisappear()
  }

  func photoBrowser(_ browser: GKPhotoBrowser!, panBeginWith index: Int) {
    owner?.handlePanBegin()
  }

  func photoBrowser(_ browser: GKPhotoBrowser!, panEndedWith index: Int, willDisappear disappear: Bool) {
    owner?.handlePanEnded(willDisappear: disappear)
  }

  func photoBrowser(_ browser: GKPhotoBrowser!, singleTapWith index: Int) {
    owner?.handleDismissWillStart()
  }

  func photoBrowser(_ browser: GKPhotoBrowser!, longPressWith index: Int) {}
}
