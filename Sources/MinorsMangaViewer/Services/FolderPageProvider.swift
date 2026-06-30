import AppKit
import Foundation

/// 从本地文件夹按自然顺序读取图片的页面提供者。
struct FolderPageProvider: PageProvider {
    let pageCount: Int
    private let imageURLs: [URL]

    init(folder: URL) async throws {
        let urls = try await FolderScanner.imageFiles(in: folder)
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
        // 文件夹 provider 不需要清理资源
    }
}
