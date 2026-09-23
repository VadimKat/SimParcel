import SwiftUI

@main
struct SimulatorMediaDropApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Simulator Media Drop", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 640, height: 580)
        .windowResizability(.contentMinSize)
        .commands {
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
