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
  maxZoomScale?: number
  doubleZoomScale?: number
  hidesCountLabel?: boolean
  showsPageControl?: boolean
  isAdaptiveSafeArea?: boolean
  isFollowSystemRotation?: boolean
  showCloseButton?: boolean
  showDownloadButton?: boolean
  showForwardButton?: boolean
}

export interface BrowserCallbacks {
  onDismiss?: () => void
  onDownload?: (index: number) => void
  onForward?: (index: number) => void
}

export interface GKPhotoBrowser extends HybridObject<{ ios: 'swift' }> {
  show(
    config: BrowserConfig,
    onDismiss: () => void,
    onDownload: (index: number) => void,
    onForward: (index: number) => void
  ): void
  dismiss(): void
}
