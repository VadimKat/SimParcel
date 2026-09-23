import Foundation
import UniformTypeIdentifiers

enum MediaKind: Sendable {
    case photo
    case video
    case livePhoto

    /// Classifies a single file by its extension, or returns `nil` for unsupported files.
    init?(file: URL) {
        guard file.isFileURL, let type = UTType(filenameExtension: file.pathExtension) else {
            return nil
        }

        if type.conforms(to: .image) {
            self = .photo
        } else if type.conforms(to: .movie) {
            self = .video
        } else {
            return nil
        }
    }
}

/// One entry in the import queue.
///
/// Files that share a folder and a base name are kept together, so the still image and video
/// of a Live Photo reach `simctl addmedia` in the same call and import as a single Live Photo.
struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String
    private(set) var files: [URL]
    var failure: String?

    init(file: URL) {
        id = Self.key(for: file)
        files = [file]
    }

    var kind: MediaKind {
        let kinds = files.compactMap(MediaKind.init(file:))
        if kinds.contains(.photo) && kinds.contains(.video) {
            return .livePhoto
        }

        return kinds.contains(.photo) ? .photo : .video
    }

    var name: String {
        files.count == 1 ? files[0].lastPathComponent : files[0].deletingPathExtension().lastPathComponent
    }

    /// The file to show as a thumbnail: the still image for a Live Photo.
    var previewFile: URL {
        files.first { MediaKind(file: $0) == .photo } ?? files[0]
    }

    /// Adds supported files to a queue, merging files that belong to the same Live Photo
    /// and skipping files that are already queued.
    static func merging(_ newFiles: [URL], into items: [MediaItem]) -> [MediaItem] {
        var items = items

        for file in newFiles where MediaKind(file: file) != nil {
            let key = key(for: file)
            if let index = items.firstIndex(where: { $0.id == key }) {
                if !items[index].files.contains(file) {
                    items[index].files.append(file)
                    items[index].failure = nil
                }
            } else {
                items.append(MediaItem(file: file))
            }
        }

        return items
    }

    private static func key(for file: URL) -> String {
        file.standardizedFileURL.deletingPathExtension().path.lowercased()
    }
}

enum MediaFiles {
    /// Expands folders and separates supported media from everything else.
    static func collect(from urls: [URL]) -> (media: [URL], skipped: [URL]) {
        var media: [URL] = []
        var skipped: [URL] = []

        for url in urls.flatMap(expand) {
            if MediaKind(file: url) == nil {
                skipped.append(url)
            } else {
                media.append(url)
            }
        }

        return (media, skipped)
    }

    /// Describes files that were left out of the queue, naming the file when there is only one.
    /// The detail lists the skipped files for a tooltip.
    static func skippedSummary(_ skipped: [URL], addedMedia: Bool) -> (message: String, detail: String?)? {
        let names = skipped.map(\.lastPathComponent)
        let detailLimit = 10
        let detail = names.count > detailLimit
            ? (names.prefix(detailLimit) + ["and \(names.count - detailLimit) more"]).joined(separator: "\n")
            : names.joined(separator: "\n")

        switch (names.count, addedMedia) {
        case (0, true):
            return nil
        case (0, false):
            return ("No photos or videos found.", nil)
        case (1, true):
            return ("Skipped \(names[0]) — not a photo or video.", skipped[0].path)
        case (1, false):
            return ("\(names[0]) isn’t a photo or video.", skipped[0].path)
        case (let count, true):
            return ("Skipped \(count) files that aren’t photos or videos.", detail)
        case (let count, false):
            return ("None of the \(count) files are photos or videos.", detail)
        }
    }

    private static func expand(_ url: URL) -> [URL] {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
        guard isDirectory, !isPackage else {
            return [url]
        }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
