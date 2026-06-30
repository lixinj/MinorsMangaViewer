import AppKit
import Foundation
import Unrar

/// 从 RAR/CBR 压缩包中读取图片的页面提供者。
///
/// 初始化时把压缩包解压到临时目录，按自然顺序收集图片。
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

        try Self.extractArchive(archive, to: tempRoot)

        let urls = try Self.collectImageFiles(in: tempRoot)
        self.imageURLs = urls
        self.pageCount = urls.count
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

    private static func collectImageFiles(in folder: URL) throws -> [URL] {
        let extensions = Set(["jpg", "jpeg", "png", "webp", "gif", "bmp", "tiff", "heic"])
        return try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { url in
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return false
                }
                return extensions.contains(url.pathExtension.lowercased())
            }
            .sorted { naturalPageCompare($0.lastPathComponent, $1.lastPathComponent) }
    }
}
