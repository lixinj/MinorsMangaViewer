import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    /// 内存缓存，使用 NSCache 自动管理淘汰
    /// countLimit: 最多保留 200 张缩略图
    /// totalCostLimit: 最多占用约 50 MB
    private let memoryCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    private let cacheDirectory: URL
    private let maxPixelSize: CGFloat = 400

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("MinorsMangaViewer/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func thumbnail(for version: WorkVersion) async -> NSImage? {
        let key = version.path as NSURL

        // 1. 内存缓存
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. 磁盘缓存
        let diskURL = cacheDirectory.appendingPathComponent(version.path.path.sha256).appendingPathExtension("jpg")
        if let cached = NSImage(contentsOf: diskURL) {
            memoryCache.setObject(cached, forKey: key)
            return cached
        }

        // 3. 后台生成缩略图
        let thumbnail = await Task.detached(priority: .userInitiated) { [cacheDirectory, maxPixelSize] () -> NSImage? in
            let image: NSImage?
            if version.isArchive {
                image = await Self.firstImage(fromArchive: version.path)
            } else {
                guard let imageFiles = try? await FolderScanner.imageFiles(in: version.path),
                      let first = imageFiles.first else {
                    return nil
                }
                image = NSImage(contentsOf: first)
            }

            guard let image = image else { return nil }
            let thumbnail = image.resized(toMax: maxPixelSize)

            // 保存到磁盘
            let diskURL = cacheDirectory.appendingPathComponent(version.path.path.sha256).appendingPathExtension("jpg")
            if let data = thumbnail?.jpegData {
                try? data.write(to: diskURL)
            }

            return thumbnail
        }.value

        // 4. 更新内存缓存
        if let thumbnail = thumbnail {
            let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
            memoryCache.setObject(thumbnail, forKey: key, cost: cost)
        }

        return thumbnail
    }

    private static func firstImage(fromArchive archiveURL: URL) async -> NSImage? {
        do {
            let provider = try await ArchiveService.provider(for: archiveURL)
            defer { provider.close() }
            guard provider.pageCount > 0 else { return nil }
            return try await provider.image(at: 0)
        } catch {
            return nil
        }
    }

    @available(*, deprecated, renamed: "thumbnail(for:)")
    func thumbnail(for folder: URL) async -> NSImage? {
        let key = folder as NSURL

        // 1. 内存缓存
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. 磁盘缓存
        let diskURL = cacheDirectory.appendingPathComponent(folder.path.sha256).appendingPathExtension("jpg")
        if let cached = NSImage(contentsOf: diskURL) {
            memoryCache.setObject(cached, forKey: key)
            return cached
        }

        // 3. 后台生成缩略图
        let thumbnail = await Task.detached(priority: .userInitiated) { [cacheDirectory, maxPixelSize] () -> NSImage? in
            guard let imageFiles = try? await FolderScanner.imageFiles(in: folder),
                  let first = imageFiles.first,
                  let image = NSImage(contentsOf: first) else {
                return nil
            }

            let thumbnail = image.resized(toMax: maxPixelSize)

            // 保存到磁盘
            let diskURL = cacheDirectory.appendingPathComponent(folder.path.sha256).appendingPathExtension("jpg")
            if let data = thumbnail?.jpegData {
                try? data.write(to: diskURL)
            }

            return thumbnail
        }.value

        // 4. 更新内存缓存
        if let thumbnail = thumbnail {
            let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
            memoryCache.setObject(thumbnail, forKey: key, cost: cost)
        }

        return thumbnail
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
}

private extension NSImage {
    /// 使用 CGContext 缩放图片，避免 lockFocus，支持后台线程执行。
    func resized(toMax maxDimension: CGFloat) -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)
        guard originalWidth > 0, originalHeight > 0 else { return nil }

        let ratio = min(maxDimension / originalWidth, maxDimension / originalHeight)
        guard ratio < 1 else { return self }

        let newWidth = Int(originalWidth * ratio)
        let newHeight = Int(originalHeight * ratio)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let scaledCGImage = context.makeImage() else { return nil }
        return NSImage(cgImage: scaledCGImage, size: NSSize(width: newWidth, height: newHeight))
    }

    var jpegData: Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

private extension String {
    var sha256: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
