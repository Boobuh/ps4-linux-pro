import PS4LinuxCore
import XCTest

final class PkgVersioningTests: XCTestCase {
    func testSonyAppVerBuild70() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 70), "00.70")
    }

    func testSonyAppVerBuild79() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 79), "00.79")
    }

    func testSonyAppVerBuild81GoldHenScheme() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 81), "02.12")
        XCTAssertEqual(PkgVersioning.masterVersion(buildNum: 81), "02.12")
    }

    func testSonyAppVerBuild100() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 100), "02.31")
    }

    func testMasterVersionTracksBuild() {
        XCTAssertEqual(PkgVersioning.masterVersion(buildNum: 79), "00.79")
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 84), PkgVersioning.masterVersion(buildNum: 84))
    }

    func testVersionedPkgFileName() {
        let name = PkgVersioning.versionedPkgFileName(display: "0.7.9", buildLabel: "79", sonyAppVer: "00.79")
        XCTAssertEqual(name, "PS4-Linux-v0.7.9-b79-APP0079.pkg")
    }

    func testBumpIncrementsOnce() {
        let a = PkgVersioning.bump(displayRaw: "0.7.8", buildNumRaw: "78", bump: true)
        XCTAssertEqual(a.display, "0.7.9")
        XCTAssertEqual(a.buildLabel, "79")
        XCTAssertEqual(a.sonyAppVer, "00.79")
        XCTAssertEqual(a.masterVersion, "00.79")
    }

    func testBumpNoBumpPreservesPatch() {
        let a = PkgVersioning.bump(displayRaw: "0.7.9", buildNumRaw: "79", bump: false)
        XCTAssertEqual(a.display, "0.7.9")
        XCTAssertEqual(a.buildLabel, "79")
    }

    func testAppVerFitsParamSfo() {
        XCTAssertTrue(PkgVersioning.appVerFitsParamSfo("00.79"))
        XCTAssertFalse(PkgVersioning.appVerFitsParamSfo("00000079"))
    }
}

final class LanguageAssetPathsTests: XCTestCase {
    func testArabicUsesX21() {
        XCTAssertEqual(LanguageAssetPaths.jsonPath(languageCode: 21), "/app0/assets/languages/X21.json")
        XCTAssertEqual(LanguageAssetPaths.jsonPath(languageCode: 1), "/app0/assets/languages/01.json")
    }
}

final class PkgInspectorTests: XCTestCase {
    func testParseSfoSample() {
        let sample = """
        APP_VER : Utf8(6/8) = 00.79
        VERSION : Utf8(6/8) = 00.79
        TITLE_ID : Utf8(10/12) = CSTP00003
        CATEGORY : Utf8(3/4) = gd
        """
        let fields = PkgInspector.parseSfoListentries(sample)
        XCTAssertEqual(fields.appVer, "00.79")
        XCTAssertEqual(fields.version, "00.79")
        XCTAssertEqual(fields.titleID, "CSTP00003")
        XCTAssertEqual(fields.category, "gd")
    }

    func testValidateParamOk() {
        let fields = ParamSfoFields(appVer: "00.79", version: "00.79", titleID: "CSTP00003", category: "gde")
        let errors = PkgInspector.validateParam(fields: fields, expectedAppVer: "00.79", expectedMaster: "00.79")
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateParamRejectsSameAppAndVersion() {
        let fields = ParamSfoFields(appVer: "02.15", version: "02.15", titleID: "CSTP00003", category: "gde")
        let errors = PkgInspector.validateParam(fields: fields, expectedAppVer: "02.15", expectedMaster: "02.15")
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateParamRejectsMismatchedAppAndVersion() {
        let fields = ParamSfoFields(appVer: "01.14", version: "02.14", titleID: "CSTP00003", category: "gde")
        let errors = PkgInspector.validateParam(fields: fields, expectedAppVer: "01.14", expectedMaster: "02.14")
        XCTAssertFalse(errors.isEmpty)
    }
}

final class PkgLayoutGuardTests: XCTestCase {
    func testValidateGp4OkUnified() {
        let xml = """
        <file targ_path="eboot.bin" orig_path="eboot.bin" />
        <dir targ_name="fonts" />
        """
        XCTAssertTrue(PkgLayoutGuard.validateGp4(xml).isEmpty)
    }

    func testValidateGp4RejectsGuestOelf() {
        let xml = """
        <file targ_path="eboot.bin" orig_path="eboot.bin" />
        <file targ_path="assets/boot/guest.oelf" orig_path="assets/boot/guest.oelf" />
        """
        XCTAssertFalse(PkgLayoutGuard.validateGp4(xml).isEmpty)
    }

    func testValidateGp4RejectsRootGuest() {
        let xml = """
        <file targ_path="guest.elf" orig_path="guest.elf" />
        <file targ_path="eboot.bin" orig_path="eboot.bin" />
        """
        XCTAssertFalse(PkgLayoutGuard.validateGp4(xml).isEmpty)
    }

    func testValidateEbootRejectsSplitChainTiny() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let eboot = dir.appendingPathComponent("eboot.bin")
        let bytes = PkgLayoutGuard.fselfMagic + [UInt8](repeating: 0, count: 100_000)
        FileManager.default.createFile(atPath: eboot.path, contents: Data(bytes), attributes: nil)
        let errors = PkgLayoutGuard.validateEbootStructure(at: eboot)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.joined().contains("34878") || errors.joined().contains("split"))
    }

