import PS4LinuxCore
import XCTest

final class PkgVersioningTests: XCTestCase {
    func testSonyAppVerBuild70() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 70), "00.70")
    }

    func testSonyAppVerBuild79() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 79), "00.79")
    }

    func testSonyAppVerBuild100() {
        XCTAssertEqual(PkgVersioning.sonyAppVer(buildNum: 100), "01.00")
    }

    func testMasterVersionTracksBuild() {
        XCTAssertEqual(PkgVersioning.masterVersion(buildNum: 79), "01.79")
        XCTAssertTrue(PkgVersioning.appVerDiffersFromMaster("00.79", "01.79"))
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
        XCTAssertEqual(a.masterVersion, "01.79")
    }

    func testBumpNoBumpPreservesPatch() {
        let a = PkgVersioning.bump(displayRaw: "0.7.9", buildNumRaw: "79", bump: false)
        XCTAssertEqual(a.display, "0.7.9")
        XCTAssertEqual(a.buildLabel, "79")
    }

    func testAppVerMaxLength() {
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
        VERSION : Utf8(6/8) = 01.79
        TITLE_ID : Utf8(10/12) = CSTP00002
        CATEGORY : Utf8(3/4) = gd
        """
        let fields = PkgInspector.parseSfoListentries(sample)
        XCTAssertEqual(fields.appVer, "00.79")
        XCTAssertEqual(fields.version, "01.79")
        XCTAssertEqual(fields.titleID, "CSTP00002")
        XCTAssertEqual(fields.category, "gd")
    }

    func testValidateParamOk() {
        let fields = ParamSfoFields(appVer: "00.79", version: "01.79", titleID: "CSTP00002", category: "gd")
        let errors = PkgInspector.validateParam(fields: fields, expectedAppVer: "00.79", expectedMaster: "01.79")
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateParamRejectsSameAppAndVersion() {
        let fields = ParamSfoFields(appVer: "01.00", version: "01.00", titleID: "CSTP00002", category: "gd")
        let errors = PkgInspector.validateParam(fields: fields, expectedAppVer: "01.00", expectedMaster: "01.00")
        XCTAssertFalse(errors.isEmpty)
    }
}

final class TitleConstantsTests: XCTestCase {
    func testBootLogPathsIncludeTitleDir() {
        XCTAssertTrue(TitleConstants.bootLogPaths.first?.contains("CSTP00002") == true)
    }
}
