import AppKit
import Foundation
import Unrar
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MinorsMangaViewer",
    category: "RarPageProvider"
)

/// 从 RAR/CBR 压缩包中读取图片的页面提供者。
///
/// 初始化时把压缩包解压到临时目录，递归收集所有图片。
/// `close()` 时删除临时目录。
final class RarPageProvider: PageProvider, @unchecked Sendable {
    let pageCount: Int
    private let tempDirectory: URL
    private let imageURLs: [URL]

    init(archive: URL) throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MinorsMangaViewer", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        self.tempDirectory = tempRoot

        do {
            try Self.extractArchive(archive, to: tempRoot)
        } catch {
            logger.error("Failed to extract rar \(archive.path): \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempRoot)
            throw error
        }

        let urls = Self.collectImageFiles(in: tempRoot)
        self.imageURLs = urls
        self.pageCount = urls.count
        logger.info("RarPageProvider prepared \(urls.count) images from \(archive.lastPathComponent)")
    }

    func image(at index: Int) async throws -> NSImage {
        guard index >= 0, index < imageURLs.count else {
            throw PageProviderError.indexOutOfRange
        }
        let url = imageURLs[index]
        guard let image = NSImage(contentsOf: url) else {
            throw PageProviderError.imageLoadFailed
        }
        return image
    }

    func close() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Private

    private static func extractArchive(_ archive: URL, to destination: URL) throws {
        let archive = try Archive(fileURL: archive)
        let entries = try archive.entries()

        for entry in entries {
            guard !entry.directory else { continue }
            let targetURL = destination.appendingPathComponent(entry.fileName)
            let targetDirectory = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let data = try archive.extract(entry)
            try data.write(to: targetURL)
        }
    }

    /// 递归收集目录及其子目录中的图片文件。
    private static func collectImageFiles(in folder: URL) -> [URL] {
        let extensions = Set(["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"])
        var result: [URL] = []

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == false,
                  extensions.contains(url.pathExtension.lowercased())
            else { continue }
            result.append(url)
        }

        return result.sorted { naturalPageCompare($0.path, $1.path) }
    }
}
