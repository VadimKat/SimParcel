import Foundation
import Testing

struct MediaItemTests {
    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test func classifiesFilesByExtension() {
        #expect(MediaKind(file: file("/a/IMG_1.HEIC")) == .photo)
        #expect(MediaKind(file: file("/a/clip.mov")) == .video)
        #expect(MediaKind(file: file("/a/clip.mp4")) == .video)
        #expect(MediaKind(file: file("/a/notes.txt")) == nil)
        #expect(MediaKind(file: file("/a/README")) == nil)
        #expect(MediaKind(file: URL(string: "https://example.com/a.jpg")!) == nil)
    }

    @Test func pairsLivePhotoFiles() {
        let items = MediaItem.merging(
            [file("/a/IMG_1.HEIC"), file("/a/IMG_1.MOV"), file("/a/IMG_2.jpg")],
            into: []
        )

        #expect(items.count == 2)
        #expect(items[0].kind == .livePhoto)
        #expect(items[0].files.count == 2)
        #expect(items[0].name == "IMG_1")
        #expect(items[0].previewFile.lastPathComponent == "IMG_1.HEIC")
        #expect(items[1].kind == .photo)
        #expect(items[1].name == "IMG_2.jpg")
    }

    @Test func doesNotPairFilesFromDifferentFolders() {
        let items = MediaItem.merging([file("/a/IMG_1.HEIC"), file("/b/IMG_1.MOV")], into: [])
        #expect(items.map(\.kind) == [.photo, .video])
    }

    @Test func skipsDuplicatesAndUnsupportedFiles() {
        let queue = MediaItem.merging([file("/a/IMG_1.HEIC")], into: [])
        let items = MediaItem.merging([file("/a/IMG_1.HEIC"), file("/a/notes.txt")], into: queue)
        #expect(items == queue)
    }

    @Test func addingPairedFileClearsPreviousFailure() {
        var queue = MediaItem.merging([file("/a/IMG_1.HEIC")], into: [])
        queue[0].failure = "Failed"

        let items = MediaItem.merging([file("/a/IMG_1.MOV")], into: queue)
        #expect(items[0].failure == nil)
        #expect(items[0].kind == .livePhoto)
    }

    @Test func expandsFoldersAndReportsSkippedFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = folder.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        for name in ["b.jpg", "a.mov", "notes.txt", ".hidden.jpg", "Nested/c.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }

        let result = MediaFiles.collect(from: [folder, file("/a/loose.heic")])
        #expect(result.media.map(\.lastPathComponent) == ["a.mov", "b.jpg", "c.png", "loose.heic"])
        #expect(result.skipped.map(\.lastPathComponent) == ["notes.txt"])
    }

    @Test func namesASingleSkippedFile() {
        let summary = MediaFiles.skippedSummary([file("/a/notes.txt")], addedMedia: true)
        #expect(summary?.message == "Skipped notes.txt — not a photo or video.")
        #expect(summary?.detail == "/a/notes.txt")

        let nothingAdded = MediaFiles.skippedSummary([file("/a/notes.txt")], addedMedia: false)
        #expect(nothingAdded?.message == "notes.txt isn’t a photo or video.")
    }

    @Test func countsSeveralSkippedFilesAndListsThemInDetail() {
        let skipped = (1...12).map { file("/a/file\($0).txt") }

        let summary = MediaFiles.skippedSummary(skipped, addedMedia: true)
        #expect(summary?.message == "Skipped 12 files that aren’t photos or videos.")
        #expect(summary?.detail?.hasPrefix("file1.txt\nfile2.txt") == true)
        #expect(summary?.detail?.hasSuffix("file10.txt\nand 2 more") == true)

        let nothingAdded = MediaFiles.skippedSummary(Array(skipped.prefix(2)), addedMedia: false)
        #expect(nothingAdded?.message == "None of the 2 files are photos or videos.")
        #expect(nothingAdded?.detail == "file1.txt\nfile2.txt")
    }

    @Test func summarizesOnlyWhenSomethingWasLeftOut() {
        #expect(MediaFiles.skippedSummary([], addedMedia: true) == nil)
        #expect(MediaFiles.skippedSummary([], addedMedia: false)?.message == "No photos or videos found.")
    }
}
