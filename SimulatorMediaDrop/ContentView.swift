import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            SimulatorBar()
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            queue
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            FooterBar()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .frame(minWidth: 540, minHeight: 460)
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isImporting else {
                return false
            }

            Task {
                await model.add(urls)
            }
            return true
        } isTargeted: { isTargeted in
            withAnimation(.easeOut(duration: 0.15)) {
                isDropTargeted = isTargeted && !model.isImporting
            }
        }
        .fileImporter(
            isPresented: $model.isFilePickerPresented,
            allowedContentTypes: [.image, .movie, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await model.add(urls)
                }
            case .failure(let error):
                model.reportFilePickerError(error)
            }
        }
        .task {
            await model.refreshDevices()
        }
    }

    @ViewBuilder
    private var queue: some View {
        ZStack {
            if model.items.isEmpty {
                EmptyDropZone(isTargeted: isDropTargeted)
                    .padding(20)
                    .transition(.opacity)
            } else {
                MediaGrid()
                    .transition(.opacity)
                    .overlay {
                        if isDropTargeted {
                            DropHighlight()
                                .padding(8)
                                .transition(.opacity)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.items.isEmpty)
    }
}

// MARK: - Simulator

private struct SimulatorBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 12) {
            Image(systemName: model.selectedDevice?.symbolName ?? "iphone")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if model.devices.isEmpty {
                    Text(model.isRefreshing ? "Looking for simulators…" : "No simulators")
                        .font(.headline)
                    Text("Simulators with an installed iOS runtime appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Simulator", selection: $model.selectedDeviceID) {
                        ForEach(model.runtimeGroups) { group in
                            Section(group.runtime.name) {
                                ForEach(group.devices) { device in
                                    Text(device.name)
                                        .tag(device.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(model.isBusy)

                    if let device = model.selectedDevice {
                        DeviceStateLabel(device: device)
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                Task {
                    await model.showSelectedDevice()
                }
            } label: {
                Label("Show Simulator", systemImage: "arrow.up.forward.app")
                    .labelStyle(.titleAndIcon)
            }
            .help("Start this simulator and bring the Simulator app to the front")
            .disabled(model.selectedDevice == nil || model.isBusy)

            Button {
                Task {
                    await model.refreshDevices()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload the list of simulators")
            .keyboardShortcut("r")
            .disabled(model.isBusy)
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }
}

private struct DeviceStateLabel: View {
    let device: SimulatorDevice

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(device.isBooted ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(device.isBooted ? "\(device.runtime.name) · Running" : "\(device.runtime.name) · Starts automatically on import")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Drop zone

private struct EmptyDropZone: View {
    @Environment(AppModel.self) private var model
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "photo.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(isTargeted ? "Release to add" : "Drop photos and videos here")
                    .font(.title3.weight(.semibold))

                Text("Folders and Live Photos are supported")
                    .foregroundStyle(.secondary)
            }

            Button("Choose Files…") {
                model.isFilePickerPresented = true
            }
            .controlSize(.large)
            .disabled(model.isImporting)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.quaternary.opacity(0.35)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [8, 6])
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone for photos and videos")
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.tint.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
            }
            .overlay {
                Label("Release to add", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            StatusView()
                .frame(maxWidth: .infinity, alignment: .leading)

            if !model.items.isEmpty {
                Button("Add More…") {
                    model.isFilePickerPresented = true
                }
                .disabled(model.isImporting)
            }

            Button {
                Task {
                    await model.importAll()
                }
            } label: {
                Text(importTitle)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canImport)
        }
        .controlSize(.large)
    }

    private var importTitle: String {
        let count = model.items.count
        return count > 1 ? "Add \(count) to Photos" : "Add to Photos"
    }
}

private struct StatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isImporting && model.importTotal > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    statusText
                    ProgressView(value: Double(model.importedCount), total: Double(model.importTotal))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                }
            } else {
                statusText
            }
        }
        .lineLimit(2)
        .animation(.default, value: model.status)
    }

    @ViewBuilder
    private var statusText: some View {
        switch model.status {
        case .idle:
            Text(idleMessage)
                .foregroundStyle(.secondary)
        case .info(let message, let detail):
            Label(message, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .help(detail ?? message)
        case .working(let message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
            }
            .foregroundStyle(.secondary)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message, let detail):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(detail ?? message)
        }
    }

    private var idleMessage: String {
        let count = model.items.count
        switch count {
        case 0:
            return "Add photos or videos to import."
        case 1:
            return "1 item ready"
        default:
            return "\(count) items ready"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
