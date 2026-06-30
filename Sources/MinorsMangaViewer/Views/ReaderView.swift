import SwiftUI
import AppKit

struct ReaderView: View {
    let work: Work
    let works: [Work]
    let currentIndex: Int
    let onClose: () -> Void
    let onOpenWork: (Work, Int) -> Void
    @StateObject private var viewModel: ReaderViewModel
    @State private var keyMonitor: Any?
    @State private var isVersionMenuPresented = false
    @State private var versionHighlightIndex: Int = 0
    @FocusState private var isReaderFocused: Bool

    init(work: Work, works: [Work], currentIndex: Int, onClose: @escaping () -> Void, onOpenWork: @escaping (Work, Int) -> Void, initialLayout: ReaderLayout? = nil, filenameFilters: [String] = []) {
        self.work = work
        self.works = works
        self.currentIndex = currentIndex
        self.onClose = onClose
        self.onOpenWork = onOpenWork
        let version = ReadingProgressStore.shared.versionID(for: work.id.uuidString)
            .flatMap { id in work.versions.first { $0.id.uuidString == id } }
            ?? work.primaryVersion
            ?? work.versions.first
            ?? WorkVersion(name: "", path: URL(fileURLWithPath: "/"), type: .unknown, parsed: NamingParser.parse(folderName: ""))
        let layout = initialLayout ?? ReaderLayoutStore.load()
        _viewModel = StateObject(wrappedValue: ReaderViewModel(work: work, version: version, layout: layout, filenameFilters: filenameFilters))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                closeShortcutButton

                toolbar

                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    if viewModel.isLoading {
                        ProgressView("加载图片中…")
                            .foregroundStyle(.white)
                    } else if viewModel.imageURLs.isEmpty {
                        ContentUnavailableView("没有图片", systemImage: "photo")
                            .foregroundStyle(.white)
                    } else {
                        readerContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .background(Color.black)

            if isVersionMenuPresented {
                versionMenu
                    .padding(.top, 50)
                    .padding(.leading, 150)
                    .frame(width: 450, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .toolbar(.hidden)
        .focusable()
        .focusEffectDisabled()
        .focused($isReaderFocused)
        .task {
            await viewModel.loadVersion(viewModel.currentVersion, preservingPage: false)
        }
        .onAppear {
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
                if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first {
                    window.title = ""
                    window.titleVisibility = .hidden
                }
                isReaderFocused = true
                startKeyMonitor()
            }
        }
        .onDisappear {
            stopKeyMonitor()
        }
        .onKeyPress(.space) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
            }
            viewModel.nextPage()
            return .handled
        }
        .onKeyPress(.return) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
                return .handled
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
                return .handled
            }
            onClose()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
            }
            if viewModel.layout == .doubleRightToLeft {
                viewModel.nextPage()
            } else {
                viewModel.previousPage()
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
            }
            if viewModel.layout == .doubleRightToLeft {
                viewModel.previousPage()
            } else {
                viewModel.nextPage()
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
            }
            viewModel.previousPage()
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isVersionMenuPresented {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isVersionMenuPresented = false
                }
            }
            viewModel.nextPage()
            return .handled
        }
    }

    private var closeShortcutButton: some View {
        Button("") {
            onClose()
        }
        .keyboardShortcut("w", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private var toolbar: some View {
        ZStack(alignment: .center) {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 100)

                versionPickerButton

                Spacer()

                Picker("", selection: $viewModel.layout) {
                    ForEach(ReaderLayout.allCases, id: \.self) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: viewModel.layout) { _, newLayout in
                    ReaderLayoutStore.save(newLayout)
                }
            }

            VStack(spacing: 2) {
                Text(work.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(viewModel.currentPageDisplay)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .background(.thinMaterial)
    }

    private var versionPickerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isVersionMenuPresented.toggle()
                if isVersionMenuPresented {
                    versionHighlightIndex = work.versions.firstIndex(where: { $0.id == viewModel.currentVersion.id }) ?? 0
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("版本")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.currentVersion.displayLabel(relativeTo: work.title))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isVersionMenuPresented ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isVersionMenuPresented ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var versionMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(work.versions.enumerated()), id: \.element.id) { index, version in
                Text(version.displayLabel(relativeTo: work.title))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(versionHighlightIndex == index ? Color.accentColor.opacity(0.45) : Color.clear)
                    )
                    .foregroundStyle(versionHighlightIndex == index ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onHover { isHovered in
                        if isHovered {
                            versionHighlightIndex = index
                        }
                    }
                    .onTapGesture {
                        selectVersion(at: index)
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isVersionMenuPresented = false
                        }
                    }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 48: // tab
                self.handleVersionTab()
                return nil
            case 53: // escape
                if self.isVersionMenuPresented {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isVersionMenuPresented = false
                    }
                    return nil
                }
                return event
            case 123, 124, 125, 126: // left, right, down, up
                if event.modifierFlags.contains(.option) {
                    self.handleOptionArrow(event.keyCode)
                    return nil
                }
            default:
                break
            }

            let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
            let noRelevantModifiers = event.modifierFlags.intersection(relevantModifiers).isEmpty
            let hasShift = event.modifierFlags.contains(.shift)
            guard hasShift && noRelevantModifiers else { return event }

            switch event.keyCode {
            case 123: // left arrow
                viewModel.shiftDoublePageForward()
                return nil
            default:
                return event
            }
        }
    }

    private func handleOptionArrow(_ keyCode: UInt16) {
        let isNext: Bool
        switch viewModel.layout {
        case .doubleRightToLeft:
            // 右开：左/下 = 下一部，右/上 = 上一部
            isNext = (keyCode == 123 || keyCode == 125)
        case .single, .doubleLeftToRight:
            // 单页/左开：右/下 = 下一部，左/上 = 上一部
            isNext = (keyCode == 124 || keyCode == 125)
        }

        let newIndex = isNext ? currentIndex + 1 : currentIndex - 1
        guard newIndex >= 0 && newIndex < works.count else { return }
        onOpenWork(works[newIndex], newIndex)
    }

    private func handleVersionTab() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if work.versions.count <= 1 {
                isVersionMenuPresented.toggle()
                if isVersionMenuPresented {
                    versionHighlightIndex = 0
                }
            } else {
                if !isVersionMenuPresented {
                    isVersionMenuPresented = true
                    versionHighlightIndex = work.versions.firstIndex(where: { $0.id == viewModel.currentVersion.id }) ?? 0
                } else {
                    versionHighlightIndex = (versionHighlightIndex + 1) % work.versions.count
                    selectVersion(at: versionHighlightIndex)
                }
            }
        }
    }

    private func moveVersionHighlight(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.1)) {
            versionHighlightIndex = (versionHighlightIndex + delta + work.versions.count) % work.versions.count
            selectVersion(at: versionHighlightIndex)
        }
    }

    private func selectVersion(at index: Int) {
        guard index >= 0 && index < work.versions.count else { return }
        let version = work.versions[index]
        Task {
            await viewModel.loadVersion(version, preservingPage: true)
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private var readerContent: some View {
        GeometryReader { geometry in
            ZStack {
                pageContent(in: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ReaderInteractionOverlay(
                    layout: viewModel.layout,
                    currentPageRange: viewModel.currentPageRange,
                    imageURLs: viewModel.imageURLs,
                    isVersionMenuPresented: isVersionMenuPresented,
                    onCloseVersionMenu: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isVersionMenuPresented = false
                        }
                    },
                    onPreviousPage: { viewModel.previousPage() },
                    onNextPage: { viewModel.nextPage() },
                    onInsertBlankPage: insertBlankPage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func pageContent(in geometry: GeometryProxy) -> some View {
        let maxWidth = geometry.size.width
        let maxHeight = geometry.size.height

        switch viewModel.layout {
        case .single:
            return AnyView(
                singlePageContent(
                    url: viewModel.imageURLs[safe: viewModel.currentPageIndex],
                    maxWidth: maxWidth,
                    maxHeight: maxHeight
                )
            )
        case .doubleRightToLeft:
            let range = viewModel.currentPageRange
            if range.count == 1 {
                return AnyView(
                    singlePageContent(
                        url: viewModel.imageURLs[safe: range.lowerBound],
                        maxWidth: maxWidth,
                        maxHeight: maxHeight
                    )
                )
            }
            return AnyView(
                doublePageContent(
                    leftURL: viewModel.imageURLs[safe: range.lowerBound + 1],
                    rightURL: viewModel.imageURLs[safe: range.lowerBound],
                    maxWidth: maxWidth,
                    maxHeight: maxHeight
                )
            )
        case .doubleLeftToRight:
            let range = viewModel.currentPageRange
            if range.count == 1 {
                return AnyView(
                    singlePageContent(
                        url: viewModel.imageURLs[safe: range.lowerBound],
                        maxWidth: maxWidth,
                        maxHeight: maxHeight
                    )
                )
            }
            return AnyView(
                doublePageContent(
                    leftURL: viewModel.imageURLs[safe: range.lowerBound],
                    rightURL: viewModel.imageURLs[safe: range.lowerBound + 1],
                    maxWidth: maxWidth,
                    maxHeight: maxHeight
                )
            )
        }
    }

    private func doublePageContent(leftURL: URL?, rightURL: URL?, maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let leftImage = leftURL.flatMap { viewModel.cachedImage(for: $0) }
        let rightImage = rightURL.flatMap { viewModel.cachedImage(for: $0) }

        if let leftImage = leftImage, let rightImage = rightImage {
            let leftAspect = leftImage.size.width / leftImage.size.height
            let rightAspect = rightImage.size.width / rightImage.size.height
            let totalAspect = leftAspect + rightAspect
            let targetHeight = min(maxHeight, maxWidth / totalAspect)
            let leftWidth = leftAspect * targetHeight
            let rightWidth = rightAspect * targetHeight

            return AnyView(
                HStack(spacing: 0) {
                    Image(nsImage: leftImage)
                        .resizable()
                        .frame(width: leftWidth, height: targetHeight)
                    Image(nsImage: rightImage)
                        .resizable()
                        .frame(width: rightWidth, height: targetHeight)
                }
            )
        }

        return AnyView(
            HStack(spacing: 0) {
                if let leftURL = leftURL {
                    PageImage(url: leftURL, viewModel: viewModel)
                }
                if let rightURL = rightURL {
                    PageImage(url: rightURL, viewModel: viewModel)
                }
            }
            .scaledToFit()
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        )
    }

    private func singlePageContent(url: URL?, maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if let url = url {
                PageImage(url: url, viewModel: viewModel)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            }
            Spacer(minLength: 0)
        }
    }

    private func insertBlankPage(before url: URL) {
        Task {
            do {
                try await viewModel.insertBlankPage(before: url)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "插入空白页失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

}

// MARK: - 阅读器交互覆盖层

/// 一个透明的 AppKit 覆盖层，同时处理左键翻页、右键「插入空白页」和鼠标滚轮翻页。
/// 右键会根据点击位置自动判断是左页还是右页，只弹出一个菜单项。
struct ReaderInteractionOverlay: NSViewRepresentable {
    let layout: ReaderLayout
    let currentPageRange: Range<Int>
    let imageURLs: [URL]
    let isVersionMenuPresented: Bool
    let onCloseVersionMenu: () -> Void
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void
    let onInsertBlankPage: (URL) -> Void

    func makeNSView(context: Context) -> ReaderInteractionOverlayView {
        let view = ReaderInteractionOverlayView()
        view.update(
            layout: layout,
            currentPageRange: currentPageRange,
            imageURLs: imageURLs,
            isVersionMenuPresented: isVersionMenuPresented,
            onCloseVersionMenu: onCloseVersionMenu,
            onPreviousPage: onPreviousPage,
            onNextPage: onNextPage,
            onInsertBlankPage: onInsertBlankPage
        )
        return view
    }

    func updateNSView(_ nsView: ReaderInteractionOverlayView, context: Context) {
        nsView.update(
            layout: layout,
            currentPageRange: currentPageRange,
            imageURLs: imageURLs,
            isVersionMenuPresented: isVersionMenuPresented,
            onCloseVersionMenu: onCloseVersionMenu,
            onPreviousPage: onPreviousPage,
            onNextPage: onNextPage,
            onInsertBlankPage: onInsertBlankPage
        )
    }
}

final class ReaderInteractionOverlayView: NSView {
    private var layout: ReaderLayout = .single
    private var currentPageRange: Range<Int> = 0..<0
    private var imageURLs: [URL] = []
    private var isVersionMenuPresented: Bool = false
    private var onCloseVersionMenu: (() -> Void)?
    private var onPreviousPage: (() -> Void)?
    private var onNextPage: (() -> Void)?
    private var onInsertBlankPage: ((URL) -> Void)?

    /// 滚轮滚动累积量，超过阈值才触发翻页，避免轻微滚动就翻页。
    private var scrollAccumulator: CGFloat = 0
    /// 触发一次翻页所需的最小滚动量。数值越大灵敏度越低。
    private let scrollThreshold: CGFloat = 15

    func update(
        layout: ReaderLayout,
        currentPageRange: Range<Int>,
        imageURLs: [URL],
        isVersionMenuPresented: Bool,
        onCloseVersionMenu: @escaping () -> Void,
        onPreviousPage: @escaping () -> Void,
        onNextPage: @escaping () -> Void,
        onInsertBlankPage: @escaping (URL) -> Void
    ) {
        self.layout = layout
        self.currentPageRange = currentPageRange
        self.imageURLs = imageURLs
        self.isVersionMenuPresented = isVersionMenuPresented
        self.onCloseVersionMenu = onCloseVersionMenu
        self.onPreviousPage = onPreviousPage
        self.onNextPage = onNextPage
        self.onInsertBlankPage = onInsertBlankPage
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let isLeftSide = location.x < bounds.width / 2

        if isVersionMenuPresented {
            onCloseVersionMenu?()
        }

        switch layout {
        case .single, .doubleLeftToRight:
            isLeftSide ? onPreviousPage?() : onNextPage?()
        case .doubleRightToLeft:
            isLeftSide ? onNextPage?() : onPreviousPage?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let isLeftSide = location.x < bounds.width / 2

        guard let url = urlFor(side: isLeftSide ? .left : .right) else { return }

        let menu = NSMenu()
        let item = NSMenuItem(
            title: "在当前页前插入空白页",
            action: #selector(handleInsertBlankPage(_:)),
            keyEquivalent: ""
        )
        item.representedObject = url
        item.target = self
        menu.addItem(item)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleInsertBlankPage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onInsertBlankPage?(url)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY

        if isVersionMenuPresented {
            onCloseVersionMenu?()
        }

        // scrollingDeltaY < 0：向下滚动 → 下一页
        // scrollingDeltaY > 0：向上滚动 → 上一页
        if scrollAccumulator <= -scrollThreshold {
            scrollAccumulator += scrollThreshold
            onNextPage?()
        } else if scrollAccumulator >= scrollThreshold {
            scrollAccumulator -= scrollThreshold
            onPreviousPage?()
        }
    }

    private enum Side { case left, right }

    private func urlFor(side: Side) -> URL? {
        guard !imageURLs.isEmpty else { return nil }
        let range = currentPageRange
        if range.count == 1 || layout == .single {
            return imageURLs[safe: range.lowerBound]
        }
        switch (layout, side) {
        case (.doubleRightToLeft, .left):
            return imageURLs[safe: range.lowerBound + 1]
        case (.doubleRightToLeft, .right):
            return imageURLs[safe: range.lowerBound]
        case (.doubleLeftToRight, .left):
            return imageURLs[safe: range.lowerBound]
        case (.doubleLeftToRight, .right):
            return imageURLs[safe: range.lowerBound + 1]
        default:
            return nil
        }
    }
}

@MainActor
struct PageImage: View {
    let url: URL
    @ObservedObject var viewModel: ReaderViewModel
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = viewModel.cachedImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loadFailed {
                ContentUnavailableView("加载失败", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .task(id: url) {
            if viewModel.cachedImage(for: url) == nil {
                let image = await Task.detached(priority: .userInitiated) {
                    return NSImage(contentsOf: url)
                }.value
                if let image = image {
                    viewModel.setCachedImage(image, for: url)
                } else {
                    loadFailed = true
                }
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
