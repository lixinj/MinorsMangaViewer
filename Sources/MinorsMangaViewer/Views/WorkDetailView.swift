import SwiftUI

struct WorkDetailView: View {
    let work: Work
    var onRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(work.title)
                .font(.title)
                .fontWeight(.semibold)

            HStack {
                Text("作者：")
                    .fontWeight(.medium)
                Text(work.author.name)
            }

            HStack {
                Text("版本数：")
                    .fontWeight(.medium)
                Text("\(work.versions.count)")
            }

            Divider()

            Text("可用版本")
                .font(.headline)

            List(work.versions) { version in
                VStack(alignment: .leading, spacing: 4) {
                    Text(version.tagSummary)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(version.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("开始阅读") {
                onRead()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
