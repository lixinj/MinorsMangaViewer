import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @Binding var isReaderPresented: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(libraryViewModel.authors) { author in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { libraryViewModel.selectedAuthor?.path == author.path },
                        set: { isExpanded in
                            if isExpanded {
                                Task {
                                    await libraryViewModel.selectAuthor(author)
                                }
                            }
                        }
                    )
                ) {
                    ForEach(libraryViewModel.collections.filter { !$0.name.isEmpty }) { collection in
                        Label(collection.displayName, systemImage: icon(for: collection.folderType))
                            .tag(SidebarItem.collection(collection))
                    }
                } label: {
                    let isSelected = libraryViewModel.selectedAuthor?.path == author.path
                    Label(author.name, systemImage: "person")
                        .tag(SidebarItem.author(author))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("漫画库")
        .onAppear {
            updateKeyMonitor()
        }
        .onChange(of: isReaderPresented) { _, _ in
            updateKeyMonitor()
        }
        .onDisappear {
            stopKeyMonitor()
        }
    }

    private var selectionBinding: Binding<SidebarItem?> {
        Binding {
            if let collection = libraryViewModel.selectedCollection {
                return .collection(collection)
            } else if let author = libraryViewModel.selectedAuthor {
                return .author(author)
            }
            return nil
        } set: { item in
            guard let item = item else { return }
            switch item {
            case .author(let author):
                Task {
                    await libraryViewModel.selectAuthor(author)
                }
            case .collection(let collection):
                libraryViewModel.selectCollection(collection)
            }
        }
    }

    private func icon(for type: FolderType) -> String {
        switch type {
        case .doujinshi:
            return "book"
        case .manga:
            return "books.vertical"
        case .year:
            return "calendar"
        case .social:
            return "globe"
        case .unknown:
            return "folder"
        }
    }

    private func updateKeyMonitor() {
        if isReaderPresented {
            stopKeyMonitor()
        } else {
            startKeyMonitor()
        }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 48 else { return event }
            guard !self.isTextFieldFocused else { return event }

            let authors = self.libraryViewModel.authors
            guard !authors.isEmpty else { return event }

            let currentAuthorIndex: Int
            if let selected = self.libraryViewModel.selectedAuthor,
               let index = authors.firstIndex(where: { $0.path == selected.path }) {
                currentAuthorIndex = index
            } else {
                Task {
                    await self.libraryViewModel.selectAuthor(authors[0])
                }
                return nil
            }

            let collections = self.libraryViewModel.collections.filter { !$0.name.isEmpty }
            let isBackward = event.modifierFlags.contains(.control)

            if let selectedCollection = self.libraryViewModel.selectedCollection {
                if selectedCollection.name.isEmpty {
                    // 当前在根目录：Tab 进入第一个子文件夹，Control+Tab 跳到上一个作者的最后一个子文件夹
                    if !isBackward, let first = collections.first {
                        self.libraryViewModel.selectCollection(first)
                        return nil
                    }
                } else if let index = collections.firstIndex(where: { $0.path == selectedCollection.path }) {
                    if isBackward {
                        if index > 0 {
                            self.libraryViewModel.selectCollection(collections[index - 1])
                            return nil
                        }
                    } else {
                        if index < collections.count - 1 {
                            self.libraryViewModel.selectCollection(collections[index + 1])
                            return nil
                        }
                    }
                }
            }

            // 当前作者没有更多子文件夹，或需要反向跳过根目录，切换到相邻作者
            let newAuthorIndex = isBackward
                ? (currentAuthorIndex - 1 + authors.count) % authors.count
                : (currentAuthorIndex + 1) % authors.count
            let newAuthor = authors[newAuthorIndex]

            Task {
                await self.libraryViewModel.selectAuthor(newAuthor)
                // selectAuthor 会自动选择根目录合集，无需再手动进入子文件夹
            }
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private var isTextFieldFocused: Bool {
        var responder: NSResponder? = NSApp.keyWindow?.firstResponder
        while responder != nil {
            if responder is NSTextView || responder is NSTextField {
                return true
            }
            responder = responder?.nextResponder
        }
        return false
    }
}

enum SidebarItem: Hashable {
    case author(Author)
    case collection(WorkCollection)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .author(let author):
            hasher.combine(0)
            hasher.combine(author.path)
        case .collection(let collection):
            hasher.combine(1)
            hasher.combine(collection.path)
        }
    }

    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        switch (lhs, rhs) {
        case (.author(let a1), .author(let a2)):
            return a1.path == a2.path
        case (.collection(let c1), .collection(let c2)):
            return c1.path == c2.path
        default:
            return false
        }
    }
}
