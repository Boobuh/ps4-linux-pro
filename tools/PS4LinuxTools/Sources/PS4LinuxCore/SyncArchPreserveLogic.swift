import Foundation

/// Mac `ps4-linux-sync` must never delete a finished Linux partition on the console by accident.
public enum SyncArchPreserveDecision: Equatable {
    case noArchOnConsole
    case preserveInstalled(archBytes: Int64)
    case removePartialOnly(archBytes: Int64)
    case explicitWipe
}

public enum SyncArchPreserveLogic {
    /// Matches `kMinPartialArchBytes` in `tools/ps4-linux-sync.swift`.
    public static let minPartialBytes: Int64 = 256 * 1024 * 1024

    public static func decide(archBytes: Int64?, wipeRequested: Bool) -> SyncArchPreserveDecision {
        if wipeRequested {
            return .explicitWipe
        }
        guard let bytes = archBytes, bytes >= 0 else {
            return .noArchOnConsole
        }
        if bytes < minPartialBytes {
            return .removePartialOnly(archBytes: bytes)
        }
        return .preserveInstalled(archBytes: bytes)
    }

    public static func shouldDeleteArchOnSync(archBytes: Int64?, wipeRequested: Bool) -> Bool {
        switch decide(archBytes: archBytes, wipeRequested: wipeRequested) {
        case .explicitWipe, .removePartialOnly:
            return true
        case .noArchOnConsole, .preserveInstalled:
            return false
        }
    }
}