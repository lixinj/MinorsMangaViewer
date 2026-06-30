import Foundation

@MainActor
final class ReadingProgressStore {
    static let shared = ReadingProgressStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        static func page(for path: URL) -> String {
            "page:\(path.path)"
        }
        static func version(for workID: String) -> String {
            "version:\(workID)"
        }
    }

    func page(for path: URL) -> Int? {
        let value = defaults.integer(forKey: Key.page(for: path))
        return value > 0 ? value : nil
    }

    func set(page: Int, for path: URL) {
        defaults.set(page, forKey: Key.page(for: path))
    }

    func versionID(for workID: String) -> String? {
        defaults.string(forKey: Key.version(for: workID))
    }

    func set(versionID: String, for workID: String) {
        defaults.set(versionID, forKey: Key.version(for: workID))
    }
}