    func testCE41839_BootLogString41839FailsGuard() {
        let log = """
        ===== RUN START pkg v0.7.64 =====
        eboot: unified OpenOrbis eboot (kernel loader)
        error CE-41839-5 cannot start application
        """
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: nil)
        XCTAssertTrue(errors.contains { $0.contains("41839") })
    }

    func testCE41839_ConstantsMatchHardwareEvidence() {
        XCTAssertEqual(PkgLayoutGuard.fselfTenEntryHeaderMetaLe, 0x0470_0440)
        XCTAssertEqual(PkgLayoutGuard.fselfEightEntryHeaderMetaLe, 0x03D0_03D0)
        XCTAssertEqual(PkgLayoutGuard.fselfBadCreateFselfMacosField0x70Le, 0x0000_0080)
        XCTAssertEqual(PkgLayoutGuard.fselfOneFamilyReferenceBytes, 899_200)
        XCTAssertEqual(PkgLayoutGuard.fselfGoldHenShipMaxBytes, 950_000)
        XCTAssertEqual(PkgLayoutGuard.fselfGoldHenEightEntryProgramFlagsLe, 0x0022_0008)
        XCTAssertEqual(PkgLayoutGuard.fselfTenEntryProgramFlagsLe, 0x0022_000a)
        XCTAssertEqual(FselfShipGate.authInfoOffsetPyFakeMax, 1_800)
        XCTAssertEqual(FselfShipGate.authInfoOffsetCreateFselfMin, 1_900)
    }

    func testCE41839_FselfHeaderAcceptsCreateFselfTenEntryHeaderMeta() {
        let errors = PkgLayoutGuard.validateFselfHeader(
            bytes: stubFselfHeader(dwordAt0xC: PkgLayoutGuard.fselfTenEntryHeaderMetaLe, numEntries: 10)
        )
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
    }

    func testCE41839_FselfHeaderRejectsApolloPatchOnTenEntrySelf() {
        let errors = PkgLayoutGuard.validateFselfHeader(
            bytes: stubFselfHeader(dwordAt0xC: PkgLayoutGuard.fselfEightEntryHeaderMetaLe, numEntries: 10)
        )
        XCTAssertTrue(errors.contains { $0.contains("Apollo") || $0.contains("0x3D0") })
    }

    func testCE30008_PkgIntegrityRejectsZeroByteListedFile() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gp4 = """
        <file targ_path="eboot.bin" orig_path="eboot.bin" />
        <file targ_path="assets/languages/X21.json" orig_path="assets/languages/X21.json" />
        """
        FileManager.default.createFile(atPath: dir.appendingPathComponent("eboot.bin").path, contents: Data(), attributes: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("assets/languages/X21.json").path, contents: Data([0x7b, 0x7d]), attributes: nil)
        let errors = PkgLayoutGuard.validatePkgIntegrity(loaderDir: dir, gp4XML: gp4)
        XCTAssertTrue(errors.contains { $0.contains("30008") && $0.contains("eboot.bin") })
    }

    func testCE30008_PkgIntegrityRejectsTruncated3200Eboot() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let eboot = dir.appendingPathComponent("eboot.bin")
        FileManager.default.createFile(atPath: eboot.path, contents: Data(repeating: 0, count: 3200), attributes: nil)
        let gp4 = "<file targ_path=\"eboot.bin\" orig_path=\"eboot.bin\" />"
        let errors = PkgLayoutGuard.validatePkgIntegrity(loaderDir: dir, gp4XML: gp4)
        XCTAssertTrue(errors.contains { $0.contains("3200") && $0.contains("30008") })
    }

    func testCE30008_Gp4MustListRequiredManifestPaths() {
        let xml = "<file targ_path=\"eboot.bin\" orig_path=\"eboot.bin\" />"
        let errors = PkgLayoutGuard.validatePkgIntegrity(loaderDir: URL(fileURLWithPath: "/tmp"), gp4XML: xml)
        XCTAssertTrue(errors.contains { $0.contains("param.sfo") && $0.contains("30008") })
    }

    func testCE30008_BootLogString30008FailsGuard() {
        let log = """
        ===== RUN START =====
        error CE-30008-1 cannot start application
        """
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: nil)
        XCTAssertTrue(errors.contains { $0.contains("30008") })
    }

    func testCE30008_BootLogTruncated3200MarkerFailsGuard() {
        let log = "eboot: guest.elf ok size=3200 magic=7f454c46"
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: nil)
        XCTAssertTrue(errors.contains { $0.contains("30008") || $0.contains("3200") })
    }

    func testCE30008_Gp4TargPathsParser() {
        let xml = """
        <file targ_path="eboot.bin" orig_path="eboot.bin" />
        <file targ_path="sce_sys/param.sfo" orig_path="sce_sys/param.sfo" />
        """
        let paths = PkgLayoutGuard.gp4TargPaths(xml)
        XCTAssertEqual(paths, ["eboot.bin", "sce_sys/param.sfo"])
    }

    private func stubFselfHeader(dwordAt0xC: UInt32, numEntries: UInt16 = 10) -> Data {
        var data = Data(repeating: 0, count: 64)
        data.replaceSubrange(0..<4, with: PkgLayoutGuard.fselfMagic)
        data.replaceSubrange(8..<12, with: [0x01, 0x01, 0x00, 0x00])
        var le = dwordAt0xC.littleEndian
        withUnsafeBytes(of: &le) { raw in
            data.replaceSubrange(12..<16, with: raw)
        }
        var entries = numEntries.littleEndian
        withUnsafeBytes(of: &entries) { raw in
            data.replaceSubrange(24..<26, with: raw)
        }
        return data
    }

    func testValidateBootLogRejectsLoadExec() {
        let log = """
        eboot: menu autodetect /app0/assets/boot/guest.elf size=1612848
        eboot: LoadExec /app0/assets/boot/guest.elf
        """
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: nil)
        XCTAssertFalse(errors.isEmpty)
    }

    func testValidateBootLogAcceptsUnified() {
        let log = """
        ===== RUN START pkg v0.7.59 =====
        eboot: unified OpenOrbis eboot (kernel loader)
        step: 00 main entered
        app: guest main entered
        """
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: "v0.7.59")
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateBootLogRejectsCe34878LoaderOnly() {
        let log = """
        step: 03 guestPlainLoaderRun [v0.7.56]
        loader: running /app0/assets/boot/guest.oelf entry=0xf8be0 map=1534848
        """
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: nil)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.joined().contains("34878") || errors.joined().contains("split"))
    }

    func testValidateBootLogRejectsPlainLoaderWithoutMain() {
        let log = """
        ===== RUN START pkg v0.7.56 =====
        loader: running /app0/assets/boot/guest.oelf
        """
        let errors = PkgLayoutGuard.validateBootLogContent(log, expectedVersionPrefix: nil)
        XCTAssertFalse(errors.isEmpty)
    }
}

