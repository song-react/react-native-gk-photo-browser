import { NitroModules } from 'react-native-nitro-modules'
import type {
  BrowserCallbacks,
  BrowserConfig as NativeBrowserConfig,
  BrowserImage,
  BrowserMediaType,
  BrowserRect,
  GKPhotoBrowser,
} from './specs/GKPhotoBrowser.nitro'

export type { BrowserCallbacks, BrowserImage, BrowserMediaType, BrowserRect, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro'

export type BrowserShowStyle = 'none' | 'zoom' | 'push'
export type BrowserHideStyle = 'zoom' | 'zoomScale' | 'zoomSlide'
export type BrowserLoadStyle =
  | 'indeterminate'
  | 'indeterminateMask'
  | 'determinate'
  | 'custom'

export type BrowserConfig = Omit<
  NativeBrowserConfig,
  'showStyle' | 'hideStyle' | 'loadStyle' | 'originLoadStyle'
> & {
  showStyle?: BrowserShowStyle
  hideStyle?: BrowserHideStyle
  loadStyle?: BrowserLoadStyle
  originLoadStyle?: BrowserLoadStyle
}

export const PhotoBrowser =
  NitroModules.createHybridObject<GKPhotoBrowser>('GKPhotoBrowser')

export function showPhotoBrowser(
  config: BrowserConfig,
  callbacks?: BrowserCallbacks
): void {
  PhotoBrowser.show(
    config as NativeBrowserConfig,
    callbacks?.onDismiss ?? (() => {}),
    callbacks?.onDownload ?? (() => {}),
    callbacks?.onForward ?? (() => {})
  )
}

export function dismissPhotoBrowser(): void {
  PhotoBrowser.dismiss()
}
