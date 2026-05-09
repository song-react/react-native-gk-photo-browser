import type { BrowserConfig as NativeBrowserConfig, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro';
export type { BrowserCallbacks, BrowserImage, BrowserMediaType, BrowserRect, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro';
export type BrowserShowStyle = 'none' | 'zoom' | 'push' | 'pushZoom';
export type BrowserHideStyle = 'none' | 'zoom' | 'zoomScale' | 'zoomSlide';
export type BrowserLoadStyle = 'indeterminate' | 'indeterminateMask' | 'determinate' | 'determinateSector' | 'custom';
export type BrowserFailStyle = 'onlyText' | 'onlyImage' | 'imageAndText' | 'custom';
export type BrowserStatusBarStyle = 'default' | 'light' | 'dark';
export type BrowserConfig = Omit<NativeBrowserConfig, 'showStyle' | 'hideStyle' | 'loadStyle' | 'originLoadStyle' | 'videoLoadStyle' | 'liveLoadStyle' | 'failStyle' | 'videoFailStyle' | 'statusBarStyle'> & {
    showStyle?: BrowserShowStyle;
    hideStyle?: BrowserHideStyle;
    loadStyle?: BrowserLoadStyle;
    originLoadStyle?: BrowserLoadStyle;
    videoLoadStyle?: BrowserLoadStyle;
    liveLoadStyle?: BrowserLoadStyle;
    failStyle?: BrowserFailStyle;
    videoFailStyle?: BrowserFailStyle;
    statusBarStyle?: BrowserStatusBarStyle;
};
export declare const PhotoBrowser: GKPhotoBrowser;
//# sourceMappingURL=index.d.ts.map