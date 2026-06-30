import Foundation

public enum SocialPlatform: String, CaseIterable, Sendable {
    case pixiv = "Pixiv"
    case twitter = "Twitter"
    case x = "X"
    case fanbox = "Fanbox"
    case fantia = "Fantia"
    case patreon = "Patreon"
    case other
}

public enum FolderType: Hashable, Sendable {
    case doujinshi
    case manga
    case year
    case social(SocialPlatform)
    case unknown
}

extension FolderType {
    public static func from(folderName: String) -> FolderType {
        let lowercased = folderName.lowercased().trimmingCharacters(in: .whitespaces)
        switch lowercased {
        case "doujinshi", "同人誌":
            return .doujinshi
        case "manga", "漫画", "comic":
            return .manga
        case "pixiv":
            return .social(.pixiv)
        case "twitter", "x":
            return .social(.x)
        case "fanbox":
            return .social(.fanbox)
        case "fantia":
            return .social(.fantia)
        case "patreon":
            return .social(.patreon)
        default:
            if let year = Int(folderName), year >= 1900, year <= 2100 {
                return .year
            }
            return .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .doujinshi:
            return "同人志"
        case .manga:
            return "漫画"
        case .year:
            return "年份"
        case .social(let platform):
            return platform.rawValue
        case .unknown:
            return "其他"
        }
    }
}
