import Foundation
import Testing

struct FilesStorageTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func readsTheGroupFromSimctlOutput() {
        let output = """
        group.com.apple.DocumentManager\t/Devices/A/data/Containers/Shared/AppGroup/1
        group.com.apple.FileProvider.LocalStorage\t/Devices/A/data/Containers/Shared/AppGroup/My Group
        group.com.apple.tipsnext\t/Devices/A/data/Containers/Shared/AppGroup/3
        """

        #expect(FilesStorage.groupPath(inGroupsOutput: output) == "/Devices/A/data/Containers/Shared/AppGroup/My Group")
        #expect(FilesStorage.groupPath(inGroupsOutput: "group.com.apple.tipsnext\t/x") == nil)
        #expect(FilesStorage.groupPath(inGroupsOutput: "") == nil)
    }

    @Test func findsTheGroupByContainerMetadata() throws {
        let data = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: data)
        }

        let groups = data.appendingPathComponent("Containers/Shared/AppGroup")
        for (name, identifier) in [("A", "group.com.apple.tipsnext"), ("B", FilesStorage.appGroup)] {
            let container = groups.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["MCMMetadataIdentifier": identifier],
                format: .binary,
                options: 0
            )
            try plist.write(to: container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"))
        }

        #expect(FilesStorage.findGroup(inDataPath: data.path)?.lastPathComponent == "B")
        #expect(FilesStorage.findGroup(inDataPath: "/nonexistent") == nil)
    }

    @Test func numbersNamesThatAreTaken() {
        let folder = URL(fileURLWithPath: "/Files")
        let taken: Set<String> = ["photo.png", "photo 2.png", "README"]
        let exists = { (url: URL) in taken.contains(url.lastPathComponent) }

        #expect(FilesStorage.availableURL(for: "photo.png", in: folder, exists: exists).lastPathComponent == "photo 3.png")
        #expect(FilesStorage.availableURL(for: "README", in: folder, exists: exists).lastPathComponent == "README 2")
        #expect(FilesStorage.availableURL(for: "new.pdf", in: folder, exists: exists).lastPathComponent == "new.pdf")
    }

    @Test func copiesIntoANewFolderWithoutLeavingPartialFiles() throws {
        let root = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let source = root.appendingPathComponent("report.pdf")
        try Data("pdf".utf8).write(to: source)
        let folder = root.appendingPathComponent("File Provider Storage")

        let first = try FilesStorage.copy(source, into: folder)
        let second = try FilesStorage.copy(source, into: folder)

        #expect(first.lastPathComponent == "report.pdf")
        #expect(second.lastPathComponent == "report 2.pdf")
        #expect(try Data(contentsOf: second) == Data("pdf".utf8))
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(contents.sorted() == ["report 2.pdf", "report.pdf"])
    }
}
