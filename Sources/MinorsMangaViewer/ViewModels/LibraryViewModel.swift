import Foundation
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var authors: [Author] = []
    @Published var collections: [WorkCollection] = []
    @Published var works: [Work] = []
    @Published var isLoading = false
    @Published var searchQuery = ""
    @Published var separateAnthology: Bool = false
    @Published var filenameFilters: [String] = FilenameFilterStore.load() {
        didSet {
            FilenameFilterStore.save(filenameFilters)
            FolderScanner.skippedFolderNames = Set(filenameFilters)
        }
    }

    private let appState: AppState

    /// 当前选中的作者，实际存储在 `AppState.libraryContext` 中。
    var selectedAuthor: Author? {
        appState.libraryContext.selectedAuthor
    }

    /// 当前选中的子文件夹，实际存储在 `AppState.libraryContext` 中。
    var selectedCollection: WorkCollection? {
        appState.libraryContext.selectedCollection
    }

    init(appState: AppState) {
        self.appState = appState
        FolderScanner.skippedFolderNames = Set(filenameFilters)
    }

    var filteredWorks: [Work] {
        let source: [Work]
        if !searchQuery.isEmpty {
            source = allWorks()
        } else if let selectedCollection {
            source = selectedCollection.works
        } else if let rootCollection = collections.first(where: { $0.name.isEmpty }) {
            source = rootCollection.works
        } else {
            source = []
        }
        let lower = searchQuery.lowercased()
        guard !lower.isEmpty else { return source }
        return source.filter {
            $0.title.lowercased().contains(lower) ||
            $0.author.name.lowercased().contains(lower) ||
            $0.versions.contains { version in
                version.parsed.tags.contains { $0.lowercased().contains(lower) }
            }
        }
    }

    func loadLibrary(url: URL) async {
        isLoading = true
        defer { isLoading = false }

        SecurityScopedBookmarkManager.shared.startAccessing(path: url.path)

        do {
            authors = try await FolderScanner.scan(libraryURL: url)
            if let currentAuthor = selectedAuthor,
               authors.contains(where: { $0.path == currentAuthor.path }) {
                await selectAuthor(currentAuthor, preservingCollection: selectedCollection)
            } else if let first = authors.first {
                await selectAuthor(first)
            }
        } catch {
            print("Failed to scan library: \(error)")
        }
    }

    func selectAuthor(_ author: Author, preservingCollection: WorkCollection? = nil) async {
        appState.libraryContext = LibraryContext(selectedAuthor: author, selectedCollection: nil)
        do {
            collections = try await FolderScanner.collections(for: author)

            if let preserved = preservingCollection,
               let matching = collections.first(where: { $0.path == preserved.path }) {
                selectCollection(matching)
                return
            }

            if let rootCollection = collections.first(where: { $0.name.isEmpty }) {
                selectCollection(rootCollection)
            } else if let firstCollection = collections.first {
                selectCollection(firstCollection)
            } else {
                appState.libraryContext.selectedCollection = nil
                works = []
            }
        } catch {
            print("Failed to load collections: \(error)")
            collections = []
            appState.libraryContext.selectedCollection = nil
            works = []
        }
    }

    func selectCollection(_ collection: WorkCollection?) {
        appState.libraryContext.selectedCollection = collection
        let rawWorks = collection?.works ?? []
        works = rawWorks.sorted {
            if $0.isAnthology != $1.isAnthology {
                return !$0.isAnthology
            }
            return $0.originalFolderName < $1.originalFolderName
        }
    }

    private func allWorks() -> [Work] {
        var seen = Set<UUID>()
        return collections.flatMap { $0.works }.filter { work in
            guard !seen.contains(work.id) else { return false }
            seen.insert(work.id)
            return true
        }
    }
}

enum FilenameFilterStore {
    private static let key = "filenameFilters"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ filters: [String]) {
        UserDefaults.standard.set(filters, forKey: key)
    }
}
