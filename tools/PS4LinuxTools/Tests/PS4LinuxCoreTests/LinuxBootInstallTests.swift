import PS4LinuxCore
import XCTest

final class LinuxBootStackLogicTests: XCTestCase {
    func testValidateSizesReady() {
        let c = LinuxBootStackLogic.validateSizes(kernelBytes: 9_872_896, initramfsBytes: 4_086_408)
        XCTAssertTrue(c.readyForLaunch)
        XCTAssertTrue(c.kernelSizeOk)
        XCTAssertTrue(c.initramfsSizeOk)
    }

    func testValidateSizesMissingKernel() {
        let c = LinuxBootStackLogic.validateSizes(kernelBytes: nil, initramfsBytes: 4_000_000)
        XCTAssertFalse(c.readyForLaunch)
        XCTAssertTrue(c.statusLines().joined().contains("missing"))
    }

    func testValidateSizesTinyKernel() {
        let c = LinuxBootStackLogic.validateSizes(kernelBytes: 4096, initramfsBytes: 4_000_000)
        XCTAssertFalse(c.readyForLaunch)
        XCTAssertFalse(c.kernelSizeOk)
    }
}

final class LinuxBootConfigLogicTests: XCTestCase {
    func testArchGbClampMinMaxDefault() {
        XCTAssertEqual(LinuxBootConfigLogic.clampArchGb(10), 50)
        XCTAssertEqual(LinuxBootConfigLogic.clampArchGb(50), 50)
        XCTAssertEqual(LinuxBootConfigLogic.clampArchGb(100), 100)
        XCTAssertEqual(LinuxBootConfigLogic.clampArchGb(999), 512)
        XCTAssertEqual(LinuxBootConfigLogic.archGbDefault, 100)
    }

    func testNormalizeSnapsVram() {
        var v = LinuxBootConfigLogic.Values(vramMb: 999, archGb: 40)
        LinuxBootConfigLogic.normalize(&v)
        XCTAssertEqual(v.archGb, 50)
        XCTAssertEqual(v.vramMb, 1024)

        var v2 = LinuxBootConfigLogic.Values(vramMb: 600, archGb: 100)
        LinuxBootConfigLogic.normalize(&v2)
        XCTAssertEqual(v2.vramMb, 512)
    }

    func testParseLiteJSONRoundTrip() {
        let json = """
        {
          "vram_mb": 1024,
          "arch_gb": 100,
          "verbose_boot": true,
          "payload": "pro_baikal_1gb",
          "install_target": "internal_hdd"
        }
        """
        guard let parsed = LinuxBootConfigLogic.parseLiteJSON(json) else {
            XCTFail("parse failed")
            return
        }
        XCTAssertEqual(parsed.vramMb, 1024)
        XCTAssertEqual(parsed.archGb, 100)
        XCTAssertTrue(parsed.verboseBoot)
        XCTAssertEqual(parsed.payload, "pro_baikal_1gb")
        let out = LinuxBootConfigLogic.serializeLiteJSON(parsed)
        guard let again = LinuxBootConfigLogic.parseLiteJSON(out) else {
            XCTFail("re-parse failed")
            return
        }
        XCTAssertEqual(again, parsed)
    }

    func testParseLiteJSONClampsArchGb() {
        let json = """
        { "vram_mb": 512, "arch_gb": 12, "verbose_boot": false }
        """
        let parsed = LinuxBootConfigLogic.parseLiteJSON(json)
        XCTAssertEqual(parsed?.archGb, 50)
    }

    func testSyncInstallGbDefaultAndClamp() {
        XCTAssertEqual(LinuxBootConfigLogic.syncInstallGbDefault(), 100)
        XCTAssertEqual(LinuxBootConfigLogic.syncInstallGbClamped(50), 50)
        XCTAssertEqual(LinuxBootConfigLogic.syncInstallGbClamped(30), 50)
        XCTAssertEqual(LinuxBootConfigLogic.syncInstallGbClamped(200), 200)
    }

    func testCppHeaderConstantsMatchSwift() throws {
        let repo = RepoPaths.repoRoot(fromFile: #filePath)
        let header = repo
            .appendingPathComponent("ps4-linux-launcher-app/linux-loader/include/LinuxBootConfig.h")
        let text = try String(contentsOf: header, encoding: .utf8)
        XCTAssertTrue(text.contains("kArchGbMin = 50"))
        XCTAssertTrue(text.contains("kArchGbDefault = 100"))
        XCTAssertTrue(text.contains("kArchGbMax = 512"))
    }
}

final class LinuxInstallDetectLogicTests: XCTestCase {
    private let oneGb: Int64 = 1024 * 1024 * 1024

    func testMissingArchImg() {
        let s = LinuxInstallDetectLogic.detect(inputs: LinuxInstallInputs())
        XCTAssertEqual(s.level, LinuxInstallLevel.none)
        XCTAssertTrue(s.summaryLine.contains("missing"))
    }

