import Foundation
import UniformTypeIdentifiers

enum ItemKind: Sendable, Hashable {
    case photo
    case video
    case livePhoto
    case contact
    case app
    case push
    case link
    /// Any other file, copied to the Files app's On My iPhone folder.
    case file

    /// Classifies a dropped URL. Files that aren't media, contacts, apps or push payloads go to the Files app.
    init?(url: URL) {
        guard url.isFileURL else {
            // Web links and custom-scheme deep links open in the simulator.
            guard let scheme = url.scheme, !scheme.isEmpty else {
                return nil
            }
            self = .link
            return
        }

        // Checked by extension: without the file system, UTType can't tell that ".app" is an app bundle.
        switch url.pathExtension.lowercased() {
        case "apns":
            self = .push
            return
        case "app":
            self = .app
            return
        default:
            break
        }

        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .vCard) == true {
            self = .contact
        } else if type?.conforms(to: .image) == true {
            self = .photo
        } else if type?.conforms(to: .movie) == true {
            self = .video
        } else {
            self = .file
        }
    }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .livePhoto: "Live Photo"
        case .contact: "Contact"
        case .app: "App"
        case .push: "Push Notification"
        case .link: "Link"
        case .file: "File"
        }
    }

    var isMedia: Bool {
        [.photo, .video, .livePhoto].contains(self)
    }

    /// Apps are installed first so that push notifications and links sent in the same batch can reach them.
    var sendOrder: Int {
        switch self {
        case .app: 0
        case .photo, .video, .livePhoto, .contact, .file: 1
        case .push: 2
        case .link: 3
        }
    }
}

/// One entry in the queue.
///
/// Photos and videos that share a folder and a base name are kept together, so the still image and video
/// of a Live Photo reach `simctl addmedia` in the same call and import as a single Live Photo.
struct QueueItem: Identifiable, Hashable, Sendable {
    let id: String
    private(set) var urls: [URL]
    var failure: String?

    init(url: URL) {
        id = Self.key(for: url)
        urls = [url]
    }

    var kind: ItemKind {
        let kinds = urls.compactMap(ItemKind.init(url:))
        if kinds.contains(.photo) && kinds.contains(.video) {
            return .livePhoto
        }

        return kinds.first ?? .photo
    }

    var name: String {
        if kind == .link, let url = urls.first {
            return url.absoluteString
        }

        return urls.count == 1 ? urls[0].lastPathComponent : urls[0].deletingPathExtension().lastPathComponent
    }

    /// The file to show as a thumbnail: the still image for a Live Photo.
    var previewURL: URL {
        urls.first { ItemKind(url: $0) == .photo } ?? urls[0]
    }

    /// Adds supported URLs to a queue, merging the files of a Live Photo and skipping URLs that are already queued.
    static func merging(_ newURLs: [URL], into items: [QueueItem]) -> [QueueItem] {
        var items = items

        for url in newURLs where ItemKind(url: url) != nil {
            let key = key(for: url)
            if let index = items.firstIndex(where: { $0.id == key }) {
                if !items[index].urls.contains(url) {
                    items[index].urls.append(url)
                    items[index].failure = nil
                }
            } else {
                items.append(QueueItem(url: url))
            }
        }

        return items
    }

    private static func key(for url: URL) -> String {
        guard url.isFileURL else {
            return "link:\(url.absoluteString)"
        }

        let path = url.standardizedFileURL.path.lowercased()
        if ItemKind(url: url)?.isMedia == true {
            return "media:" + (path as NSString).deletingPathExtension
        }

        return "file:" + path
    }
}

enum PushPayload {
    static let targetBundleKey = "Simulator Target Bundle"

    /// Checks what `simctl push` needs when no bundle identifier is passed, so the error can say how to fix the file.
    static func validate(_ data: Data) throws(PushPayloadError) {
        guard data.count <= 4096 else {
            throw .tooLarge
        }

        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .notJSONObject
        }

        guard object["aps"] is [String: Any] else {
            throw .missingAPS
        }

        guard let bundle = object[targetBundleKey] as? String, !bundle.isEmpty else {
            throw .missingTargetBundle
        }
    }
}

enum PushPayloadError: LocalizedError, Equatable {
    case tooLarge
    case notJSONObject
    case missingAPS
    case missingTargetBundle

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            "The payload is larger than 4 KB."
        case .notJSONObject:
            "The payload must be a JSON object."
        case .missingAPS:
            "The payload needs an \"aps\" dictionary."
        case .missingTargetBundle:
            "Add a \"\(PushPayload.targetBundleKey)\" key with your app’s bundle ID to the payload."
        }
    }
}

enum DroppedFiles {
    /// Expands folders and separates supported items from everything else.
    static func collect(from urls: [URL]) -> (supported: [URL], skipped: [URL]) {
        var supported: [URL] = []
        var skipped: [URL] = []

        for url in urls.flatMap(expand) {
            if ItemKind(url: url) == nil {
                skipped.append(url)
            } else {
                supported.append(url)
            }
        }

        return (supported, skipped)
    }

    /// Describes files that were left out of the queue, naming the file when there is only one.
    /// The detail lists the skipped files for a tooltip.
    static func skippedSummary(_ skipped: [URL], addedAny: Bool) -> (message: String, detail: String?)? {
        let names = skipped.map(\.lastPathComponent)
        let detailLimit = 10
        let detail = names.count > detailLimit
            ? (names.prefix(detailLimit) + ["and \(names.count - detailLimit) more"]).joined(separator: "\n")
            : names.joined(separator: "\n")

        switch (names.count, addedAny) {
        case (0, true):
            return nil
        case (0, false):
            return ("Nothing to add.", nil)
        case (1, true):
            return ("Skipped \(names[0]) — it can’t be sent to a simulator.", skipped[0].path)
        case (1, false):
            return ("\(names[0]) can’t be sent to a simulator.", skipped[0].path)
        case (let count, true):
            return ("Skipped \(count) items that can’t be sent to a simulator.", detail)
        case (let count, false):
            return ("None of the \(count) items can be sent to a simulator.", detail)
        }
    }

    private static func expand(_ url: URL) -> [URL] {
        guard url.isFileURL else {
            return [url]
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values?.isDirectory == true, values?.isPackage != true else {
            return [url]
        }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        return (enumerator?.allObjects as? [URL] ?? [])
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey])
                return values?.isRegularFile == true || values?.isPackage == true
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
