import Foundation

public struct Author: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: URL
}
