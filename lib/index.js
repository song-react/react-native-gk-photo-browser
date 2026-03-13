import { NitroModules } from 'react-native-nitro-modules';
export const PhotoBrowser = NitroModules.createHybridObject('GKPhotoBrowser');
export function showPhotoBrowser(config, callbacks) {
    PhotoBrowser.show(config, callbacks?.onDismiss ?? (() => { }), callbacks?.onDownload ?? (() => { }), callbacks?.onForward ?? (() => { }));
}
export function dismissPhotoBrowser() {
    PhotoBrowser.dismiss();
}
