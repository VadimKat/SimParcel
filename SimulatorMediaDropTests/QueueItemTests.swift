import Foundation
import Testing

struct QueueItemTests {
    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test func classifiesURLs() {
        #expect(ItemKind(url: file("/a/IMG_1.HEIC")) == .photo)
        #expect(ItemKind(url: file("/a/clip.mov")) == .video)
        #expect(ItemKind(url: file("/a/clip.mp4")) == .video)
        #expect(ItemKind(url: file("/a/Jane.vcf")) == .contact)
        #expect(ItemKind(url: file("/a/MyApp.app")) == .app)
        #expect(ItemKind(url: file("/a/payload.apns")) == .push)
        #expect(ItemKind(url: URL(string: "https://example.com/a.jpg")!) == .link)
        #expect(ItemKind(url: URL(string: "myapp://settings")!) == .link)
        #expect(ItemKind(url: file("/a/notes.txt")) == nil)
        #expect(ItemKind(url: file("/a/payload.json")) == nil)
        #expect(ItemKind(url: file("/a/README")) == nil)
    }

    @Test func pairsLivePhotoFiles() {
        let items = QueueItem.merging(
            [file("/a/IMG_1.HEIC"), file("/a/IMG_1.MOV"), file("/a/IMG_2.jpg")],
            into: []
        )

        #expect(items.count == 2)
        #expect(items[0].kind == .livePhoto)
        #expect(items[0].urls.count == 2)
        #expect(items[0].name == "IMG_1")
        #expect(items[0].previewURL.lastPathComponent == "IMG_1.HEIC")
        #expect(items[1].kind == .photo)
        #expect(items[1].name == "IMG_2.jpg")
    }

    @Test func doesNotPairFilesFromDifferentFolders() {
        let items = QueueItem.merging([file("/a/IMG_1.HEIC"), file("/b/IMG_1.MOV")], into: [])
        #expect(items.map(\.kind) == [.photo, .video])
    }

    @Test func doesNotPairNonMediaFilesWithMedia() {
        let items = QueueItem.merging(
            [file("/a/Jane.jpg"), file("/a/Jane.vcf"), file("/a/Demo.app"), file("/a/Demo.apns")],
            into: []
        )
        #expect(items.map(\.kind) == [.photo, .contact, .app, .push])
    }

    @Test func keepsLinksAsSeparateItems() {
        let links = [URL(string: "https://example.com")!, URL(string: "myapp://settings")!]
        let items = QueueItem.merging(links + [links[0]], into: [])

        #expect(items.map(\.kind) == [.link, .link])
        #expect(items.map(\.name) == ["https://example.com", "myapp://settings"])
    }

    @Test func skipsDuplicatesAndUnsupportedFiles() {
        let queue = QueueItem.merging([file("/a/IMG_1.HEIC")], into: [])
        let items = QueueItem.merging([file("/a/IMG_1.HEIC"), file("/a/notes.txt")], into: queue)
        #expect(items == queue)
    }

    @Test func addingPairedFileClearsPreviousFailure() {
        var queue = QueueItem.merging([file("/a/IMG_1.HEIC")], into: [])
        queue[0].failure = "Failed"

        let items = QueueItem.merging([file("/a/IMG_1.MOV")], into: queue)
        #expect(items[0].failure == nil)
        #expect(items[0].kind == .livePhoto)
    }

    @Test func sendsAppsFirstAndLinksLast() {
        let kinds: [ItemKind] = [.link, .push, .photo, .app, .contact]
        let sorted = kinds.sorted { $0.sendOrder < $1.sendOrder }
        #expect(sorted.first == .app)
        #expect(sorted.last == .link)
    }

    @Test func expandsFoldersKeepingAppBundlesWhole() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = folder.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Demo.app/Contents"),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        for name in ["b.jpg", "a.mov", "notes.txt", ".hidden.jpg", "Nested/c.png", "Demo.app/Contents/Info.plist"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }

        let result = DroppedFiles.collect(from: [folder, file("/a/loose.heic")])
        #expect(result.supported.map(\.lastPathComponent) == ["a.mov", "b.jpg", "Demo.app", "c.png", "loose.heic"])
        #expect(result.skipped.map(\.lastPathComponent) == ["notes.txt"])
    }

    @Test func namesASingleSkippedFile() {
        let summary = DroppedFiles.skippedSummary([file("/a/notes.txt")], addedAny: true)
        #expect(summary?.message == "Skipped notes.txt — this file type isn’t supported.")
        #expect(summary?.detail == "/a/notes.txt")

        let nothingAdded = DroppedFiles.skippedSummary([file("/a/notes.txt")], addedAny: false)
        #expect(nothingAdded?.message == "notes.txt can’t be sent to a simulator.")
    }

    @Test func countsSeveralSkippedFilesAndListsThemInDetail() {
        let skipped = (1...12).map { file("/a/file\($0).txt") }

        let summary = DroppedFiles.skippedSummary(skipped, addedAny: true)
        #expect(summary?.message == "Skipped 12 files of unsupported types.")
        #expect(summary?.detail?.hasPrefix("file1.txt\nfile2.txt") == true)
        #expect(summary?.detail?.hasSuffix("file10.txt\nand 2 more") == true)

        let nothingAdded = DroppedFiles.skippedSummary(Array(skipped.prefix(2)), addedAny: false)
        #expect(nothingAdded?.message == "None of the 2 files can be sent to a simulator.")
        #expect(nothingAdded?.detail == "file1.txt\nfile2.txt")
    }

    @Test func summarizesOnlyWhenSomethingWasLeftOut() {
        #expect(DroppedFiles.skippedSummary([], addedAny: true) == nil)
        #expect(DroppedFiles.skippedSummary([], addedAny: false)?.message == "Nothing to add.")
    }
}

struct PushPayloadTests {
    private func payload(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test func acceptsPayloadWithTargetBundle() throws {
        try PushPayload.validate(payload(#"{"Simulator Target Bundle": "com.example.app", "aps": {"alert": "Hi"}}"#))
    }

    @Test func explainsWhatIsMissing() {
        #expect(throws: PushPayloadError.missingTargetBundle) {
            try PushPayload.validate(payload(#"{"aps": {"alert": "Hi"}}"#))
        }
        #expect(throws: PushPayloadError.missingAPS) {
            try PushPayload.validate(payload(#"{"Simulator Target Bundle": "com.example.app"}"#))
        }
        #expect(throws: PushPayloadError.notJSONObject) {
            try PushPayload.validate(payload("[1, 2]"))
        }
        #expect(throws: PushPayloadError.tooLarge) {
            try PushPayload.validate(Data(count: 5000))
        }
    }
}
