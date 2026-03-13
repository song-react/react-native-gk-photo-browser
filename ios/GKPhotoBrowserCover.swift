import GKPhotoBrowser
import UIKit

final class GKRNPhotoBrowserCover: NSObject, GKCoverViewProtocol {
  weak var browser: GKPhotoBrowser?
  weak var photo: GKPhoto?

  var showCloseButton = true
  var showDownloadButton = false
  var showForwardButton = false

  // Fixed layout: safeArea.top + NavigationBarHeight style spacing.
  private let horizontalInset: CGFloat = 15
  private let topOffset: CGFloat = 4
  private let buttonSize: CGFloat = 40
  private let buttonGap: CGFloat = 20

  private lazy var countLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.font = .systemFont(ofSize: 16, weight: .medium)
    label.textAlignment = .center
    label.bounds = CGRect(x: 0, y: 0, width: 96, height: 30)
    return label
  }()

  private lazy var pageControl: UIPageControl = {
    let control = UIPageControl()
    control.hidesForSinglePage = true
    control.isEnabled = false
    if #available(iOS 14.0, *) {
      control.backgroundStyle = .minimal
    }
    return control
  }()

  private lazy var closeButton = makeButton(systemName: "xmark")
  private lazy var downloadButton = makeButton(systemName: "arrow.down.to.line")
  private lazy var forwardButton = makeButton(systemName: "arrowshape.turn.up.right.fill")
  private var actionButtonsHiddenByPan = false
  private var actionButtonsHiddenByDismiss = false

  func addCover(to view: UIView?) {
    guard let view else { return }
    view.addSubview(countLabel)
    view.addSubview(pageControl)
    view.addSubview(closeButton)
    view.addSubview(downloadButton)
    view.addSubview(forwardButton)

    closeButton.addTarget(self, action: #selector(onClose), for: .touchUpInside)
    downloadButton.addTarget(self, action: #selector(onDownload), for: .touchUpInside)
    forwardButton.addTarget(self, action: #selector(onForward), for: .touchUpInside)

    pageControl.numberOfPages = browser?.photos.count ?? 0
  }

  func updateLayout(withFrame frame: CGRect) {
    let safeInsets = resolvedSafeAreaInsets()
    let topY = safeInsets.top + topOffset

    closeButton.frame = CGRect(
      x: horizontalInset,
      y: topY,
      width: buttonSize,
      height: buttonSize
    )
    forwardButton.frame = CGRect(
      x: frame.width - horizontalInset - buttonSize,
      y: topY,
      width: buttonSize,
      height: buttonSize
    )
    downloadButton.frame = CGRect(
      x: forwardButton.frame.minX - buttonGap - buttonSize,
      y: topY,
      width: buttonSize,
      height: buttonSize
    )

    countLabel.center = CGPoint(x: frame.width * 0.5, y: topY + buttonSize * 0.5)

    let pageSize = pageControl.size(forNumberOfPages: browser?.photos.count ?? 0)
    pageControl.bounds = CGRect(origin: .zero, size: pageSize)
    pageControl.center = CGPoint(
      x: frame.width * 0.5,
      y: frame.height - safeInsets.bottom - 22
    )
  }

  func updateCover(withCount count: Int, index: Int) {
    countLabel.text = "\(index + 1)/\(count)"
    pageControl.currentPage = index
  }

  func updateCover(with photo: GKPhoto?) {
    self.photo = photo

    if browser?.configure.hidesCountLabel == true {
      countLabel.isHidden = true
    } else {
      countLabel.isHidden = (browser?.photos.count ?? 0) <= 1 || photo?.isVideo == true
    }

    if browser?.configure.hidesPageControl == true {
      pageControl.isHidden = true
    } else {
      pageControl.isHidden = (browser?.photos.count ?? 0) <= 1 || photo?.isVideo == true
    }

    applyActionButtonsHiddenState()
  }

  func setActionButtonsHiddenByPan(_ hidden: Bool) {
    actionButtonsHiddenByPan = hidden
    applyActionButtonsHiddenState()
  }

  func setActionButtonsHiddenByDismiss(_ hidden: Bool) {
    actionButtonsHiddenByDismiss = hidden
    applyActionButtonsHiddenState()
  }
}

private extension GKRNPhotoBrowserCover {
  func applyActionButtonsHiddenState() {
    let shouldHideAll = actionButtonsHiddenByPan || actionButtonsHiddenByDismiss
    closeButton.isHidden = shouldHideAll || !showCloseButton
    downloadButton.isHidden = shouldHideAll || !showDownloadButton
    forwardButton.isHidden = shouldHideAll || !showForwardButton
  }

  func resolvedSafeAreaInsets() -> UIEdgeInsets {
    let browserViewInsets = browser?.view.safeAreaInsets ?? .zero
    let browserWindowInsets = browser?.view.window?.safeAreaInsets ?? .zero
    let keyWindowInsets =
      UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .safeAreaInsets ?? .zero
    let statusBarHeight =
      UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .compactMap { $0.statusBarManager?.statusBarFrame.height }
      .max() ?? 0

    return UIEdgeInsets(
      top: max(browserViewInsets.top, browserWindowInsets.top, keyWindowInsets.top, statusBarHeight),
      left: max(browserViewInsets.left, browserWindowInsets.left, keyWindowInsets.left),
      bottom: max(browserViewInsets.bottom, browserWindowInsets.bottom, keyWindowInsets.bottom),
      right: max(browserViewInsets.right, browserWindowInsets.right, keyWindowInsets.right)
    )
  }

  func makeButton(systemName: String) -> UIButton {
    let button = UIButton(type: .system)
    button.tintColor = .white
    button.backgroundColor = UIColor(white: 0.18, alpha: 0.64)
    button.layer.cornerRadius = buttonSize * 0.5
    button.clipsToBounds = true
    let image = UIImage(systemName: systemName)?.withConfiguration(
      UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    )
    button.setImage(image, for: .normal)
    return button
  }

  @objc
  func onClose() {
    setActionButtonsHiddenByDismiss(true)
    browser?.dismiss()
  }

  @objc
  func onDownload() {
    guard let browser else { return }
    browser.delegate?.photoBrowser?(
      browser,
      onSaveBtnClick: browser.currentIndex,
      image: browser.curPhotoView.imageView.image
    )
  }

  @objc
  func onForward() {
    guard let browser else { return }
    NotificationCenter.default.post(
      name: .gkPhotoBrowserForward,
      object: browser,
      userInfo: ["index": browser.currentIndex]
    )
  }
}

extension Notification.Name {
  static let gkPhotoBrowserForward = Notification.Name("gkPhotoBrowserForward")
}
