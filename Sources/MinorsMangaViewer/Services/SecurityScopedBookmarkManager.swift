import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MinorsMangaViewer",
    category: "SecurityScopedBookmarkManager"
)

/// 管理 App Sandbox 下的安全范围书签（Security-Scoped Bookmarks）。
///
/// 用户通过 NSOpenPanel 选择的文件夹在沙盒中默认只能一次性访问，
/// 通过保存 bookmark data 可以在 App 重启后继续访问该目录。
@MainActor
final class SecurityScopedBookmarkManager {
    static let shared = SecurityScopedBookmarkManager()

    private let bookmarkKey = "securityScopedBookmarks"
    private var activeURLs: Set<URL> = []

    private init() {}

    /// 尝试恢复并访问存储的第一个书签 URL。
    /// 用于 App 启动时恢复上次选择的漫画库目录。
    func firstRestoredURL() -> URL? {
        let bookmarks = loadAllBookmarkData()
        guard let (path, _) = bookmarks.first else { return nil }
        return startAccessing(path: path)
    }

    /// 为指定 URL 生成并保存安全范围书签。
    func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadAllBookmarkData()
            bookmarks[url.path] = bookmarkData
            saveAllBookmarkData(bookmarks)
        } catch {
            logger.error("Failed to save bookmark for \(url.path): \(error.localizedDescription)")
        }
    }

    /// 解析指定路径的书签并开始访问安全范围资源。
    /// 返回解析后的 URL；如果书签过期且路径发生变化，会更新存储。
    @discardableResult
    func startAccessing(path: String) -> URL? {
        let bookmarks = loadAllBookmarkData()
        guard let data = bookmarks[path] else { return nil }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            logger.error("Failed to resolve bookmark for \(path): \(error.localizedDescription)")
            removeBookmark(for: path)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            logger.warning("Failed to start accessing security-scoped resource: \(url.path)")
            return nil
        }
        activeURLs.insert(url)

        if isStale {
            refreshBookmark(for: url, oldPath: path)
        }

        return url
    }

    /// 停止访问指定的安全范围资源。
    func stopAccessing(url: URL) {
        if activeURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeURLs.remove(url)
        }
    }

    /// 停止所有活跃的安全范围资源访问。
    func stopAll() {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
    }

    /// 移除指定路径的书签数据。
    func removeBookmark(for path: String) {
        var bookmarks = loadAllBookmarkData()
        bookmarks.removeValue(forKey: path)
        saveAllBookmarkData(bookmarks)
    }

    /// 清除所有书签数据（谨慎使用）。
    func removeAllBookmarks() {
        stopAll()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    // MARK: - Private

    private func refreshBookmark(for url: URL, oldPath: String) {
        do {
            let freshData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadAllBookmarkData()
            if url.path != oldPath {
                bookmarks.removeValue(forKey: oldPath)
            }
            bookmarks[url.path] = freshData
            saveAllBookmarkData(bookmarks)
        } catch {
            logger.warning("Failed to refresh stale bookmark: \(error.localizedDescription)")
        }
    }

    private func loadAllBookmarkData() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Data].self, from: data)
        } catch {
            logger.error("Failed to decode bookmark data: \(error.localizedDescription)")
            return [:]
        }
    }

    private func saveAllBookmarkData(_ bookmarks: [String: Data]) {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            logger.error("Failed to save bookmarks: \(error.localizedDescription)")
        }
    }
}
