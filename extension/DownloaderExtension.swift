// The Background Assets downloader extension. One source, two flavours: built with SELF_HOSTED it adopts
// ManagedDownloaderExtension (self-hosting), without it StoreDownloaderExtension (Apple hosting).
import BackgroundAssets
import ExtensionFoundation
import Foundation
import os

#if SELF_HOSTED
@main
struct DownloaderExtension: ManagedDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool { shouldDownloadPack(assetPack) }
}
#else
import StoreKit

@main
struct DownloaderExtension: StoreDownloaderExtension {
    func shouldDownload(_ assetPack: AssetPack) -> Bool { shouldDownloadPack(assetPack) }
}
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DownloaderExtension", category: "download")

// The download policy of both flavours: every pack the system offers. Return false here to skip a pack.
private func shouldDownloadPack(_ assetPack: AssetPack) -> Bool {
    logger.info("shouldDownload \(assetPack.id, privacy: .public)")
    return true
}
