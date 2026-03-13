import AVFoundation
import GKPhotoBrowser
import UIKit

private final class GKRNAVPlayerView: UIView {
  override class var layerClass: AnyClass {
    AVPlayerLayer.self
  }
}

final class GKRNAVPlayerManager: NSObject, GKVideoPlayerProtocol {
  weak var browser: GKPhotoBrowser?
  weak var photo: GKPhoto?
  weak var coverImage: UIImage?

  var videoPlayView: UIView? = GKRNAVPlayerView()
  var assetURL: URL?
  var error: Error?

  var playerStatusChange: ((GKVideoPlayerProtocol, GKVideoPlayerStatus) -> Void)!
  var playerPlayTimeChange: ((GKVideoPlayerProtocol, TimeInterval, TimeInterval) -> Void)!
  var playerGetVideoSize: ((GKVideoPlayerProtocol, CGSize) -> Void)!

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var bufferEmptyObservation: NSKeyValueObservation?
  private var keepUpObservation: NSKeyValueObservation?
  private var presentationSizeObservation: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var resignActiveObserver: NSObjectProtocol?
  private var didBecomeActiveObserver: NSObjectProtocol?
  private var seekTime: TimeInterval = 0
  private var seekCompletion: ((Bool) -> Void)?
  private var wasPlayingBeforeBackground = false
  private var shouldPlayWhenReady = false
  private var downloadTask: URLSessionDownloadTask?

  private(set) var isPlaying = false
  private(set) var currentTime: TimeInterval = 0
  private(set) var totalTime: TimeInterval = 0

  var status: GKVideoPlayerStatus = .prepared {
    didSet {
      playerStatusChange?(self, status)
    }
  }

  deinit {
    gk_stop()
  }

  func gk_prepareToPlay() {
    guard let assetURL else { return }
    gk_stop()

    status = .prepared
    preparePlayableURL(from: assetURL)
  }

  func gk_play() {
    if player == nil {
      shouldPlayWhenReady = true
      return
    }
    player?.play()
    isPlaying = true
    if status != .prepared {
      status = .playing
    }
  }

  func gk_replay() {
    gk_seek(toTime: 0) { [weak self] _ in
      guard let self else { return }
      self.currentTime = 0
      self.playerPlayTimeChange?(self, self.currentTime, self.totalTime)
      self.gk_play()
      self.status = .playing
    }
  }

  func gk_pause() {
    guard isPlaying else { return }
    player?.pause()
    player?.currentItem?.cancelPendingSeeks()
    isPlaying = false
    status = .paused
  }

  func gk_stop() {
    downloadTask?.cancel()
    downloadTask = nil
    shouldPlayWhenReady = false
    if let timeObserver, let player {
      player.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    statusObservation = nil
    bufferEmptyObservation = nil
    keepUpObservation = nil
    presentationSizeObservation = nil

    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    if let resignActiveObserver {
      NotificationCenter.default.removeObserver(resignActiveObserver)
    }
    if let didBecomeActiveObserver {
      NotificationCenter.default.removeObserver(didBecomeActiveObserver)
    }
    endObserver = nil
    resignActiveObserver = nil
    didBecomeActiveObserver = nil

    player?.pause()
    player = nil
    (videoPlayView?.layer as? AVPlayerLayer)?.player = nil

    currentTime = 0
    totalTime = 0
    isPlaying = false
    seekTime = 0
    seekCompletion = nil
  }

  func gk_seek(toTime time: TimeInterval, completionHandler: ((Bool) -> Void)?) {
    guard let player, totalTime > 0 else {
      seekTime = time
      seekCompletion = completionHandler
      return
    }

    player.currentItem?.cancelPendingSeeks()
    let timeScale = player.currentItem?.asset.duration.timescale ?? 600
    let cmTime = CMTimeMakeWithSeconds(time, preferredTimescale: timeScale)
    player.seek(to: cmTime, completionHandler: completionHandler ?? { _ in })
  }

  func gk_updateFrame(_ frame: CGRect) {
    videoPlayView?.frame = frame
  }

  func gk_setMute(_ mute: Bool) {
    player?.isMuted = mute
  }
}

private extension GKRNAVPlayerManager {
  func preparePlayableURL(from url: URL) {
    if url.isFileURL {
      setupPlayer(with: url)
      return
    }

    let cacheURL = cachedVideoURL(for: url)
    if FileManager.default.fileExists(atPath: cacheURL.path) {
      setupPlayer(with: cacheURL)
      return
    }

    status = .buffering
    var request = URLRequest(url: url)
    request.timeoutInterval = 300
    headersFromPhoto()?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

    downloadTask = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
      guard let self else { return }
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
      if statusCode != -1, !(200 ... 299).contains(statusCode) {
        DispatchQueue.main.async {
          NSLog(
            "[GKRNAVPlayerManager] download http error url=%@ status=%d",
            url.absoluteString,
            statusCode
          )
          self.setupRemotePlayer(with: url)
        }
        return
      }
      if let error {
        DispatchQueue.main.async {
          self.error = error
          NSLog(
            "[GKRNAVPlayerManager] download failed url=%@ error=%@",
            url.absoluteString,
            error.localizedDescription
          )
          self.setupRemotePlayer(with: url)
        }
        return
      }
      guard let tempURL else {
        DispatchQueue.main.async {
          NSLog(
            "[GKRNAVPlayerManager] download temp file missing url=%@",
            url.absoluteString
          )
          self.setupRemotePlayer(with: url)
        }
        return
      }

      do {
        try FileManager.default.createDirectory(
          at: cacheURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: cacheURL.path) {
          try FileManager.default.removeItem(at: cacheURL)
        }
        try FileManager.default.copyItem(at: tempURL, to: cacheURL)

        DispatchQueue.main.async {
          self.setupPlayer(with: cacheURL)
        }
      } catch {
        DispatchQueue.main.async {
          self.error = error
          NSLog(
            "[GKRNAVPlayerManager] cache failed url=%@ error=%@",
            url.absoluteString,
            error.localizedDescription
          )
          self.setupRemotePlayer(with: url)
        }
      }
    }
    downloadTask?.resume()
  }

