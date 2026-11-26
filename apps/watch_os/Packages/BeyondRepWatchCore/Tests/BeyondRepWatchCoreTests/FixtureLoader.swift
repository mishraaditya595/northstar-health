import Foundation

/// Finds the shared `contracts/` files by walking up from this source file.
enum FixtureLoader {
    enum LoaderError: Error { case contractsNotFound }

    static func repoRoot(from file: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        while dir.path != "/" {
            var isDir: ObjCBool = false
            let candidate = dir.appendingPathComponent("contracts").path
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw LoaderError.contractsNotFound
    }

    static func json(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repoRoot().appendingPathComponent(relativePath))
    }

    /// `.json` files directly inside `relativeDir`, sorted by name.
    static func files(in relativeDir: String) throws -> [URL] {
        let dir = try repoRoot().appendingPathComponent(relativeDir)
        return try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
