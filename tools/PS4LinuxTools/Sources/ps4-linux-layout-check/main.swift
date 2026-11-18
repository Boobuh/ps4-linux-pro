import Foundation
import PS4LinuxCore

@main
enum LayoutCheck {
    static func main() {
        let loaderPath = CommandLine.arguments.dropFirst().first
            ?? FileManager.default.currentDirectoryPath
        let loaderDir = URL(fileURLWithPath: loaderPath, isDirectory: true)
        let errors = PkgLayoutGuard.validateBuildTree(loaderDir: loaderDir)
        if errors.isEmpty {
            print("PkgLayoutGuard: OK (\(loaderDir.path))")
            exit(0)
        }
        fputs("PkgLayoutGuard FAILED (\(loaderDir.path)):\n", stderr)
        for e in errors { fputs("  - \(e)\n", stderr) }
        fputs("See docs/PS4-LINUX-PKG-POSTMORTEM.md\n", stderr)
        exit(1)
    }
}
