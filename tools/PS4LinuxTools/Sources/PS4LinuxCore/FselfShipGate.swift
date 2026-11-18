import Foundation

/// CE-41839-5 / CE-30008 launch gates from FTP hardware evidence — see tmp/console-evidence/CE-41839-ROOT-CAUSE.md
public enum FselfShipGate {
    /// First 16 bytes of OpenOrbis `--authinfo` in shipped PS4 Linux builds.
    public static let authInfoMarker: [UInt8] = [
        0x00, 0x1c, 0x00, 0x40, 0x00, 0xff, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x80, 0x00, 0x00,
    ]

    /// ps4-linux-make-fself.py places auth marker ~1716; create-fself ~1988+ (same ELF link).
    public static let authInfoOffsetPyFakeMax = 1_800
    public static let authInfoOffsetCreateFselfMin = 1_900

    /// Fixed SELF header constants shared by Apollo + OneFamily on user hardware.
    public static let fixedHeaderU32: [(offset: UInt64, value: UInt32, label: String)] = [
        (0x40, 0x0000_2804, "segment meta @0x40"),
        (0x60, 0x0031_0004, "segment meta @0x60"),
    ]

    /// @0x18: Apollo `08002200`; create-fself also emits `0a002200` — both seen on working homebrew.
    public static let allowedU32At0x18: Set<UInt32> = [0x0022_0008, 0x0022_000a]

    /// @0x70 after ps4-linux-fself.sh patch — Apollo or OneFamily (never macOS `0x80`).
    public static let allowedU32At0x70: Set<UInt32> = [
        PkgLayoutGuard.fselfApolloField0x70Le,
        PkgLayoutGuard.fselfOneFamilyField0x70Le,
        PkgLayoutGuard.fselfBadCreateFselfMacosField0x70Le,
    ]

    public struct Options: Sendable {
        public var requireMethodStamp: Bool
        public var requireCreateFselfSize: Bool
        public var requireAuthInfoLayout: Bool
        public var compareApolloFixedHeader: Bool
        /// CSTP00003 on GoldHEN: 8-entry FSELF ≤ ~950 KiB (OneFamily profile), not 10-entry ~1.6 MiB.
        public var requireGoldHenOneFamilyProfile: Bool

        public static let ship = Options(
            requireMethodStamp: true,
            requireCreateFselfSize: false,
            requireAuthInfoLayout: true,
            compareApolloFixedHeader: true,
            requireGoldHenOneFamilyProfile: true
        )

        public static let workingReference = Options(
            requireMethodStamp: false,
            requireCreateFselfSize: false,
            requireAuthInfoLayout: false,
            compareApolloFixedHeader: false,
            requireGoldHenOneFamilyProfile: false
        )
    }

    public static func consoleEvidenceEboot(repo: URL, relative: String) -> URL {
        repo.appendingPathComponent(relative, isDirectory: false)
    }

    public static func referenceApolloEboot(repo: URL) -> URL {
        consoleEvidenceEboot(repo: repo, relative: "tmp/console-evidence/ex-apollo/uroot/eboot.bin")
    }

    public static func referenceOneFamilyEboot(repo: URL) -> URL {
        consoleEvidenceEboot(repo: repo, relative: "tmp/console-evidence/ex-one/uroot/eboot.bin")
    }

