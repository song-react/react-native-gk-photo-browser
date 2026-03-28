import type { BrowserConfig as NativeBrowserConfig, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro';
export type { BrowserCallbacks, BrowserImage, BrowserMediaType, BrowserRect, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro';
export type BrowserShowStyle = 'none' | 'zoom' | 'push';
export type BrowserHideStyle = 'zoom' | 'zoomScale' | 'zoomSlide';
export type BrowserLoadStyle = 'indeterminate' | 'indeterminateMask' | 'determinate' | 'custom';
export type BrowserConfig = Omit<NativeBrowserConfig, 'showStyle' | 'hideStyle' | 'loadStyle' | 'originLoadStyle'> & {
    showStyle?: BrowserShowStyle;
    hideStyle?: BrowserHideStyle;
    loadStyle?: BrowserLoadStyle;
    originLoadStyle?: BrowserLoadStyle;
};
export declare const PhotoBrowser: GKPhotoBrowser;
//# sourceMappingURL=index.d.ts.map