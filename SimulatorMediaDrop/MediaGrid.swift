import QuickLookThumbnailing
import SwiftUI

struct MediaGrid: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(summary)
                    .font(.headline)

                if model.failedCount > 0 {
                    Text("\(model.failedCount) failed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }

                Spacer()

                Button("Clear All", role: .destructive) {
                    withAnimation {
                        model.removeAll()
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.isImporting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.items) { item in
                        MediaTile(item: item, isImporting: model.importingItemID == item.id)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .animation(.spring(duration: 0.3), value: model.items.map(\.id))
            }
        }
    }

    private var summary: String {
        let count = model.items.count
        return count == 1 ? "1 item" : "\(count) items"
    }
}

private struct MediaTile: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    let item: MediaItem
    let isImporting: Bool

    var body: some View {
        VStack(spacing: 6) {
            Thumbnail(file: item.previewFile)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(item.failure == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(.red), lineWidth: item.failure == nil ? 0.5 : 2)
                }
                .overlay(alignment: .bottomLeading) {
                    kindBadge
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if isHovered && !model.isImporting {
                        removeButton
                            .padding(5)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if item.failure != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .font(.title3)
                            .padding(5)
                    }
                }
                .overlay {
                    if isImporting {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    }
                }
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            Text(item.name)
                .font(.caption)
                .foregroundStyle(item.failure == nil ? .primary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(item.failure.map { "Import failed: \($0)" } ?? item.files.map(\.path).joined(separator: "\n"))
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(item.files)
            }

            Divider()

            Button("Remove", role: .destructive) {
                model.remove(item)
            }
            .disabled(model.isImporting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Remove") {
            model.remove(item)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        switch item.kind {
        case .photo:
            EmptyView()
        case .video:
            badge("video.fill", "Video")
        case .livePhoto:
            badge("livephoto", "Live")
        }
    }

    private func badge(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var removeButton: some View {
        Button {
            model.remove(item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
                .font(.title3)
        }
        .buttonStyle(.plain)
        .help("Remove from queue")
    }

    private var accessibilityLabel: String {
        let kind = switch item.kind {
        case .photo: "Photo"
        case .video: "Video"
        case .livePhoto: "Live Photo"
        }

        if let failure = item.failure {
            return "\(kind), \(item.name), import failed: \(failure)"
        }

        return "\(kind), \(item.name)"
    }
}

private struct Thumbnail: View {
    let file: URL
    @State private var image: NSImage?

    var body: some View {
        // The square container defines the size; the image fills it and is cropped, never widening the tile.
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: file) {
                image = await Self.thumbnail(for: file)
            }
    }

    private static func thumbnail(for file: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: 150, height: 150),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        guard let cgImage = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage else {
            return NSWorkspace.shared.icon(forFile: file.path)
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }
}