    /// Full pre-ship validation for `eboot.bin` (not sufficient for kernel accept — blocks known-bad builds).
    public static func validate(eboot: URL, loaderDir: URL, options: Options = .ship) -> [String] {
        var errors: [String] = []
        errors.append(contentsOf: PkgLayoutGuard.validateEbootStructure(at: eboot))
        if options.requireMethodStamp {
            errors.append(contentsOf: validateMethodStamp(loaderDir: loaderDir))
        }
        if options.requireGoldHenOneFamilyProfile {
            errors.append(contentsOf: validateGoldHenOneFamilyShipProfile(eboot: eboot, loaderDir: loaderDir))
        } else if options.requireCreateFselfSize {
            errors.append(contentsOf: PkgLayoutGuard.validateFselfCreateFselfSize(at: eboot))
        }
        if options.requireAuthInfoLayout {
            errors.append(contentsOf: validateAuthInfoLayout(at: eboot, loaderDir: loaderDir))
        }
        if options.compareApolloFixedHeader {
            let repo = loaderDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let apollo = referenceApolloEboot(repo: repo)
            if FileManager.default.fileExists(atPath: apollo.path) {
                for msg in PkgLayoutGuard.fselfHeaderDiffVsApolloReference(eboot: eboot, apolloReference: apollo)
                    where msg.contains("0x00…0x0B") || msg.contains("@0x20") {
                    errors.append("\(msg) — CE-41839-5")
                }
            }
        }
        errors.append(contentsOf: validateFixedHeaderFields(at: eboot))
        return errors
    }

    public static func validateWorkingReference(eboot: URL) -> [String] {
        var errors: [String] = []
        errors.append(contentsOf: PkgLayoutGuard.validateEbootStructure(at: eboot))
        errors.append(contentsOf: validateFixedHeaderFields(at: eboot))
        return errors
    }

