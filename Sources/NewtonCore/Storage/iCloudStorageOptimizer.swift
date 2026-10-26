import Foundation

public struct GhostFolderItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let totalSizeBytes: Int64
    public let localSizeBytes: Int64

    public init(name: String, path: String, totalSizeBytes: Int64, localSizeBytes: Int64) {
        self.id = path
        self.name = name
        self.path = path
        self.totalSizeBytes = totalSizeBytes
        self.localSizeBytes = localSizeBytes
    }

    public var ghostRatio: Double {
        guard totalSizeBytes > 0 else { return 0.0 }
        let offloaded = max(0, totalSizeBytes - localSizeBytes)
        return min(1.0, max(0.0, Double(offloaded) / Double(totalSizeBytes)))
    }

    public var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    public var localFormatted: String {
        ByteCountFormatter.string(fromByteCount: localSizeBytes, countStyle: .file)
    }

    public var offloadedFormatted: String {
        let offloaded = max(0, totalSizeBytes - localSizeBytes)
        return ByteCountFormatter.string(fromByteCount: offloaded, countStyle: .file)
    }
}

/// On-device iCloud storage and dataless ghost file optimizer for Newton.
public enum iCloudStorageOptimizer: Sendable {

    /// Measures logical vs physical storage usage for an iCloud or local directory.
    public static func getFolderStorageBreakdown(_ url: URL) -> (total: Int64, local: Int64) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .ubiquitousItemDownloadingStatusKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        var totalSize: Int64 = 0
        var localSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .ubiquitousItemDownloadingStatusKey, .isRegularFileKey]),
                  res.isRegularFile == true else {
                continue
            }
            let logical = Int64(res.fileSize ?? 0)
            totalSize += logical

            // Dataless evicted files consume 0 local physical bytes
            if res.ubiquitousItemDownloadingStatus == .notDownloaded {
                continue
            }

            localSize += Int64(res.totalFileAllocatedSize ?? 0)
        }

        return (totalSize, localSize)
    }

    /// Requests macOS to purge local cached copy and retain as dataless cloud ghost.
    public static func evictItem(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        // If already not downloaded, skip
        if let res = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           res.ubiquitousItemDownloadingStatus == .notDownloaded {
            return false
        }

        do {
            try fm.evictUbiquitousItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// Scans key workspace and cloud targets for local vs ghost ratios.
    public static func scanGhostFolders(customPaths: [String]? = nil) -> [GhostFolderItem] {
        let home = NSHomeDirectory()
        let cloudDocs = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"

        let defaultTargets: [(name: String, path: String)] = [
            ("iCloud Drive Root", cloudDocs),
            ("iCloud Documents", "\(cloudDocs)/Documents"),
            ("iCloud Archive", "\(cloudDocs)/Archive"),
            ("Local Repositories", "\(home)/local/repos"),
            ("Projects", "\(home)/Projects"),
            ("Downloads", "\(home)/Downloads")
        ]

        var items: [GhostFolderItem] = []
        let fm = FileManager.default

        for target in defaultTargets {
            if fm.fileExists(atPath: target.path) {
                let (total, local) = getFolderStorageBreakdown(URL(fileURLWithPath: target.path))
                if total > 0 {
                    items.append(GhostFolderItem(
                        name: target.name,
                        path: target.path,
                        totalSizeBytes: total,
                        localSizeBytes: local
                    ))
                }
            }
        }

        if let custom = customPaths {
            for path in custom {
                if fm.fileExists(atPath: path) && !items.contains(where: { $0.path == path }) {
                    let (total, local) = getFolderStorageBreakdown(URL(fileURLWithPath: path))
                    let name = (path as NSString).lastPathComponent
                    items.append(GhostFolderItem(
                        name: name,
                        path: path,
                        totalSizeBytes: total,
                        localSizeBytes: local
                    ))
                }
            }
        }

        return items
    }
}
