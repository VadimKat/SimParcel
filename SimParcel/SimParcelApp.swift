import Sparkle
import SwiftUI

@main
struct SimParcelApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    /// Checks the appcast in Info.plist (`SUFeedURL`) once a day and on demand.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Window("SimParcel", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 640, height: 580)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updaterController.updater)
            }

            CommandGroup(replacing: .newItem) {
                Button("Choose Files…") {
                    model.isFilePickerPresented = true
                }
                .keyboardShortcut("o")
                .disabled(model.isSending)

                Button("Add Link…") {
                    model.isLinkPromptPresented = true
                }
                .keyboardShortcut("l")
                .disabled(model.isSending)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// "Check for Updates…" in the app menu, disabled while Sparkle is already checking.
private struct CheckForUpdatesButton: View {
    @State private var checker: UpdateChecker

    init(updater: SPUUpdater) {
        _checker = State(initialValue: UpdateChecker(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            checker.updater.checkForUpdates()
        }
        .disabled(!checker.canCheckForUpdates)
    }
}

@MainActor
@Observable
private final class UpdateChecker {
    let updater: SPUUpdater
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        self.updater = updater
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in
                self?.canCheckForUpdates = canCheck
            }
        }
    }
}