    func testTinyArchImgPartial() {
        let s = LinuxInstallDetectLogic.detect(inputs: LinuxInstallInputs(archImgBytes: 1024))
        XCTAssertEqual(s.level, LinuxInstallLevel.partial)
        XCTAssertTrue(s.summaryLine.contains("too small"))
    }

    func testReadyViaInstallMeta() {
        let meta = """
        distro=psxitarch
        arch_gb=100
        install_complete=1
        """
        let s = LinuxInstallDetectLogic.detect(
            inputs: LinuxInstallInputs(archImgBytes: Int64(300 * 1024 * 1024), installMeta: meta)
        )
        XCTAssertEqual(s.level, LinuxInstallLevel.ready)
        XCTAssertEqual(s.metaArchGb, 100)
        XCTAssertEqual(s.distro, "psxitarch")
        XCTAssertTrue(s.summaryLine.contains("100 GB"))
    }

    func testReadyViaInstallStatus() {
        let status = "2026-11-05T12:00:00 Step 3/3 done: extract finished"
        let s = LinuxInstallDetectLogic.detect(
            inputs: LinuxInstallInputs(archImgBytes: Int64(512 * 1024 * 1024), installStatus: status)
        )
        XCTAssertEqual(s.level, LinuxInstallLevel.ready)
    }

    func testReadyViaArchImgSizeHeuristic50Gb() {
        let bytes = 50 * oneGb
        let s = LinuxInstallDetectLogic.detect(inputs: LinuxInstallInputs(archImgBytes: bytes))
        XCTAssertEqual(s.level, LinuxInstallLevel.ready)
        XCTAssertEqual(s.archImgSizeGb, 50)
        XCTAssertTrue(s.summaryLine.contains("psxitarch"))
    }

    func testLargeArchWithoutMetaStillPartialIfUnder50GbNominal() {
        let bytes = Int64(512 * 1024 * 1024)
        let s = LinuxInstallDetectLogic.detect(inputs: LinuxInstallInputs(archImgBytes: bytes))
        XCTAssertEqual(s.level, LinuxInstallLevel.partial)
    }

    func testInstallStatusCompleteMarkers() {
        XCTAssertTrue(LinuxInstallDetectLogic.installStatusIndicatesComplete("Step 3/3 done"))
        XCTAssertTrue(LinuxInstallDetectLogic.installStatusIndicatesComplete("extract finished"))
        XCTAssertTrue(LinuxInstallDetectLogic.installStatusIndicatesComplete("switch_root /newroot"))
        XCTAssertFalse(LinuxInstallDetectLogic.installStatusIndicatesComplete("Step 1/3"))
    }

    func testReadMetaField() {
        let raw = "distro=psxitarch\narch_gb=50\ninstall_complete=1\n"
        XCTAssertEqual(LinuxInstallDetectLogic.readMetaField(raw, key: "arch_gb"), "50")
        XCTAssertEqual(LinuxInstallDetectLogic.readMetaField(raw, key: "install_complete"), "1")
        XCTAssertNil(LinuxInstallDetectLogic.readMetaField(raw, key: "missing"))
    }

    func testDetectAndWipeOnFilesystem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LinuxInstallPaths(
            archImg: root.appendingPathComponent("Arch.img"),
            installMeta: root.appendingPathComponent("installed.meta"),
            installStatus: root.appendingPathComponent("status.txt")
        )
        let archData = Data(repeating: 0, count: 300 * 1024 * 1024)
        try archData.write(to: paths.archImg)
        try "Step 3/3 done\n".write(to: paths.installStatus, atomically: true, encoding: .utf8)

        let before = LinuxInstallDetectLogic.detect(paths: paths)
        XCTAssertEqual(before.level, .ready)

        let wiped = try LinuxInstallDetectLogic.wipe(paths: paths)
        XCTAssertTrue(wiped)
        let after = LinuxInstallDetectLogic.detect(paths: paths)
        XCTAssertEqual(after.level, .none)
    }

    func testWipeNothingIsOk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LinuxInstallPaths(
            archImg: root.appendingPathComponent("Arch.img"),
            installMeta: root.appendingPathComponent("meta"),
            installStatus: root.appendingPathComponent("status")
        )
        let wiped = try LinuxInstallDetectLogic.wipe(paths: paths)
        XCTAssertFalse(wiped)
    }
}

final class LinuxMenuLogicTests: XCTestCase {
    func testMenuCountAndActionsWhenInstalled() {
        XCTAssertEqual(LinuxMenuLogic.mainMenuCount(installReady: true), 5)
        XCTAssertEqual(LinuxMenuLogic.action(installReady: true, index: 0), .primaryLaunch)
        XCTAssertEqual(LinuxMenuLogic.action(installReady: true, index: 1), .newInstallWipe)
        XCTAssertEqual(LinuxMenuLogic.action(installReady: true, index: 4), .refresh)
        XCTAssertNil(LinuxMenuLogic.action(installReady: true, index: 5))
    }

