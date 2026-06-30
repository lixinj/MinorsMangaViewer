import SwiftUI

struct WorkGridItem: View {
    let work: Work
    let isSelected: Bool
    var isWide: Bool = false
    @State private var thumbnail: NSImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .aspectRatio(isWide ? 3/2 : 3/4, contentMode: .fit)
                    .frame(height: 220)

                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(6)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            Text(work.isAnthology ? work.fullTitle : work.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .task {
            guard let version = work.primaryVersion else { return }
            isLoading = true
            thumbnail = await ThumbnailCache.shared.thumbnail(for: version)
            isLoading = false
        }
    }
}