final class ConsoleLaunchE2ETests: XCTestCase {
    func testStrictFailsWhenLatestInstalledButLogsEmpty() {
        let errors = ConsoleLaunchE2E.validateLaunchAfterInstall(
            macLatestPkgFileName: "PS4-Linux-v0.7.72-b141-APP0272.pkg",
            consoleInstalledPkgFileName: "PS4-Linux-v0.7.72-b141-APP0272.pkg",
            combinedBootLog: ""
        )
        XCTAssertTrue(errors.contains { $0.contains("empty") || $0.contains("41839") || $0.contains("30008") })
    }

    func testStrictPassesWhenRunStartPresent() {
        let log = """
        ===== RUN START pkg v0.7.72 =====
        eboot: unified OpenOrbis eboot (kernel loader)
        app: guest main entered
        """
        let errors = ConsoleLaunchE2E.validateLaunchAfterInstall(
            macLatestPkgFileName: "PS4-Linux-v0.7.72-b141-APP0272.pkg",
            consoleInstalledPkgFileName: "PS4-Linux-v0.7.72-b141-APP0272.pkg",
            combinedBootLog: log
        )
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "; "))
    }

    func testMismatchInstalledVsMacReportsInstall() {
        let errors = ConsoleLaunchE2E.validateLaunchAfterInstall(
            macLatestPkgFileName: "PS4-Linux-v0.7.72-b141-APP0272.pkg",
            consoleInstalledPkgFileName: "PS4-Linux-v0.7.70-b139-APP0270.pkg",
            combinedBootLog: ""
        )
        XCTAssertTrue(errors.contains { $0.contains("0.7.70") && $0.contains("0.7.72") })
    }
}

final class TitleConstantsTests: XCTestCase {
    func testBootLogPathsIncludeTitleDir() {
        XCTAssertTrue(TitleConstants.bootLogPaths.first?.contains("CSTP00003") == true)
    }
}
