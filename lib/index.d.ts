import type { BrowserCallbacks, BrowserConfig as NativeBrowserConfig, GKPhotoBrowser } from './specs/GKPhotoBrowser.nitro';
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
export declare function showPhotoBrowser(config: BrowserConfig, callbacks?: BrowserCallbacks): void;
export declare function dismissPhotoBrowser(): void;
//# sourceMappingURL=index.d.ts.map