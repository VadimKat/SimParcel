import Foundation
import Testing

struct SimulatorListTests {
    private let json = Data("""
    {
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          { "udid": "A", "name": "iPhone 17", "state": "Shutdown", "isAvailable": true }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [
          { "udid": "B", "name": "iPhone 17 Pro", "state": "Shutdown", "isAvailable": true },
          { "udid": "C", "name": "iPad Air", "state": "Booted", "isAvailable": true }
        ],
        "com.apple.CoreSimulator.SimRuntime.watchOS-12-0": [
          { "udid": "D", "name": "Apple Watch", "state": "Shutdown", "isAvailable": true }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": []
      }
    }
    """.utf8)

    @Test func parsesRuntimeIdentifiers() throws {
        let runtime = try #require(SimulatorRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-1"))
        #expect(runtime.platform == "iOS")
        #expect(runtime.version == [27, 1])
        #expect(runtime.name == "iOS 27.1")

        #expect(SimulatorRuntime(identifier: "com.example.iOS-27") == nil)
        #expect(SimulatorRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-beta") == nil)
    }

    @Test func comparesVersionsNumerically() {
        #expect(SimulatorRuntime(platform: "iOS", version: [9, 0]) < SimulatorRuntime(platform: "iOS", version: [17, 5]))
        #expect(SimulatorRuntime(platform: "iOS", version: [27]) < SimulatorRuntime(platform: "iOS", version: [27, 1]))
    }

    @Test func keepsOnlyIOSDevices() throws {
        let devices = try SimulatorList.parse(json)
        #expect(Set(devices.map(\.id)) == ["A", "B", "C"])
        #expect(devices.first { $0.id == "C" }?.isBooted == true)
    }

    @Test func rejectsNonJSONOutput() {
        #expect(throws: (any Error).self) {
            try SimulatorList.parse(Data("xcrun: warning\n{}".utf8))
        }
    }

    @Test func groupsNewestRuntimeFirstWithRunningDevicesFirst() throws {
        let groups = SimulatorList.grouped(try SimulatorList.parse(json))
        #expect(groups.map(\.runtime.name) == ["iOS 27.1", "iOS 26.5"])
        #expect(groups[0].devices.map(\.id) == ["C", "B"])
    }

    @Test func prefersRunningDevice() throws {
        let devices = try SimulatorList.parse(json)
        #expect(SimulatorList.preferredDevice(in: devices)?.id == "C")

        let shutDown = devices.filter { !$0.isBooted }
        #expect(SimulatorList.preferredDevice(in: shutDown)?.id == "B")
        #expect(SimulatorList.preferredDevice(in: []) == nil)
    }
}
