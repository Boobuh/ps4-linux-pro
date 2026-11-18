import Foundation

/// Mirrors `tools/ps4-linux-sync.swift` `isKexecLoaderBin` / `isElfFile`.
public enum KexecLoaderBinLogic {
    public static let minBytes = 8192
    public static let maxBytes = 2 * 1024 * 1024
    public static let referenceKexecSize = 329_088

    public static func isElfMagic(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x7f && data[1] == 0x45 && data[2] == 0x4c && data[3] == 0x46
    }

    public static func isKexecLoaderBin(fileSize: Int, header: Data) -> Bool {
        if isElfMagic(header) { return false }
        return fileSize >= minBytes && fileSize <= maxBytes
    }
}
