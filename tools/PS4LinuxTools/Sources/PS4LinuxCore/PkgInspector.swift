import Foundation

public struct ParamSfoFields: Equatable {
    public var appVer: String?
    public var version: String?
    public var titleID: String?
    public var category: String?

    public init(appVer: String? = nil, version: String? = nil, titleID: String? = nil, category: String? = nil) {
        self.appVer = appVer
        self.version = version
        self.titleID = titleID
        self.category = category
    }
}

public enum PkgInspector {
    public static func parseSfoListentries(_ output: String) -> ParamSfoFields {
        var fields = ParamSfoFields()
        for line in output.split(separator: "\n") {
            let s = String(line)
            if s.contains("APP_VER :") {
                fields.appVer = sfoValue(s)
            } else if s.contains("VERSION :"), !s.contains("APP_VER") {
                fields.version = sfoValue(s)
            } else if s.contains("TITLE_ID :") {
                fields.titleID = sfoValue(s)
            } else if s.contains("CATEGORY :") {
                fields.category = sfoValue(s)
            }
        }
        return fields
    }

    private static func sfoValue(_ line: String) -> String? {
        guard let eq = line.range(of: " = ") else { return nil }
        return String(line[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    public static func validateParam(
        fields: ParamSfoFields,
        expectedAppVer: String,
        expectedMaster: String
    ) -> [String] {
        var errors: [String] = []
        guard fields.appVer != nil else {
            errors.append("APP_VER missing from param.sfo")
            return errors
        }
        if fields.appVer != expectedAppVer {
            errors.append("APP_VER mismatch: got \(fields.appVer ?? "nil"), want \(expectedAppVer)")
        }
        if fields.version != expectedMaster {
            errors.append("VERSION mismatch: got \(fields.version ?? "nil"), want \(expectedMaster)")
        }
        if fields.titleID != TitleConstants.titleID {
            errors.append("TITLE_ID mismatch: got \(fields.titleID ?? "nil")")
        }
        if let app = fields.appVer, let ver = fields.version, app == ver {
            errors.append("APP_VER must differ from VERSION")
        }
        if let app = fields.appVer, !PkgVersioning.appVerFitsParamSfo(app) {
            errors.append("APP_VER too long for param.sfo: \(app)")
        }
        return errors
    }

    public static func runPkgTool(_ tool: URL, args: [String]) throws -> String {
        let task = Process()
        task.executableURL = tool
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw NSError(
                domain: "PkgInspector", code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: out.isEmpty ? "PkgTool failed" : out]
            )
        }
        return out
    }

    public static func extractParamSfo(from pkg: URL, pkgTool: URL, workDir: URL) throws -> URL {
        let tmpSfo = workDir.appendingPathComponent("param.sfo")
        _ = try runPkgTool(pkgTool, args: ["pkg_extractentry", pkg.path, "9", tmpSfo.path])
        return tmpSfo
    }
}