  func setupPlayer(with playURL: URL) {
    let item = AVPlayerItem(asset: makeAsset(url: playURL))
    let player = AVPlayer(playerItem: item)
    player.isMuted = browser?.configure.isVideoMutedPlay ?? false
    self.player = player

    if let layer = videoPlayView?.layer as? AVPlayerLayer {
      layer.player = player
      layer.videoGravity = .resizeAspect
    }

    addObservers(for: item)
    if shouldPlayWhenReady {
      gk_play()
    }
  }

  func setupRemotePlayer(with remoteURL: URL) {
    NSLog(
      "[GKRNAVPlayerManager] fallback remote playback url=%@",
      remoteURL.absoluteString
    )
    setupPlayer(with: remoteURL)
  }

  func cachedVideoURL(for url: URL) -> URL {
    let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
    let key = String(url.absoluteString.hashValue.magnitude)
    return URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("gk_photo_browser_video", isDirectory: true)
      .appendingPathComponent("\(key).\(ext)")
  }

  func makeAsset(url: URL) -> AVURLAsset {
    guard !url.isFileURL, let headers = headersFromPhoto(), !headers.isEmpty else {
      return AVURLAsset(url: url)
    }
    return AVURLAsset(
      url: url,
      options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
    )
  }

  func headersFromPhoto() -> [String: String]? {
    guard
      let info = photo?.extraInfo as? [String: Any],
      let headers = info["headers"] as? [String: String]
    else {
      return nil
    }
    return headers
  }

  func addObservers(for item: AVPlayerItem) {
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      guard let self else { return }
      switch item.status {
      case .readyToPlay:
        self.status = .playing
        let duration = item.duration.seconds
        self.totalTime = duration.isFinite ? duration : 0
        self.installTimeObserver()
        if self.seekTime > 0 {
          let seekTime = self.seekTime
          let completion = self.seekCompletion
          self.seekTime = 0
          self.seekCompletion = nil
          self.gk_seek(toTime: seekTime, completionHandler: completion)
        }
      case .failed:
        self.error = item.error
        NSLog(
          "[GKRNAVPlayerManager] playback failed url=%@ error=%@",
          self.assetURL?.absoluteString ?? "nil",
          item.error?.localizedDescription ?? "unknown"
        )
        self.status = .failed
      default:
        break
      }
    }

    bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
      guard let self else { return }
      if self.status == .paused || self.status == .ended { return }
      if item.isPlaybackBufferEmpty {
        self.status = .buffering
      }
    }

    keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
      guard let self else { return }
      if self.status == .paused || self.status == .ended { return }
      if item.isPlaybackLikelyToKeepUp {
        self.status = .playing
        if self.isPlaying {
          self.player?.play()
        }
      }
    }

    presentationSizeObservation = item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
      guard let self else { return }
      self.playerGetVideoSize?(self, item.presentationSize)
    }

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      if self.status != .ended {
        self.status = .ended
        self.isPlaying = false
        self.gk_seek(toTime: 0, completionHandler: nil)
      }
    }

    resignActiveObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.wasPlayingBeforeBackground = self.isPlaying
      self.gk_pause()
    }

    didBecomeActiveObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      if self.wasPlayingBeforeBackground {
        self.gk_play()
      }
    }
  }

  func installTimeObserver() {
    guard timeObserver == nil, let player else { return }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTimeMake(value: 1, timescale: 10),
      queue: .main
    ) { [weak self] time in
      guard let self else { return }
      self.currentTime = time.seconds.isFinite ? time.seconds : 0
      self.playerPlayTimeChange?(self, self.currentTime, self.totalTime)
    }
  }
}
