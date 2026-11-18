import Foundation

/// Enforces canonical PS4 Linux PKG layout — see tmp/docs/PS4-LINUX-INTERNAL-RUNBOOK.md and docs/PS4-HOMEBREW-LOADER-PATTERNS.md
public enum PkgLayoutGuard {
    /// Legacy unified gate (Apollo-class). GoldHEN CSTP00003 ships under OneFamily ceiling instead.
    public static let ebootMinUnifiedBytes = 512 * 1024
    /// OneFamily companion on user GoldHEN (FTP `ex-one/uroot/eboot.bin`).
    public static let fselfOneFamilyReferenceBytes = 899_200
    /// Hard ceiling for CSTP00003 — larger 10-entry create-fself → CE-41839 before BootTrace.
    public static let fselfGoldHenShipMaxBytes = 950_000
    /// SELF @0x18 program flags: 8-entry (OneFamily / thin) vs 10-entry (hello_world — rejected on CSTP00003).
    public static let fselfGoldHenEightEntryProgramFlagsLe: UInt32 = 0x0022_0008
    public static let fselfTenEntryProgramFlagsLe: UInt32 = 0x0022_000a
    /// Sanity cap (Apollo ~6.5 MiB on hardware); not CE-41839 — bad SELF/PKG causes that.
    public static let ebootSanityMaxBytes = 16 * 1024 * 1024
    public static let splitChainMaxBytes = 512 * 1024 - 1
    public static let fselfMagic: [UInt8] = [0x4f, 0x15, 0x3d, 0x1d]
    /// SELF @0x0C is HeaderSize (u16) + MetaSize (u16). Unified PS4 Linux link has 10 entries → 0x440 / 0x470.
    public static let fselfTenEntryHeaderMetaLe: UInt32 = 0x0470_0440
    /// Apollo / OneFamily (8 SELF entries) → HeaderSize/MetaSize 0x3D0 / 0x3D0 at @0x0C.
    public static let fselfEightEntryHeaderMetaLe: UInt32 = 0x03D0_03D0
    /// Unified PS4 Linux create-fself output (same as fselfTenEntryHeaderMetaLe).
    public static let fselfBadCreateFselfMacosLe: UInt32 = 0x0470_0440
    @available(*, deprecated, renamed: "fselfEightEntryHeaderMetaLe")
    public static let fselfGoodKeyTypeLe: UInt32 = 0x03D0_03D0
    public static let fselfExpectedKeyTypeLe: UInt32 = 0x101
    public static let fselfUnifiedSelfEntryCount: UInt16 = 10
    /// create-fself-macos (unpatched) LE u32 @ SELF 0x70 (bytes `80 00 00 00`).
    public static let fselfBadCreateFselfMacosField0x70Le: UInt32 = 0x0000_0080
    /// Apollo reference LE u32 @ 0x70 (hardware-valid).
    public static let fselfApolloField0x70Le: UInt32 = 0x0000_0100
    /// OneFamily companion LE u32 @ 0x70.
    public static let fselfOneFamilyField0x70Le: UInt32 = 0x0000_0060
    /// ps4-linux-make-fself.py output for this link (~1.51 MiB). Kernel rejects → CE-41839-5; not a ship path.
    public static let fselfFakePythonShrinkMaxBytes: Int = 1_560_000
    /// OpenOrbis create-fself for current unified link (~1.61 MiB).
    /// OpenOrbis hello_world ~1.21 MiB; PS4 Linux stage-12 UI ~1.58 MiB (10-entry create-fself-macos).
    public static let fselfCreateFselfMinBytes: Int = 1_570_000
    public static let fselfMethodStampFile = ".ps4-linux-fself-method"
    /// Present when PS4LINUX_THIN=1 — hardware-valid probe path on CSTP00003 before full UI link is restored.
    public static let thinEbootStampFile = ".ps4-linux-thin-eboot"
    public static let ebootMinThinBytes = 64 * 1024
    public static let forbiddenFselfMethods = [
        "ps4-linux-make-fself.py",
        "make_fself",
        "eight-entry-fself-fallback",
    ]
    /// Fixed-prefix bytes that match Apollo/OneFamily for offsets 0x00…0x0B (before size-dependent fields).
    public static let fselfApolloPrefix12: [UInt8] = [
        0x4f, 0x15, 0x3d, 0x1d, 0x00, 0x01, 0x01, 0x12, 0x01, 0x01, 0x00, 0x00,
    ]
    /// Program auth id field @ SELF 0x20 (matches Apollo/OpenOrbis homebrew samples).
    public static let fselfExpectedAuthIdPrefixLe: UInt32 = 0x0011_0004

