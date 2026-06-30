import Foundation

/// 描述用户在漫画库中的当前位置：选中的作者及其子文件夹。
///
/// 该结构体故意设计为不可变值类型：每次切换位置都替换整个上下文，
/// 便于 SwiftUI 观察变化并触发下游数据加载。
struct LibraryContext: Equatable, Sendable {
    var selectedAuthor: Author?
    var selectedCollection: WorkCollection?

    init(selectedAuthor: Author? = nil, selectedCollection: WorkCollection? = nil) {
        self.selectedAuthor = selectedAuthor
        self.selectedCollection = selectedCollection
    }
}
