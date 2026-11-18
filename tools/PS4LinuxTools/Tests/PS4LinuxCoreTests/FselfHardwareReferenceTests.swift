import PS4LinuxCore
import XCTest

/// CE-41839 / CE-30008 guards using real FTP reference eboots and real create-fself output — not padded stub buffers.
final class FselfHardwareReferenceTests: XCTestCase {
    private var repo: URL { RepoPaths.repoRoot(fromFile: #filePath) }
    private var loader: URL { RepoPaths.loaderDir(repo: repo) }
    private var toolchain: URL { RepoPaths.toolchainDir(repo: repo) }

    func testApolloReferenceEbootIsValidWorkingHomebrew() throws {
        let apollo = FselfShipGate.referenceApolloEboot(repo: repo)
        try requireFile(apollo, "Apollo reference (tmp/console-evidence/ex-apollo)")
        XCTAssertTrue(FselfShipGate.validateWorkingReference(eboot: apollo).isEmpty)
        XCTAssertEqual(FselfShipGate.authInfoMarkerOffset(in: apollo), 1_716)
    }

    func testOneFamilyReferenceEbootIsValidWorkingHomebrew() throws {
        let one = FselfShipGate.referenceOneFamilyEboot(repo: repo)
        try requireFile(one, "OneFamily reference (tmp/console-evidence/ex-one)")
        XCTAssertTrue(FselfShipGate.validateWorkingReference(eboot: one).isEmpty)
        if let le70 = readU32LE(one, 0x70) {
            XCTAssertEqual(le70, PkgLayoutGuard.fselfOneFamilyField0x70Le)
        }
    }

    func testOneFamilyReferenceMatchesGoldHenShipProfile() throws {
        let one = FselfShipGate.referenceOneFamilyEboot(repo: repo)
        try requireFile(one, "OneFamily reference (tmp/console-evidence/ex-one)")
        let size = PkgLayoutGuard.fileSize(one)
        XCTAssertLessThanOrEqual(size, PkgLayoutGuard.fselfGoldHenShipMaxBytes)
        XCTAssertGreaterThanOrEqual(size, PkgLayoutGuard.fselfOneFamilyReferenceBytes - 50_000)
        let profileErrors = FselfShipGate.validateGoldHenOneFamilyShipProfile(eboot: one, loaderDir: one.deletingLastPathComponent())
        XCTAssertTrue(
            profileErrors.isEmpty,
            "OneFamily reference must match CSTP00003 ship profile:\n\(profileErrors.joined(separator: "\n"))"
        )
    }

    func testGoldHenShipProfileRejectsTenEntryCreateFselfOutput() throws {
        let elf = loader.appendingPathComponent("build/eboot.elf")
        try requireFile(elf, "build/eboot.elf (make all)")
        guard PkgLayoutGuard.fileSize(elf) > 500_000 else {
            throw XCTSkip("build/eboot.elf too small — link stage ≥12 to produce 10-entry create-fself sample")
        }
        let macos = toolchain.appendingPathComponent("bin/macos/create-fself-macos")
        try requireFile(macos, "create-fself-macos")

        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("eboot-ten-entry.bin")
        let auth = try authInfoHexFromMakefile()

        XCTAssertEqual(
            runTool(
                macos.path,
                [
                    "-in=\(elf.path)",
                    "-out=\(work.appendingPathComponent("eboot.oelf").path)",
                    "--eboot", out.path,
                    "--paid", "0x3800000000000011",
                    "--authinfo=\(auth)",
                ]
            ),
            0
        )
        guard readU32LE(out, 0x18) == PkgLayoutGuard.fselfTenEntryProgramFlagsLe else {
            throw XCTSkip("create-fself emitted 8-entry for this link — need stage 2/3 ELF for 10-entry regression")
        }
        try "macos/create-fself-macos".write(
            to: work.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile),
            atomically: true,
            encoding: .utf8
        )
        let profileErrors = FselfShipGate.validateGoldHenOneFamilyShipProfile(eboot: out, loaderDir: work)
        XCTAssertFalse(profileErrors.isEmpty)
        XCTAssertTrue(profileErrors.joined().contains("10-entry") || profileErrors.joined().contains("950"))
    }

    private func readU32LE(_ url: URL, _ offset: UInt64) -> UInt32? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        try? h.seek(toOffset: offset)
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return nil }
        return UInt32(d[0]) | (UInt32(d[1]) << 8) | (UInt32(d[2]) << 16) | (UInt32(d[3]) << 24)
    }

    func testBuiltLoaderEbootPassesFullShipGateWhenPresent() throws {
        let eboot = loader.appendingPathComponent("eboot.bin")
        let stamp = loader.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile)
        guard FileManager.default.fileExists(atPath: eboot.path) else {
            throw XCTSkip("Run swift tools/ps4-linux-launcher-build.swift first")
        }
        guard FileManager.default.fileExists(atPath: stamp.path) else {
            XCTFail("Built tree missing .ps4-linux-fself-method — eboot was not produced by ps4-linux-fself.sh")
            return
        }
        let errors = FselfShipGate.validate(eboot: eboot, loaderDir: loader, options: .ship)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        let profileErrors = FselfShipGate.validateGoldHenOneFamilyShipProfile(eboot: eboot, loaderDir: loader)
        XCTAssertTrue(profileErrors.isEmpty, profileErrors.joined(separator: "\n"))
    }

    func testCreateFselfMacosUnpatchedPassesShipGateForUnifiedLink() throws {
        let elf = loader.appendingPathComponent("build/eboot.elf")
        try requireFile(elf, "build/eboot.elf (make all)")
        guard PkgLayoutGuard.fileSize(elf) > 500_000 else {
            throw XCTSkip("build/eboot.elf too small — link stage ≥12 to produce 10-entry create-fself sample")
        }
        let macos = toolchain.appendingPathComponent("bin/macos/create-fself-macos")
        try requireFile(macos, "create-fself-macos")

        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("eboot-unpatched.bin")
        let auth = try authInfoHexFromMakefile()

        let status = runTool(
            macos.path,
            [
                "-in=\(elf.path)",
                "-out=\(work.appendingPathComponent("eboot.oelf").path)",
                "--eboot", out.path,
                "--paid", "0x3800000000000011",
                "--authinfo=\(auth)",
            ]
        )
        XCTAssertEqual(status, 0)
        guard readU32LE(out, 0x18) == PkgLayoutGuard.fselfTenEntryProgramFlagsLe else {
            throw XCTSkip("create-fself emitted 8-entry for this link — need stage 2/3 ELF for 10-entry regression")
        }
        try "macos/create-fself-macos".write(
            to: work.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile),
            atomically: true,
            encoding: .utf8
        )
        let errors = FselfShipGate.validate(eboot: out, loaderDir: work, options: .ship)
        XCTAssertFalse(errors.isEmpty, "10-entry / large create-fself must fail GoldHEN ship gate")
        XCTAssertTrue(errors.joined().contains("10-entry") || errors.joined().contains("950") || errors.joined().contains("0x80"))
    }

    func testApolloPatchProfileCorruptsTenEntrySelfHeader() throws {
        let elf = loader.appendingPathComponent("build/eboot.elf")
        try requireFile(elf, "build/eboot.elf")
        guard PkgLayoutGuard.fileSize(elf) > 500_000 else {
            throw XCTSkip("build/eboot.elf too small for 10-entry Apollo @0x0C patch test")
        }
        let macos = toolchain.appendingPathComponent("bin/macos/create-fself-macos")
        try requireFile(macos, "create-fself-macos")

        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("eboot.bin")
        let auth = try authInfoHexFromMakefile()

        XCTAssertEqual(
            runTool(
                macos.path,
                [
                    "-in=\(elf.path)",
                    "-out=\(work.appendingPathComponent("eboot.oelf").path)",
                    "--eboot", out.path,
                    "--paid", "0x3800000000000011",
                    "--authinfo=\(auth)",
                ]
            ),
            0
        )
        guard readU32LE(out, 0x18) == PkgLayoutGuard.fselfTenEntryProgramFlagsLe else {
            throw XCTSkip("create-fself emitted 8-entry for this link — need stage 2/3 ELF for 10-entry patch test")
        }
        let patch = repo.appendingPathComponent("tools/ps4-linux-patch-fself-header.py")
        var env = ProcessInfo.processInfo.environment
        env["PS4LINUX_FSELF_PATCH_PROFILE"] = "minimal"
        XCTAssertEqual(runTool("/usr/bin/python3", [patch.path, out.path], environment: env), 0)
        let errors = PkgLayoutGuard.validateFselfHeader(bytes: try Data(contentsOf: out))
        XCTAssertTrue(errors.contains { $0.contains("0x3D0") || $0.contains("Apollo") })
    }

    func testPythonMakeFselfOutputFailsShipGate() throws {
        let elf = loader.appendingPathComponent("build/eboot.elf")
        let py = repo.appendingPathComponent("tools/ps4-linux-make-fself.py")
        try requireFile(elf, "build/eboot.elf")
        try requireFile(py, "ps4-linux-make-fself.py")

        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("eboot-py.bin")
        let auth = try authInfoHexFromMakefile()

        let status = runTool(
            "/usr/bin/python3",
            [py.path, elf.path, out.path, "--paid", "0x3800000000000011", "--auth-info=\(auth)"]
        )
        XCTAssertEqual(status, 0)
        let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        XCTAssertLessThan(size, 1_580_000, "py fake should stay below create-fself unified floor")

        try PkgLayoutGuard.forbiddenFselfMethods.first!.write(
            to: work.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile),
            atomically: true,
            encoding: .utf8
        )
        let errors = FselfShipGate.validate(eboot: out, loaderDir: work, options: .ship)
        XCTAssertFalse(errors.isEmpty, "py fake SELF must fail ship gate")
        XCTAssertTrue(
            errors.contains { $0.contains("authinfo") || $0.contains("1716") || $0.contains("1_800") || $0.contains("1_510") || $0.contains("1510") },
            errors.joined(separator: "\n")
        )
        XCTAssertEqual(FselfShipGate.authInfoMarkerOffset(in: out), 1_716)
    }

    func testUnpatchedCreateFselfScriptMatchesShipGateProfile() throws {
        let elf = loader.appendingPathComponent("build/eboot.elf")
        try requireFile(elf, "build/eboot.elf")
        let fselfSh = repo.appendingPathComponent("tools/ps4-linux-fself.sh")
        try requireFile(fselfSh, "ps4-linux-fself.sh")

        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("eboot.bin")
        let auth = try authInfoHexFromMakefile()

        var env = ProcessInfo.processInfo.environment
        env["OO_PS4_TOOLCHAIN"] = toolchain.path
        env["PS4LINUX_FSELF_PATCH_PROFILE"] = "none"
        env["PS4LINUX_FSELF_PTYPE"] = "fake"
        let status = runTool(
            "/bin/bash",
            [fselfSh.path,
             "-in=\(elf.path)",
             "-out=\(work.appendingPathComponent("eboot.oelf").path)",
             "--eboot", out.path,
             "--paid", "0x3800000000000011",
             "--authinfo=\(auth)"],
            environment: env,
            workingDirectory: loader.path
        )
        XCTAssertEqual(status, 0, "ps4-linux-fself.sh failed")
        if PkgLayoutGuard.fileSize(out) <= PkgLayoutGuard.splitChainMaxBytes {
            FileManager.default.createFile(
                atPath: work.appendingPathComponent(PkgLayoutGuard.thinEbootStampFile).path,
                contents: Data(),
                attributes: nil
            )
        }
        let errors = FselfShipGate.validate(eboot: out, loaderDir: work, options: .ship)
        let outSize = PkgLayoutGuard.fileSize(out)
        if outSize > PkgLayoutGuard.fselfGoldHenShipMaxBytes {
            XCTAssertFalse(errors.isEmpty, "Large FSELF must fail GoldHEN OneFamily ship gate")
        } else {
            XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        }
    }

    func testCE30008InstalledPkgSizeFromEvidence() throws {
        let manifest = repo.appendingPathComponent("tmp/console-evidence/CE-41839-ROOT-CAUSE.md")
        try requireFile(manifest, "CE-41839-ROOT-CAUSE.md")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        XCTAssertTrue(text.contains("950") || text.contains("OneFamily"))
        XCTAssertTrue(text.contains("0x04700440") || text.contains("0x440") || text.contains("0x3D0"))
        XCTAssertTrue(text.contains("HeaderSize"))
    }

    // MARK: - Helpers

    private func requireFile(_ url: URL, _ label: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing \(label) at \(url.path)")
        }
    }

    private func authInfoHexFromMakefile() throws -> String {
        let mk = try String(contentsOf: loader.appendingPathComponent("Makefile"), encoding: .utf8)
        guard let line = mk.split(separator: "\n").first(where: { $0.contains("AUTHINFO") && $0.contains(":=") }) else {
            XCTFail("Makefile AUTHINFO not found")
            return ""
        }
        let parts = line.split(separator: ":=")
        return parts.last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    @discardableResult
    private func runTool(
        _ launch: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launch)
        task.arguments = arguments
        if let environment { task.environment = environment }
        if let workingDirectory { task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory) }
        let err = Pipe()
        task.standardError = err
        task.standardOutput = err
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                fputs("tool failed (\(launch)): \(msg)\n", stderr)
            }
            return task.terminationStatus
        } catch {
            XCTFail("\(launch): \(error)")
            return -1
        }
    }
}