    /// Corrupt partial installs on console (FTP); launch fails with CE-30008-1 before app runs.
    public static let ce30008TruncatedEbootSizes: Set<Int> = [3200, 8192]
    /// Paths that must be listed in pkg.gp4 and non-empty on disk (incomplete PKG → CE-30008-1).
    /// OpenOrbis sample PRX (~52 KiB). 3200 B stubs break some GoldHEN launches (CE-41839-5).
    public static let sceModulePrxMinBytes = 50_000

    public static let pkgRequiredGp4Paths: [String] = [
        "eboot.bin",
        "sce_sys/param.sfo",
        "sce_sys/about/right.sprx",
        "sce_module/libc.prx",
        "sce_module/libSceFios2.prx",
        "assets/languages/X21.json",
    ]

    private static let forbiddenGp4RootExecutables = ["guest.elf", "linux_menu.elf"]
    private static let forbiddenSplitAsset = "assets/boot/guest.oelf"
    private static let requiredMakefileNeedles = [
        "$(MENU_OBJS) -o $(ODIR)/eboot.elf $(LDFLAGS)",
        "--paid $(PAID)",
        "--authinfo=$(AUTHINFO)",
        "PAID          := 0x3800000000000011",
        "PS4LINUX_EBOOT_MIN_BYTES",
        "PS4LINUX_EBOOT_MAX_BYTES",
        "unified eboot",
    ]
    private static let forbiddenMakefileNeedles = [
        "guestPlainLoaderRun",
        "chain_launcher.o",
        "guest_plain_loader",
        "GUEST_OELF",
        "CHAIN_LDFLAGS",
        "LoadExec Mac-synced",
        "GUEST_ASSET   := assets/boot/guest.elf",
    ]

    public static func validateBuildTree(loaderDir: URL) -> [String] {
        var errors: [String] = []

        let makefile = loaderDir.appendingPathComponent("Makefile")
        if let mk = try? String(contentsOf: makefile, encoding: .utf8) {
            for needle in requiredMakefileNeedles where !mk.contains(needle) {
                errors.append("Makefile missing required layout token: \(needle)")
            }
            for needle in forbiddenMakefileNeedles where mk.contains(needle) {
                errors.append("Makefile contains forbidden split-loader pattern: \(needle)")
            }
        } else {
            errors.append("Missing Makefile")
        }

        let eboot = loaderDir.appendingPathComponent("eboot.bin")
        errors.append(contentsOf: FselfShipGate.validate(eboot: eboot, loaderDir: loaderDir, options: .ship))

        let splitMenu = loaderDir.appendingPathComponent(forbiddenSplitAsset)
        if FileManager.default.fileExists(atPath: splitMenu.path) {
            errors.append("Remove \(forbiddenSplitAsset) — unified eboot only (CE-34878-0)")
        }

        if FileManager.default.fileExists(atPath: loaderDir.appendingPathComponent("assets/boot/guest.elf").path) {
            errors.append("Remove assets/boot/guest.elf — LoadExec secondary FSELF (st_size bug)")
        }

        for forbidden in forbiddenGp4RootExecutables {
            let rootCopy = loaderDir.appendingPathComponent(forbidden)
            if FileManager.default.fileExists(atPath: rootCopy.path) {
                errors.append("Remove root \(forbidden)")
            }
        }

        let gp4 = loaderDir.appendingPathComponent("pkg.gp4")
        if let xml = try? String(contentsOf: gp4, encoding: .utf8) {
            errors.append(contentsOf: validateGp4(xml))
            errors.append(contentsOf: validatePkgIntegrity(loaderDir: loaderDir, gp4XML: xml))
        } else {
            errors.append("Missing pkg.gp4 after build")
        }

        return errors
    }

