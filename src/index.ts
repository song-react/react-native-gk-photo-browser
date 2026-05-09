import { NitroModules } from 'react-native-nitro-modules'
import type {
  BrowserConfig as NativeBrowserConfig,
  BrowserImage,
  BrowserMediaType,
  BrowserRect,
  GKPhotoBrowser,
} from './specs/GKPhotoBrowser.nitro'

export type { BrowserCallbacks, BrowserImage, BrowserMediaType, BrowserRect, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro'

export type BrowserShowStyle = 'none' | 'zoom' | 'push' | 'pushZoom'
export type BrowserHideStyle = 'none' | 'zoom' | 'zoomScale' | 'zoomSlide'
export type BrowserLoadStyle =
  | 'indeterminate'
  | 'indeterminateMask'
  | 'determinate'
  | 'determinateSector'
  | 'custom'
export type BrowserFailStyle = 'onlyText' | 'onlyImage' | 'imageAndText' | 'custom'
export type BrowserStatusBarStyle = 'default' | 'light' | 'dark'

export type BrowserConfig = Omit<
  NativeBrowserConfig,
  | 'showStyle'
  | 'hideStyle'
  | 'loadStyle'
  | 'originLoadStyle'
  | 'videoLoadStyle'
  | 'liveLoadStyle'
  | 'failStyle'
  | 'videoFailStyle'
  | 'statusBarStyle'
> & {
  showStyle?: BrowserShowStyle
  hideStyle?: BrowserHideStyle
  loadStyle?: BrowserLoadStyle
  originLoadStyle?: BrowserLoadStyle
  videoLoadStyle?: BrowserLoadStyle
  liveLoadStyle?: BrowserLoadStyle
  failStyle?: BrowserFailStyle
  videoFailStyle?: BrowserFailStyle
  statusBarStyle?: BrowserStatusBarStyle
}

export const PhotoBrowser =
  NitroModules.createHybridObject<GKPhotoBrowser>('GKPhotoBrowser')
