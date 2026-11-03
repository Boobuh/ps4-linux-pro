import Foundation

public enum RepoPaths {
    public static func repoRoot(fromFile file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<10 {
            let marker = url.appendingPathComponent("ps4-linux-launcher-app/linux-loader/Makefile")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
            if url.pathComponents.count <= 1 {
                break
            }
            url.deleteLastPathComponent()
        }
        fatalError("Could not locate repo root (ps4-linux-launcher-app/linux-loader/Makefile)")
    }

    public static func loaderDir(repo: URL) -> URL {
        repo.appendingPathComponent("ps4-linux-launcher-app/linux-loader", isDirectory: true)
    }

    public static func toolchainDir(repo: URL) -> URL {
        repo.appendingPathComponent("vendor/OpenOrbis/PS4Toolchain", isDirectory: true)
    }

    public static func pkgTool(repo: URL) -> URL {
        toolchainDir(repo: repo).appendingPathComponent("bin/macos/PkgTool.Core")
    }
}
