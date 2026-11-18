import Foundation
import PS4LinuxCore

@main
enum InstallGuardCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let repo: URL
        if let root = args.first {
            repo = URL(fileURLWithPath: root, isDirectory: true)
        } else {
            repo = RepoPaths.repoRoot(fromFile: #filePath)
        }
        let asset = repo.appendingPathComponent("downloads/ps4-linux-baikal", isDirectory: true)
        let overlay = asset.appendingPathComponent("overlays/bin/install-HDD.sh")
        let initramfs = asset.appendingPathComponent("initramfs.cpio.gz")
        let arch = asset.appendingPathComponent("psxitarch.tar.xz")
        let bz = asset.appendingPathComponent("bzImage")

        let archBytes = (try? arch.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let bzBytes = (try? bz.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        let errors = InstallHddScriptGuard.validateInstallBundle(
            overlay: overlay,
            initramfs: initramfs,
            archBytes: archBytes,
            archMinBytes: 1_500_000_000,
            bzImageBytes: bzBytes,
            bzImageExpectedBytes: 9_872_896
        )
        if errors.isEmpty {
            print("InstallHddScriptGuard: OK (rev \(InstallHddScriptGuard.scriptRevision))")
            exit(0)
        }
        fputs("InstallHddScriptGuard FAILED:\n", stderr)
        for e in errors { fputs("  - \(e)\n", stderr) }
        fputs("Refuse to sync until overlay/initramfs/bzImage/arch are fixed.\n", stderr)
        exit(1)
    }
}