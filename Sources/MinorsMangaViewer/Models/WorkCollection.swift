import Foundation

public struct WorkCollection: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: URL
    public let folderType: FolderType
    public let works: [Work]

    public var displayName: String {
        name.isEmpty ? "根目录" : name
    }
}
