import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var libraryURL: URL? {
        didSet {
            // 释放旧安全域书签资源
            oldValue?.stopAccessingSecurityScopedResource()
            if let url = libraryURL {
                SecurityBookmarkStore.save(url: url)
            }
        }
    }

    @Published var libraryContext: LibraryContext = LibraryContext()

    init() {
        self.libraryURL = SecurityBookmarkStore.load()
    }
}

enum SecurityBookmarkStore {
    private static let key = "libraryBookmark"

    static func save(url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    static func load() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // bookmark 已过期，尝试重新生成
                if let freshData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(freshData, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            let success = url.startAccessingSecurityScopedResource()
            if !success {
                print("Failed to start accessing security-scoped resource")
                UserDefaults.standard.removeObject(forKey: key)
                return nil
            }
            return url
        } catch {
            print("Failed to load bookmark: \(error)")
            // 清除损坏或无效的书签数据，避免下次启动继续报错
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }
}
