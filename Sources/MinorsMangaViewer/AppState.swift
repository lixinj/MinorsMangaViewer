import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var libraryURL: URL? {
        didSet {
            if let oldURL = oldValue {
                SecurityScopedBookmarkManager.shared.stopAccessing(url: oldURL)
            }
            if let newURL = libraryURL {
                SecurityScopedBookmarkManager.shared.saveBookmark(for: newURL)
                SecurityScopedBookmarkManager.shared.startAccessing(path: newURL.path)
            }
        }
    }

    @Published var libraryContext: LibraryContext = LibraryContext()

    init() {
        self.libraryURL = SecurityScopedBookmarkManager.shared.firstRestoredURL()
    }
}
