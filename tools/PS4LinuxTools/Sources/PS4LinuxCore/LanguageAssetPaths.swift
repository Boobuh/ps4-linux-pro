import Foundation

public enum LanguageAssetPaths {
    /// OpenOrbis language JSON under `/app0/assets/languages/`.
    public static func jsonPath(languageCode: Int) -> String {
        if languageCode == 21 {
            return "/app0/assets/languages/X21.json"
        }
        return String(format: "/app0/assets/languages/%02d.json", languageCode)
    }

    public static func bundledLanguageBasenames(in assetsDir: URL) -> [String] {
        let langDir = assetsDir.appendingPathComponent("languages", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: langDir.path) else {
            return []
        }
        return entries.filter { $0.hasSuffix(".json") }.sorted()
    }

    /// Ensures Arabic uses X21.json on disk (PKG asset name).
    public static func validateBundledAssets(in assetsDir: URL) -> [String] {
        var errors: [String] = []
        let basenames = bundledLanguageBasenames(in: assetsDir)
        if !basenames.contains("X21.json") {
            errors.append("Missing assets/languages/X21.json (Arabic)")
        }
        if !basenames.contains("01.json") {
            errors.append("Missing assets/languages/01.json (English fallback)")
        }
        let path21 = jsonPath(languageCode: 21)
        if !path21.hasSuffix("X21.json") {
            errors.append("languageCode 21 must map to X21.json")
        }
        return errors
    }
}
