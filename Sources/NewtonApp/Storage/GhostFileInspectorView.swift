import SwiftUI
import NewtonCore
import NewtonWorkspace

public struct GhostFileInspectorView: View {
    @Bindable var model: WorkspaceModel
    @State private var folders: [GhostFolderItem] = []
    @State private var isScanning = false
    @State private var statusMessage: String?
    @State private var turboCandidates: [DeveloperProjectCandidate] = []
    @State private var isRunningTurboSweep = false
    @State private var turboSweepMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    private var totalCloudBytes: Int64 {
        folders.reduce(0) { $0 + $1.totalSizeBytes }
    }

    private var totalLocalBytes: Int64 {
        folders.reduce(0) { $0 + $1.localSizeBytes }
    }

    private var overallGhostRatio: Double {
        guard totalCloudBytes > 0 else { return 0.0 }
        let offloaded = max(0, totalCloudBytes - totalLocalBytes)
        return Double(offloaded) / Double(totalCloudBytes)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud Ghost & Storage Optimizer").font(.largeTitle.bold())
                        Text("Inspect dataless cloud ghost ratios, evict local caches, and execute Reviewed Developer Cleanup.").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Scan Storage", systemImage: "arrow.clockwise") {
                        scanStorage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning || isRunningTurboSweep)
                }

                // Overall Ratio Overview Banner
                if !folders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("OVERALL STORAGE RATIO")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text("\(Int(overallGhostRatio * 100))% Cloud Ghosted")
                                    .font(.title2.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(ByteCountFormatter.string(fromByteCount: totalLocalBytes, countStyle: .file)) Physical")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Text("\(ByteCountFormatter.string(fromByteCount: totalCloudBytes, countStyle: .file)) Logical")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Progress Bar
                        GeometryReader { geo in
                            let totalW = geo.size.width
                            let ghostW = max(0, min(totalW, totalW * overallGhostRatio))

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.2))
                                    .frame(width: totalW, height: 10)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green)
                                    .frame(width: ghostW, height: 10)
                            }
                        }
                        .frame(height: 10)

                        HStack {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Logical minus allocated (includes sparse/compressed data)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(Color.accentColor.opacity(0.5)).frame(width: 8, height: 8)
                                Text("Local Physical Disk").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .panelCard(cornerRadius: 14)
                }

                // Reviewed Developer Cleanup Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reviewed Developer Cleanup")
                                .font(.headline)
                            Text("Scans local developer directories for expendable bloat (node_modules, .venv, target, .build) for review. Deletion requires selecting and confirming each directory in Utilities & Clean.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            runTurboSweep()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text(isRunningTurboSweep ? "Sweeping…" : "Scan Cleanup")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isRunningTurboSweep)
                    }

                    if let turboMsg = turboSweepMessage {
                        Text(turboMsg)
                            .font(.caption.bold())
                            .foregroundStyle(Color.orange)
                    }

                    if !turboCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DETECTED DISPOSABLE BLOAT (\(turboCandidates.count) TARGETS)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            ForEach(turboCandidates.prefix(6)) { cand in
                                HStack {
                                    Text(cand.projectName).font(.system(size: 11, weight: .bold))
                                    Text(cand.bloatType).font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
                                    Spacer()
                                    Text(cand.sizeFormatted).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(10)
                        .background(PanelSurface.controlFill(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .panelCard(cornerRadius: 14)

                // Status message if any
                if let status = statusMessage {
                    Text(status)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }

                // Folders Breakdown
                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Querying iCloud metadata and computing physical vs logical storage…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                } else if folders.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                        Text("No iCloud or tracked repository paths indexed yet")
                            .font(.headline)
                        Text("Click Scan Storage to measure dataless ghost ratios.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .panelCard(cornerRadius: 14)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TRACKED DIRECTORIES (\(folders.count))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    }
                    .panelCard(cornerRadius: 14)
                }
            }
            .padding(28)
        }
        .onAppear {
            scanStorage()
        }
    }

    private func folderRow(_ item: GhostFolderItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 13, weight: .bold))
                    Text(item.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.localFormatted) physical").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text("\(item.totalFormatted) logical").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                }
            }

            // Ghost percentage bar
            GeometryReader { geo in
                let w = geo.size.width
                let ghostW = max(0, min(w, w * item.ghostRatio))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: w, height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: ghostW, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(item.ghostRatio * 100))% Ghost (\(item.offloadedFormatted) saved)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.green)

                Spacer()

                Button("Evict to Cloud") {
                    evictFolder(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Evicts local cached copy, leaving as a a cloud placeholder; outcome must be verified")
            }
        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func scanStorage() {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = iCloudStorageOptimizer.scanGhostFolders()
            DispatchQueue.main.async {
                self.folders = res
                self.isScanning = false
            }
        }
    }

    private func evictFolder(_ item: GhostFolderItem) {
        let success = iCloudStorageOptimizer.evictItem(atPath: item.path)
        statusMessage = success
            ? "Eviction requested for '\(item.name)'. macOS is reclaiming physical bytes."
            : "Eviction not confirmed; item may be unavailable or already dataless."

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            scanStorage()
        }
    }

    private func runTurboSweep() { model.perform(.scanCleanup) }
}
