import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case idle
        case info(String, detail: String? = nil)
        case working(String)
        case success(String)
        case failure(String, detail: String? = nil)
    }

    private static let selectedDeviceKey = "selectedSimulatorID"

    private(set) var devices: [SimulatorDevice] = []
    private(set) var items: [MediaItem] = []
    private(set) var isRefreshing = false
    private(set) var isImporting = false
    private(set) var importingItemID: MediaItem.ID?
    private(set) var importedCount = 0
    private(set) var importTotal = 0
    private(set) var status: Status = .idle
    var isFilePickerPresented = false

    var selectedDeviceID: String = UserDefaults.standard.string(forKey: AppModel.selectedDeviceKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedDeviceID, forKey: Self.selectedDeviceKey)
        }
    }

    var runtimeGroups: [SimulatorRuntimeGroup] {
        SimulatorList.grouped(devices)
    }

    var selectedDevice: SimulatorDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var isBusy: Bool {
        isRefreshing || isImporting
    }

    var canImport: Bool {
        !items.isEmpty && selectedDevice != nil && !isBusy
    }

    var failedCount: Int {
        items.filter { $0.failure != nil }.count
    }

    func refreshDevices() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            devices = try await SimulatorService.availableDevices()

            if selectedDevice == nil {
                selectedDeviceID = SimulatorList.preferredDevice(in: devices)?.id ?? ""
            }

            if devices.isEmpty {
                status = .failure("No iOS simulators found. Install an iOS runtime in Xcode, then refresh.")
            } else if case .failure = status, failedCount == 0 {
                status = .idle
            }
        } catch {
            status = .failure("Could not list simulators: \(error.localizedDescription)")
        }
    }

    func add(_ urls: [URL]) async {
        guard !isImporting, !urls.isEmpty else {
            return
        }

        let (media, skipped) = await Task.detached(priority: .userInitiated) {
            MediaFiles.collect(from: urls)
        }.value

        items = MediaItem.merging(media, into: items)

        if let summary = MediaFiles.skippedSummary(skipped, addedMedia: !media.isEmpty) {
            status = media.isEmpty
                ? .failure(summary.message, detail: summary.detail)
                : .info(summary.message, detail: summary.detail)
        } else {
            status = .idle
        }
    }

    func reportFilePickerError(_ error: Error) {
        status = .failure("Could not open files: \(error.localizedDescription)")
    }

    func remove(_ item: MediaItem) {
        guard !isImporting else {
            return
        }

        items.removeAll { $0.id == item.id }
        if items.isEmpty {
            status = .idle
        }
    }

    func removeAll() {
        guard !isImporting else {
            return
        }

        items.removeAll()
        status = .idle
    }

    func importAll() async {
        guard canImport, let device = selectedDevice else {
            return
        }

        isImporting = true
        importedCount = 0
        importTotal = items.count
        defer {
            isImporting = false
            importingItemID = nil
        }

        do {
            if !device.isBooted {
                status = .working("Starting \(device.name)…")
            }
            try await SimulatorService.bootIfNeeded(device)
        } catch {
            status = .failure("Could not start \(device.name): \(error.localizedDescription)")
            return
        }

        var succeeded = 0
        var lastFailure: String?

        for item in items {
            importingItemID = item.id
            status = .working("Importing \(importedCount + 1) of \(importTotal)…")

            do {
                // simctl crashes instead of reporting an error when a file is missing.
                if let missing = item.files.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
                    throw SimulatorServiceError.commandFailed("\(missing.lastPathComponent) no longer exists.")
                }

                try await SimulatorService.addMedia(item.files, to: device)
                items.removeAll { $0.id == item.id }
                succeeded += 1
            } catch {
                let message = error.localizedDescription
                lastFailure = message
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].failure = message
                }
            }

            importedCount += 1
        }

        let noun = succeeded == 1 ? "item" : "items"
        if let lastFailure {
            let failed = importTotal - succeeded
            status = .failure("Added \(succeeded) \(noun). \(failed) failed: \(lastFailure)")
        } else {
            status = .success("Added \(succeeded) \(noun) to \(device.name).")
        }

        await refreshDevices()
    }

    func showSelectedDevice() async {
        guard let device = selectedDevice, !isBusy else {
            return
        }

        isImporting = true
        defer {
            isImporting = false
        }

        if !device.isBooted {
            status = .working("Starting \(device.name)…")
        }

        do {
            try await SimulatorService.show(device)
            if case .working = status {
                status = .idle
            }
        } catch {
            status = .failure("Could not open \(device.name): \(error.localizedDescription)")
        }

        await refreshDevices()
    }
}
