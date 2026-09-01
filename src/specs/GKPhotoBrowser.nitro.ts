import type { HybridObject } from 'react-native-nitro-modules'

export interface BrowserRect {
  x: number
  y: number
  width: number
  height: number
}

export type BrowserMediaType = 'image' | 'video'

export interface BrowserImage {
  type?: BrowserMediaType
  uri?: string
  originUri?: string
  videoUri?: string
  headersJson?: string
  localPath?: string
  placeholderPath?: string
  sourceFrame?: BrowserRect
  autoPlay?: boolean
}

export interface BrowserConfig {
  images: BrowserImage[]
  currentIndex?: number
  showStyle?: string
  hideStyle?: string
  loadStyle?: string
  originLoadStyle?: string
  failStyle?: string
  videoLoadStyle?: string
  videoFailStyle?: string
  liveLoadStyle?: string
  statusBarStyle?: string
  bgColor?: string
  failureText?: string
  videoFailureText?: string
  maxZoomScale?: number
  doubleZoomScale?: number
  photoViewPadding?: number
  animDuration?: number
  scaleDismissProgressThreshold?: number
  slideDismissDistanceThreshold?: number
  slideDismissVelocityThreshold?: number
  hidesPageControl?: boolean
  hidesCountLabel?: boolean
  hidesSavedBtn?: boolean
  isAdaptiveSafeArea?: boolean
  isFollowSystemRotation?: boolean
  isModalDismissAnimated?: boolean
  isStatusBarShow?: boolean
  isShowStatusBarWhenPan?: boolean
  isScreenRotateDisabled?: boolean
  isSingleTapDisabled?: boolean
  isDoubleTapDisabled?: boolean
  isDoubleTapZoomDisabled?: boolean
  isHideSourceView?: boolean
  isResumePhotoZoom?: boolean
  isFullWidthForLandScape?: boolean
  isUpSlideDismissDisabled?: boolean
  isNeedNavigationController?: boolean
  isPopGestureEnabled?: boolean
  isClearMemoryWhenDisappear?: boolean
  isClearMemoryWhenViewReuse?: boolean
  isShowPlayImage?: boolean
  isVideoMutedPlay?: boolean
  isVideoReplay?: boolean
  isVideoPausedWhenDragged?: boolean
  isVideoPausedWhenScrollBegan?: boolean
  isVideoZoomDisabled?: boolean
  isHideProgressView?: boolean
  isLivePhotoPausedWhenDragged?: boolean
  isLivePhotoPausedWhenScrollBegan?: boolean
  isLivePhotoMutedPlay?: boolean
  isShowLivePhotoMark?: boolean
  isLivePhotoLongPressPlay?: boolean
  isClearMemoryForLivePhoto?: boolean
}

export interface BrowserCallbacks {
  onDismiss?: () => void
  onDownload?: (index: number) => void
  onForward?: (index: number) => void
}

export interface GKPhotoBrowser extends HybridObject<{ ios: 'c++' }> {
  show(config: BrowserConfig, callbacks?: BrowserCallbacks): void
  dismiss(): void
}
