import Foundation

/// 根据 URL 类型创建对应的页面提供者。
enum ArchiveService {
    static func provider(for url: URL) async throws -> any PageProvider {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return try await FolderPageProvider(folder: url)
        }

        switch url.pathExtension.lowercased() {
        case "cbz", "zip":
            return try ZipPageProvider(archive: url)
        case "cbr", "rar":
            return try RarPageProvider(archive: url)
        default:
            throw PageProviderError.imageLoadFailed
        }
    }

    static func isArchive(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "cbz", "zip", "cbr", "rar":
            return true
        default:
            return false
        }
    }
}
