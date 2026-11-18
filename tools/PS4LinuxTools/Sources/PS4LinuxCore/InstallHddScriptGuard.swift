import Foundation

/// Blocks broken internal-HDD install scripts (wrong `switch_root`, tar without checks).
/// See docs/PS4-LINUX-BAIKAL-ASSETS.md and overlay `install-HDD.sh`.
public enum InstallHddScriptGuard {
    public static let scriptRevision = 4

  public static let forbiddenPatterns = [
        "switch_root /newroot /newroot/sbin/init",
        "switch_root /newroot /newroot",
        "/newroot/sbin/init &",
    ]

    public static let requiredPatterns: [(String, String)] = [
        ("INSTALL_HDD_SCRIPT_REV=\(scriptRevision)", "revision constant"),
        ("fail_safe_switch_root", "fail-safe pivot wrapper"),
        ("exec switch_root /newroot \"$init_rel\"", "BusyBox-correct switch_root via wrapper"),
        ("ensure_sbin_init", "sbin/init symlink helper"),
        ("ensure_sbin_init || exit 1", "init guard"),
        ("ERROR: tar extract failed", "tar failure path"),
        ("Step 3/3 done: extract finished", "success marker"),
    ]

    public static func validateScriptContent(_ text: String) -> [String] {
        var errors: [String] = []
        for forbidden in forbiddenPatterns {
            if text.contains(forbidden) {
                errors.append("forbidden pattern: `\(forbidden)`")
            }
        }
        for (needle, label) in requiredPatterns {
            if !text.contains(needle) {
                errors.append("missing \(label): `\(needle)`")
            }
        }
        guard let ensure = text.range(of: "ensure_sbin_init || exit 1"),
            let step3 = text.range(of: "ui_log \"Step 3/3 done: extract finished\"")
        else {
            if errors.isEmpty {
                errors.append("could not verify Step 3 runs after ensure_sbin_init")
            }
            return errors
        }
        if ensure.lowerBound >= step3.lowerBound {
            errors.append("Step 3 must be logged only after ensure_sbin_init (order)")
        }
        if text.contains("ps4-linux-installed.meta"),
            let meta = text.range(of: "ps4-linux-installed.meta"),
            meta.lowerBound < step3.lowerBound
        {
            errors.append("install meta must be written only after Step 3 log")
        }
        return errors
    }

    public static func validateOverlay(at url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["unreadable overlay: \(url.path)"]
        }
        return validateScriptContent(text)
    }

    private static func extractCpioMember(fromInitramfs url: URL, memberPath: String) -> String? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps4-initramfs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [
            "-c",
            "gunzip -c '\(url.path)' | (cd '\(tmp.path)' && cpio -idm '\(memberPath)' 2>/dev/null)",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let file = tmp.appendingPathComponent(memberPath)
        return try? String(contentsOf: file, encoding: .utf8)
    }

    public static func extractInstallScript(fromInitramfs url: URL) -> String? {
        extractCpioMember(fromInitramfs: url, memberPath: "bin/install-HDD.sh")
    }

    public static func validateBuiltInitramfs(at url: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ["initramfs missing: \(url.path)"]
        }
        guard let script = extractInstallScript(fromInitramfs: url), !script.isEmpty else {
            return ["bin/install-HDD.sh missing inside initramfs"]
        }
        var errors = validateScriptContent(script)
        let rev = extractCpioMember(fromInitramfs: url, memberPath: "etc/ps4-linux-install-hdd.rev")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rev != "\(scriptRevision)" {
            errors.append("initramfs stamp etc/ps4-linux-install-hdd.rev = \"\(rev)\" expected \"\(scriptRevision)\"")
        }
        return errors
    }

    public static func validateInstallBundle(
        overlay: URL,
        initramfs: URL,
        archBytes: Int64,
        archMinBytes: Int64,
        bzImageBytes: Int64,
        bzImageExpectedBytes: Int64
    ) -> [String] {
        var errors = validateOverlay(at: overlay)
        errors.append(contentsOf: validateBuiltInitramfs(at: initramfs))
        if archBytes < archMinBytes {
            errors.append("arch.tar.xz too small (\(archBytes) < \(archMinBytes))")
        }
        if bzImageBytes != bzImageExpectedBytes {
            errors.append("bzImage size \(bzImageBytes) != expected \(bzImageExpectedBytes)")
        }
        return errors
    }
}