    func testMenuCountAndActionsWhenNotInstalled() {
        XCTAssertEqual(LinuxMenuLogic.mainMenuCount(installReady: false), 4)
        XCTAssertEqual(LinuxMenuLogic.action(installReady: false, index: 0), .primaryLaunch)
        XCTAssertEqual(LinuxMenuLogic.action(installReady: false, index: 1), .installGb)
        XCTAssertNil(LinuxMenuLogic.action(installReady: false, index: 4))
    }

    func testPrimaryTitlesAndWipePartial() {
        XCTAssertEqual(LinuxMenuLogic.primaryMenuTitle(level: LinuxInstallLevel.ready), "Boot installed Linux")
        XCTAssertEqual(LinuxMenuLogic.primaryMenuTitle(level: LinuxInstallLevel.none), "Install Linux on HDD")
        XCTAssertTrue(LinuxMenuLogic.primaryLaunchWipesArch(level: LinuxInstallLevel.partial))
        XCTAssertFalse(LinuxMenuLogic.primaryLaunchWipesArch(level: LinuxInstallLevel.ready))
        XCTAssertFalse(LinuxMenuLogic.primaryLaunchWipesArch(level: LinuxInstallLevel.none))
    }

    func testArchAndVramPresetsMatchApp() {
        XCTAssertEqual(LinuxMenuLogic.archPresetGigabytes(), [50, 75, 100, 125, 150, 200])
        XCTAssertEqual(LinuxMenuLogic.vramMegabytesOptions(), [512, 1024, 2048, 4096])
        XCTAssertEqual(LinuxMenuLogic.archPresetGigabytes()[2], LinuxBootConfigLogic.archGbDefault)
    }
}

final class KexecLoaderBinLogicTests: XCTestCase {
    func testRejectsElfMagic() {
        let elf = Data([0x7f, 0x45, 0x4c, 0x46, 0x00])
        XCTAssertTrue(KexecLoaderBinLogic.isElfMagic(elf))
        XCTAssertFalse(KexecLoaderBinLogic.isKexecLoaderBin(fileSize: 329_088, header: elf))
    }

    func testAcceptsKexecSizedBin() {
        let kexec = Data([0xe9, 0xb9, 0xd8, 0x04])
        XCTAssertTrue(KexecLoaderBinLogic.isKexecLoaderBin(fileSize: KexecLoaderBinLogic.referenceKexecSize, header: kexec))
    }

    func testRejectsTooSmallOrHuge() {
        let h = Data([0xe9, 0x00, 0x00, 0x00])
        XCTAssertFalse(KexecLoaderBinLogic.isKexecLoaderBin(fileSize: 100, header: h))
        XCTAssertFalse(KexecLoaderBinLogic.isKexecLoaderBin(fileSize: 3 * 1024 * 1024, header: h))
    }

    func testRealLoaderBinFromRepoIfPresent() throws {
        let repo = RepoPaths.repoRoot(fromFile: #filePath)
        let bin = repo.appendingPathComponent("downloads/ps4-linux-baikal/linux-1024mb.bin")
        guard FileManager.default.fileExists(atPath: bin.path) else {
            throw XCTSkip("linux-1024mb.bin not extracted locally")
        }
        let data = try Data(contentsOf: bin)
        let size = data.count
        let head = data.prefix(4)
        XCTAssertFalse(KexecLoaderBinLogic.isElfMagic(head))
        XCTAssertTrue(KexecLoaderBinLogic.isKexecLoaderBin(fileSize: size, header: head))
        XCTAssertEqual(size, KexecLoaderBinLogic.referenceKexecSize)
    }
}

final class InstallHddOverlayTests: XCTestCase {
    func testInstallHddScriptWritesMetaBlock() throws {
        let repo = RepoPaths.repoRoot(fromFile: #filePath)
        let script = repo.appendingPathComponent("downloads/ps4-linux-baikal/overlays/bin/install-HDD.sh")
        let errors = InstallHddScriptGuard.validateOverlay(at: script)
        XCTAssertEqual(errors, [], errors.joined(separator: "; "))
    }

    func testInstallHddScriptRejectsBrokenSwitchRootExample() {
        let broken = """
        exec switch_root /newroot /newroot/sbin/init
        ensure_sbin_init || exit 1
        """
        let errors = InstallHddScriptGuard.validateScriptContent(broken)
        XCTAssertFalse(errors.isEmpty)
    }

    func testInitSnippetRunsInstallWhenNoArchImg() throws {
        let repo = RepoPaths.repoRoot(fromFile: #filePath)
        let snippet = repo.appendingPathComponent("downloads/ps4-linux-baikal/overlays/init-auto-install.snippet")
        let text = try String(contentsOf: snippet, encoding: .utf8)
        XCTAssertTrue(text.contains("/ps4hdd/home/Arch.img"))
        XCTAssertTrue(text.contains("install-HDD.sh"))
    }
}