    public static func validateMethodStamp(loaderDir: URL) -> [String] {
        var errors: [String] = []
        let stamp = loaderDir.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile)
        guard FileManager.default.fileExists(atPath: stamp.path) else {
            errors.append(
                "Missing \(PkgLayoutGuard.fselfMethodStampFile) — run tools/ps4-linux-fself.sh (CE-41839-5 if shipped without create-fself)"
            )
            return errors
        }
        guard let raw = try? String(contentsOf: stamp, encoding: .utf8) else {
            errors.append("Unreadable \(PkgLayoutGuard.fselfMethodStampFile)")
            return errors
        }
        let method = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !method.isEmpty else {
            errors.append("Empty \(PkgLayoutGuard.fselfMethodStampFile)")
            return errors
        }
        for bad in PkgLayoutGuard.forbiddenFselfMethods where method.contains(bad) {
            errors.append("eboot built with forbidden \(bad) — CE-41839-5")
        }
        if !method.contains("create-fself") {
            errors.append(
                "FSELF stamp must be linux/create-fself or macos/create-fself-macos (got: \(method))"
            )
        }
        return errors
    }

    /// Hardware-valid CSTP00003 profile (2026-11-05): OneFamily-scale 8-entry FSELF only.
    public static func validateGoldHenOneFamilyShipProfile(eboot: URL, loaderDir: URL) -> [String] {
        var errors: [String] = []
        let size = PkgLayoutGuard.fileSize(eboot)
        if size > PkgLayoutGuard.fselfGoldHenShipMaxBytes {
            errors.append(
                "eboot.bin \(size) B exceeds GoldHEN OneFamily ceiling (\(PkgLayoutGuard.fselfGoldHenShipMaxBytes) B) — CE-41839-5"
            )
        }
        if let u18 = readU32(eboot, 0x18) {
            if u18 == PkgLayoutGuard.fselfTenEntryProgramFlagsLe {
                errors.append(
                    "eboot.bin 10-entry SELF @0x18=0x\(hex(u18)) — CSTP00003 requires 8-entry (OneFamily ~\(PkgLayoutGuard.fselfOneFamilyReferenceBytes) B)"
                )
            } else if u18 != PkgLayoutGuard.fselfGoldHenEightEntryProgramFlagsLe {
                errors.append(
                    "eboot.bin SELF @0x18=0x\(hex(u18)) (expected 8-entry 0x\(hex(PkgLayoutGuard.fselfGoldHenEightEntryProgramFlagsLe)))"
                )
            }
        }
        if let data = PkgLayoutGuard.readPrefixData(eboot, count: 16), data.count >= 16 {
            let headerMeta = UInt32(data[12]) | (UInt32(data[13]) << 8) | (UInt32(data[14]) << 16)
                | (UInt32(data[15]) << 24)
            if headerMeta != PkgLayoutGuard.fselfEightEntryHeaderMetaLe {
                errors.append(
                    "eboot.bin SELF HeaderSize/MetaSize @0x0C=0x\(String(format: "%08X", headerMeta)) (need OneFamily 0x03D003D0)"
                )
            }
        }
        if let u70 = readU32(eboot, 0x70), u70 != PkgLayoutGuard.fselfOneFamilyField0x70Le {
            errors.append(
                "eboot.bin SELF @0x70=0x\(hex(u70)) (need OneFamily 0x\(hex(PkgLayoutGuard.fselfOneFamilyField0x70Le)) — not create-fself-macos 0x80)"
            )
        }
        let stamp = loaderDir.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile)
        if let raw = try? String(contentsOf: stamp, encoding: .utf8) {
            let method = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            for bad in PkgLayoutGuard.forbiddenFselfMethods where method.contains(bad) {
                errors.append("eboot built with forbidden FSELF method \(bad) — CE-41839-5")
            }
        }
        return errors
    }

    /// Apollo + 8-entry create-fself (incl. stage 11 hardware) place authinfo ~1716; python repack uses the same offset — gate on stamp.
    public static let authInfoOffsetCreateFselfEightEntry = 1_716

    public static func validateAuthInfoLayout(at url: URL, loaderDir: URL? = nil) -> [String] {
        var errors: [String] = []
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            errors.append("Could not read eboot for authinfo layout")
            return errors
        }
        guard let offset = data.firstRange(of: Data(authInfoMarker))?.lowerBound else {
            errors.append("eboot.bin missing OpenOrbis authinfo marker (CE-41839-5)")
            return errors
        }
        let dir = loaderDir ?? url.deletingLastPathComponent()
        let thinStamp = dir.appendingPathComponent(PkgLayoutGuard.thinEbootStampFile)
        let isThin = FileManager.default.fileExists(atPath: thinStamp.path)
        let methodStamp = dir.appendingPathComponent(PkgLayoutGuard.fselfMethodStampFile)
        let method = (try? String(contentsOf: methodStamp, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let forbiddenPython = PkgLayoutGuard.forbiddenFselfMethods.contains { method.contains($0) }

        if !isThin, forbiddenPython, offset <= authInfoOffsetPyFakeMax {
            errors.append(
                "authinfo marker @\(offset) — ps4-linux-make-fself.py layout (CE-41839-5 on hardware)"
            )
        }
        if !isThin, !forbiddenPython, offset < authInfoOffsetCreateFselfMin,
           offset != authInfoOffsetCreateFselfEightEntry {
            errors.append(
                "authinfo marker @\(offset) — unexpected (Apollo/create-fself 8-entry uses \(authInfoOffsetCreateFselfEightEntry), large links ≥ \(authInfoOffsetCreateFselfMin))"
            )
        }
        return errors
    }

    public static func validateFixedHeaderFields(at url: URL) -> [String] {
        var errors: [String] = []
        if let le18 = readU32(url, 0x18), !allowedU32At0x18.contains(le18) {
            errors.append("eboot.bin SELF 0x18=0x\(hex(le18)) (unexpected program header flags)")
        }
        if let le70 = readU32(url, 0x70), !allowedU32At0x70.contains(le70) {
            errors.append(
                "eboot.bin SELF 0x70=0x\(hex(le70)) (unexpected — Apollo 0x100, OneFamily 0x60, or create-fself-macos 0x80)"
            )
        }
        for (offset, value, label) in fixedHeaderU32 {
            if let le = readU32(url, offset), le != value {
                errors.append("eboot.bin SELF \(label)=0x\(hex(le)) (expected 0x\(hex(value)))")
            }
        }
        return errors
    }

    public static func authInfoMarkerOffset(in url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return data.firstRange(of: Data(authInfoMarker))?.lowerBound
    }

    private static func readU32(_ url: URL, _ offset: UInt64) -> UInt32? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return nil }
        return UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "%08X", value)
    }
}