    /// Size, magic, and core SELF dwords (used by FselfShipGate and unit tests).
    public static func validateEbootStructure(at url: URL) -> [String] {
        var errors: [String] = []
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("Missing eboot.bin")
            return errors
        }
        let size = fileSize(url)
        let thinStamp = url.deletingLastPathComponent().appendingPathComponent(thinEbootStampFile)
        let isThin = FileManager.default.fileExists(atPath: thinStamp.path)
        let minBytes = isThin ? ebootMinThinBytes : ebootMinUnifiedBytes
        if !isThin && size <= splitChainMaxBytes {
            errors.append(
                "eboot.bin too small (\(size) B): split-chain layout (CE-34878-0 / manual PLT loader regression)"
            )
        }
        if size < minBytes {
            errors.append("eboot.bin below minimum (\(size) B < \(minBytes))\(isThin ? " thin shell" : "")")
        }
        if size > ebootSanityMaxBytes {
            errors.append("eboot.bin unexpectedly large (\(size) B)")
        }
        if let magic = readPrefix(url, count: 4), magic != fselfMagic {
            errors.append("eboot.bin missing FSELF magic 4F153D1D (CE-41839-5 risk)")
        }
        errors.append(contentsOf: validateFselfHeaderSizeMeta(bytes: readPrefixData(url, count: 32) ?? Data()))
        if let prefix = readPrefix(url, count: 12), prefix != fselfApolloPrefix12 {
            errors.append(
                "eboot.bin SELF prefix 0x00…0x0B differs from Apollo reference (CE-41839-5 risk)"
            )
        }
        if let auth = readU32LE(url, offset: 0x20), auth != fselfExpectedAuthIdPrefixLe {
            errors.append(
                "eboot.bin SELF 0x20=0x\(String(format: "%08X", auth)) (expected 0x00110004 like Apollo homebrew)"
            )
        }
        return errors
    }

    /// Pre-ship eboot checks (delegates to FselfShipGate for full CE-41839 guards).
    public static func validateEboot(at url: URL) -> [String] {
        FselfShipGate.validate(
            eboot: url,
            loaderDir: url.deletingLastPathComponent(),
            options: .ship
        )
    }

    public static func validateFselfCreateFselfSize(at url: URL) -> [String] {
        var errors: [String] = []
        let size = fileSize(url)
        let isThin = FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().appendingPathComponent(thinEbootStampFile).path
        )
        if isThin, size >= ebootMinThinBytes, size < fselfCreateFselfMinBytes {
            return errors
        }
        if size <= fselfFakePythonShrinkMaxBytes {
            errors.append(
                "eboot.bin \(size) B looks like ps4-linux-make-fself.py fake SELF (need create-fself ≥ \(fselfCreateFselfMinBytes) B) — CE-41839-5"
            )
        }
        if size >= ebootMinUnifiedBytes && size < fselfCreateFselfMinBytes {
            errors.append(
                "eboot.bin \(size) B below create-fself minimum for unified link — CE-41839-5 risk"
            )
        }
        return errors
    }

    /// Fields tied to kernel SELF reject — prefer FselfShipGate.validate for ship builds.
    public static func validateFselfLaunchFields(at url: URL) -> [String] {
        validateFselfCreateFselfSize(at: url)
            + FselfShipGate.validateFixedHeaderFields(at: url)
    }

    /// Byte-level diff vs a working Apollo eboot for fixed header slots (ignores size/load offsets).
    public static func fselfHeaderDiffVsApolloReference(eboot: URL, apolloReference: URL) -> [String] {
        var errors: [String] = []
        guard let ours = try? Data(contentsOf: eboot, options: [.mappedIfSafe]),
              let apollo = try? Data(contentsOf: apolloReference, options: [.mappedIfSafe]) else {
            errors.append("Could not read eboot or Apollo reference for header diff")
            return errors
        }
        let slots: [(Int, Int, String)] = [
            (0x00, 0x0c, "SELF header 0x00…0x0B (excludes size-dependent HeaderSize/MetaSize)"),
            (0x20, 4, "auth id @0x20"),
        ]
        for (offset, length, label) in slots {
            guard ours.count >= offset + length, apollo.count >= offset + length else {
                errors.append("\(label): eboot or Apollo too small for compare")
                continue
            }
            let a = ours[offset ..< offset + length]
            let b = apollo[offset ..< offset + length]
            if a != b {
                errors.append(
                    "\(label) mismatch vs Apollo (ours=\(a.map { String(format: "%02X", $0) }.joined()) apollo=\(b.map { String(format: "%02X", $0) }.joined()))"
                )
            }
        }
        return errors
    }

    /// Validates HeaderSize/MetaSize @0x0C and KeyType @0x08 (CE-41839-5 if Apollo patch applied to 10-entry SELF).
    public static func validateFselfHeaderSizeMeta(bytes: Data) -> [String] {
        var errors: [String] = []
        guard bytes.count >= 28 else {
            errors.append("eboot.bin too small for SELF extended header (CE-41839-5 risk)")
            return errors
        }
        let keyType = UInt32(bytes[8]) | (UInt32(bytes[9]) << 8) | (UInt32(bytes[10]) << 16)
            | (UInt32(bytes[11]) << 24)
        if keyType != fselfExpectedKeyTypeLe {
            errors.append(
                "eboot.bin SELF KeyType @0x08=0x\(String(format: "%08X", keyType)) (expected 0x101)"
            )
        }
        let headerMeta = UInt32(bytes[12]) | (UInt32(bytes[13]) << 8) | (UInt32(bytes[14]) << 16)
            | (UInt32(bytes[15]) << 24)
        let numEntries = UInt16(bytes[24]) | (UInt16(bytes[25]) << 8)
        if numEntries == fselfUnifiedSelfEntryCount {
            if headerMeta == fselfEightEntryHeaderMetaLe {
                errors.append(
                    "eboot.bin SELF HeaderSize/MetaSize 0x3D0/0x3D0 wrong for \(numEntries) entries (Apollo @0x0C patch — CE-41839-5)"
                )
            } else if headerMeta != fselfTenEntryHeaderMetaLe {
                errors.append(
                    "eboot.bin SELF @0x0C=0x\(String(format: "%08X", headerMeta)) (need 0x04700440 for unified 10-entry link)"
                )
            }
        }
        return errors
    }

    /// Validates FSELF header fields tied to CE-41839-5 (kernel rejects SELF before app logs run).
    public static func validateFselfHeader(bytes: Data) -> [String] {
        var errors: [String] = []
        guard bytes.count >= 16 else {
            errors.append("eboot.bin too small for FSELF header (CE-41839-5 risk)")
            return errors
        }
        let magic = [UInt8](bytes.prefix(4))
        if magic != fselfMagic {
            errors.append("eboot.bin missing FSELF magic 4F153D1D (CE-41839-5 risk)")
        }
        errors.append(contentsOf: validateFselfHeaderSizeMeta(bytes: bytes))
        return errors
    }

    static func readPrefixData(_ url: URL, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }

    private static func readU32LE(_ url: URL, offset: UInt64) -> UInt32? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return nil }
        return UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
    }

    public static func validateGp4(_ xml: String) -> [String] {
        var errors: [String] = []
        if xml.contains("targ_path=\"\(forbiddenSplitAsset)\"") {
            errors.append("pkg.gp4 must not ship \(forbiddenSplitAsset)")
        }
        if xml.contains("targ_path=\"assets/boot/guest.elf\"") {
            errors.append("pkg.gp4 must not ship assets/boot/guest.elf FSELF")
        }
        for name in forbiddenGp4RootExecutables {
            if xml.contains("targ_path=\"\(name)\"") {
                errors.append("pkg.gp4 must not ship root targ_path=\"\(name)\"")
            }
        }
        let ebootCount = xml.components(separatedBy: "targ_path=\"eboot.bin\"").count - 1
        if ebootCount != 1 {
            errors.append("pkg.gp4 should list eboot.bin exactly once (found \(ebootCount))")
        }
        return errors
    }

    /// Parses `targ_path="…"` entries from a gp4 project file.
    public static func gp4TargPaths(_ xml: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "targ_path=\"([^\"]+)\"") else {
            return []
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var paths: [String] = []
        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: xml) else { return }
            paths.append(String(xml[r]))
        }
        return paths
    }

    /// CE-30008-1: corrupt or incomplete PKG (0-byte / truncated files in the install image).
    public static func validatePkgIntegrity(loaderDir: URL, gp4XML: String) -> [String] {
        var errors: [String] = []
        for required in pkgRequiredGp4Paths where !gp4XML.contains("targ_path=\"\(required)\"") {
            errors.append("pkg.gp4 missing required \(required) (CE-30008-1 incomplete PKG)")
        }
        for path in gp4TargPaths(gp4XML) {
            let file = loaderDir.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: file.path) else {
                errors.append("PKG lists missing file \(path) (CE-30008-1)")
                continue
            }
            let size = fileSize(file)
            if size == 0 {
                errors.append("PKG file \(path) is 0 bytes (CE-30008-1 corrupt PKG)")
            }
            if path == "eboot.bin", ce30008TruncatedEbootSizes.contains(size) {
                errors.append("eboot.bin truncated (\(size) B) — CE-30008-1 (delete tile, reinstall PKG)")
            }
            if path.hasPrefix("sce_module/"), path.hasSuffix(".prx"), size < sceModulePrxMinBytes {
                errors.append(
                    "\(path) truncated (\(size) B) — use OpenOrbis sample sce_module (~52 KiB), not 3200 B stub (CE-41839-5)"
                )
            }
        }
        return errors
    }
    public static func validateBootLogContent(_ body: String, expectedVersionPrefix: String?) -> [String] {
        var errors: [String] = []
        if body.contains("LoadExec /app0/assets/boot/guest.elf") || body.contains("menu autodetect") {
            errors.append("Boot log shows obsolete LoadExec chain — delete tile and reinstall latest PKG")
        }
        if body.contains("LoadExec /app0/guest.elf") {
            errors.append("Boot log shows obsolete root guest LoadExec")
        }
        if body.contains("guestPlainLoaderRun") || body.contains("chain start (plain ELF loader)") {
            errors.append("Boot log shows split plain-loader chain (CE-34878-0 regression)")
        }
        let loaderHandoff = body.contains("loader: running")
        let guestAlive = body.contains("app: guest main entered") || body.contains("step: 10")
        if loaderHandoff && !guestAlive {
            errors.append(
                "Boot log shows plain loader handoff without guest main (CE-34878-0)"
            )
        }
        if body.contains("loader: dlsym failed") {
            errors.append("Plain loader PLT failure (CE-34878-0)")
        }
        if !body.contains("RUN START") && !body.contains("unified OpenOrbis eboot") {
            errors.append("Boot log missing RUN START or unified eboot marker (launch app after install?)")
        }
        if let prefix = expectedVersionPrefix, !body.isEmpty, !body.contains(prefix) {
            errors.append("Boot log missing expected version marker \(prefix)")
        }
        if !body.isEmpty && !guestAlive {
            errors.append("Boot log missing app: guest main entered / step: 10 (app crashed before UI)")
        }
        if body.contains("41839") {
            errors.append("Console reported CE-41839 — invalid SELF/PKG (check create-fself / reinstall)")
        }
        if body.contains("30008") {
            errors.append("Console reported CE-30008-1 — corrupt/incomplete PKG (delete tile, reinstall from /data/pkg/)")
        }
        if body.contains("size=3200") || body.contains("guest.elf ok size=3200") {
            errors.append("Boot log shows truncated ~3200 B menu binary (CE-30008-1)")
        }
        return errors
    }

    public static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func readPrefix(_ url: URL, count: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: count)
        guard data.count == count else { return nil }
        return [UInt8](data)
    }
}
