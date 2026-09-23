import Foundation

/// The Files app's On My iPhone folder inside a simulator's data directory.
enum FilesStorage {
    static let appGroup = "group.com.apple.FileProvider.LocalStorage"
    static let folderName = "File Provider Storage"

    /// Reads the app group path from `simctl get_app_container <device> com.apple.DocumentsApp groups`,
    /// which prints one `identifier<TAB>path` line per group.
    static func groupPath(inGroupsOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", maxSplits: 1)
            guard columns.count == 2, columns[0].trimmingCharacters(in: .whitespaces) == appGroup else {
                continue
            }

            return columns[1].trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    /// Finds the app group by its container metadata. Used when `simctl` can't look up the Files app,
    /// as happens on some iOS 27 runtimes.
    static func findGroup(inDataPath dataPath: String) -> URL? {
        let groups = URL(fileURLWithPath: dataPath).appendingPathComponent("Containers/Shared/AppGroup")
        let containers = (try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil)) ?? []

        return containers.first { container in
            let metadata = container.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: metadata),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return false
            }

            return plist["MCMMetadataIdentifier"] as? String == appGroup
        }
    }

    /// Copies a file or package into the folder under a free name. The copy is written under a hidden name
    /// first and then renamed, so the Files app never shows a half-written file.
    @discardableResult
    static func copy(_ source: URL, into folder: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let partial = folder.appendingPathComponent(".\(UUID().uuidString).partial")
        try fileManager.copyItem(at: source, to: partial)

        do {
            let destination = availableURL(for: source.lastPathComponent, in: folder) {
                fileManager.fileExists(atPath: $0.path)
            }
            try fileManager.moveItem(at: partial, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }

    /// Returns `name`, or `name 2`, `name 3`… when taken, keeping the extension: "photo 2.png".
    static func availableURL(for name: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard exists(candidate) else {
            return candidate
        }

        let base = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        var number = 2
        while true {
            let numbered = pathExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(pathExtension)"
            let url = folder.appendingPathComponent(numbered)
            if !exists(url) {
                return url
            }
            number += 1
        }
    }
}
