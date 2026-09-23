import Foundation

enum SimulatorServiceError: LocalizedError {
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message
        case .invalidResponse:
            "Could not read the simulator list."
        }
    }
}

enum SimulatorService {
    static func availableDevices() async throws -> [SimulatorDevice] {
        let output = try await simctl(["list", "devices", "available", "--json"])
        do {
            return try SimulatorList.parse(output)
        } catch {
            throw SimulatorServiceError.invalidResponse
        }
    }

    /// Boots the device unless it is already running, then shows it in Simulator.
    ///
    /// The state is read again here because the device may have been started or shut down
    /// since the list was last refreshed.
    static func bootIfNeeded(_ device: SimulatorDevice) async throws {
        let isBooted = try await availableDevices().first { $0.id == device.id }?.isBooted ?? false
        guard !isBooted else {
            return
        }

        _ = try await simctl(["bootstatus", device.id, "-b"])
        try? await openSimulatorApp(showing: device)
    }

    static func show(_ device: SimulatorDevice) async throws {
        _ = try await simctl(["bootstatus", device.id, "-b"])
        try await openSimulatorApp(showing: device)
    }

    /// Imports files with one `simctl addmedia` call, so a Live Photo's image and video are paired.
    static func addMedia(_ files: [URL], to device: SimulatorDevice) async throws {
        _ = try await simctl(["addmedia", device.id] + files.map(\.path))
    }

    private static func openSimulatorApp(showing device: SimulatorDevice) async throws {
        let developerDirectory = try await run("/usr/bin/xcode-select", ["-p"])
        let path = String(decoding: developerDirectory, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let simulatorApp = URL(fileURLWithPath: path).appendingPathComponent("Applications/Simulator.app")
        let application = FileManager.default.fileExists(atPath: simulatorApp.path) ? simulatorApp.path : "Simulator"

        _ = try await run("/usr/bin/open", ["-a", application, "--args", "-CurrentDeviceUDID", device.id])
    }

    private static func simctl(_ arguments: [String]) async throws -> Data {
        try await run("/usr/bin/xcrun", ["simctl"] + arguments)
    }

    /// Runs a command without blocking a thread while waiting for it, and returns its standard output.
    /// Standard error is kept separate so warnings cannot corrupt JSON output.
    private static func run(_ executable: String, _ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        async let output = readToEnd(outputPipe.fileHandleForReading)
        async let errorOutput = readToEnd(errorPipe.fileHandleForReading)

        let status: Int32
        do {
            status = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            // The process never started, so close the write ends to let the readers finish.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            _ = try? await (output, errorOutput)
            throw SimulatorServiceError.commandFailed(
                "Could not run \(executable): \(error.localizedDescription)"
            )
        }

        let (outputData, errorData) = try await (output, errorOutput)
        guard status == 0 else {
            let message = [errorData, outputData]
                .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
                .map(conciseMessage)
            throw SimulatorServiceError.commandFailed(message ?? "\(executable) exited with status \(status).")
        }

        return outputData
    }

    /// Keeps error output readable: simctl sometimes crashes and prints an exception with a full stack trace.
    private static func conciseMessage(_ output: String) -> String {
        if let reason = output.range(of: "reason: '"),
           let end = output[reason.upperBound...].firstIndex(of: "'") {
            return "simctl crashed: \(output[reason.upperBound..<end])"
        }

        let lines = output.split(whereSeparator: \.isNewline)
        return lines.prefix(3).joined(separator: "\n") + (lines.count > 3 ? "…" : "")
    }

    private static func readToEnd(_ handle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in handle.bytes {
            data.append(byte)
        }

        return data
    }
}
