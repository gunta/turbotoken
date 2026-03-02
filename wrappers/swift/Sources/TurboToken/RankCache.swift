import Foundation

/// Cache for downloaded rank files.
public enum RankCache {
    /// Returns the cache directory for rank files.
    public static func cacheDirectory() -> URL {
        let base: URL
        if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"] {
            base = URL(fileURLWithPath: xdgCache)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        }
        return base.appendingPathComponent("turbotoken")
    }

    /// Ensure a rank file is downloaded and cached. Returns the file URL.
    public static func ensureRankFile(name: String) async throws -> URL {
        let spec = try Registry.getEncodingSpec(name: name)
        let cacheDir = cacheDirectory()
        let fileName = spec.rankFileURL.lastPathComponent
        let localPath = cacheDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let (data, response) = try await URLSession.shared.data(from: spec.rankFileURL)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw TurboTokenError.downloadFailed(
                "Failed to download rank file for '\(name)': HTTP \(httpResponse.statusCode)"
            )
        }
        try data.write(to: localPath, options: .atomic)
        return localPath
    }

    /// Read a rank file's contents, downloading if necessary.
    public static func readRankFile(name: String) async throws -> Data {
        let fileURL = try await ensureRankFile(name: name)
        return try Data(contentsOf: fileURL)
    }
}
