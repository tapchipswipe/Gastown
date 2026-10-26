import SwiftUI
import NewtonCore
import NewtonWorkspace

public struct PortManagerView: View {
    @Bindable var model: WorkspaceModel
    @State private var ports: [PortEntry] = []
    @State private var searchQuery = ""
    @State private var isScanning = false
    @State private var statusMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    private var filteredPorts: [PortEntry] {
        guard !searchQuery.isEmpty else { return ports }
        let q = searchQuery.lowercased()
        return ports.filter {
            "\($0.port)".contains(q) ||
            $0.processName.lowercased().contains(q) ||
            "\($0.pid)".contains(q) ||
            $0.address.lowercased().contains(q)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Developer Port Manager").font(.largeTitle.bold())
                        Text("Inspect active localhost listening sockets and safely terminate hung dev servers.").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Scan Ports", systemImage: "arrow.clockwise") {
                        scanPorts()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning)
                }

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "network").foregroundStyle(.secondary)
                    TextField("Filter by port (3000), process (node, python), or PID...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let status = statusMessage {
                    Text(status)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }

                // Port Entries List
                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning Darwin process table for TCP listening sockets…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                } else if filteredPorts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.green.opacity(0.8))
                        Text(searchQuery.isEmpty ? "No active listening ports detected" : "No ports matching '\(searchQuery)'")
                            .font(.headline)
                        Text("Click Scan Ports to query local network sockets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .panelCard(cornerRadius: 14)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("ACTIVE LISTENING PORTS (\(filteredPorts.count))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        ForEach(filteredPorts) { entry in
                            portRow(entry)
                        }
                    }
                    .panelCard(cornerRadius: 14)
                }
            }
            .padding(28)
        }
        .onAppear {
            scanPorts()
        }
    }

    private func portRow(_ entry: PortEntry) -> some View {
        HStack(spacing: 14) {
            // Port Pill
            Text(":\(entry.port)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))

            // Process Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.processName)
                        .font(.system(size: 12, weight: .bold))
                    Text("PID \(entry.pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.user) · \(entry.address)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Safe Terminate Button
            Button("Kill", role: .destructive) {
                killProcess(entry, force: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Force Kill Button
            Button("Force (-9)", role: .destructive) {
                killProcess(entry, force: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func scanPorts() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            defer { isScanning = false }
            do { ports = try await PortManagerEngine.scanActivePorts() }
            catch { statusMessage = error.localizedDescription }
        }
    }

    private func killProcess(_ entry: PortEntry, force: Bool) {
        let alert = NSAlert()
        alert.messageText = "\(force ? "Force terminate" : "Terminate") \(entry.processName)?"
        alert.informativeText = "PID \(entry.pid), port :\(entry.port). Unsaved work may be lost."
        alert.addButton(withTitle: "Terminate"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let exited = try await PortManagerEngine.terminatePort(entry, force: force)
                statusMessage = exited ? "Original process exit confirmed" : "Signal sent; process exit not confirmed"
            } catch { statusMessage = error.localizedDescription }
            scanPorts()
        }
    }
}
