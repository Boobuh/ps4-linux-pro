import Foundation

/// Mirrors `LinuxLoaderView` main menu mapping.
public enum LinuxMainMenuAction: Equatable {
    case primaryLaunch
    case newInstallWipe
    case installGb
    case vram
    case refresh
}

public enum LinuxMenuLogic {
    public static func mainMenuCount(installReady: Bool) -> Int {
        installReady ? 5 : 4
    }

    public static func action(installReady: Bool, index: Int) -> LinuxMainMenuAction? {
        let count = mainMenuCount(installReady: installReady)
        guard index >= 0, index < count else { return nil }
        if installReady {
            switch index {
            case 0: return .primaryLaunch
            case 1: return .newInstallWipe
            case 2: return .installGb
            case 3: return .vram
            default: return .refresh
            }
        }
        switch index {
        case 0: return .primaryLaunch
        case 1: return .installGb
        case 2: return .vram
        default: return .refresh
        }
    }

    public static func primaryMenuTitle(level: LinuxInstallLevel) -> String {
        switch level {
        case .ready:
            return "Boot installed Linux"
        case .partial:
            return "Setup new install (fix partial)"
        case .none:
            return "Install Linux on HDD"
        }
    }

    public static func primaryLaunchWipesArch(level: LinuxInstallLevel) -> Bool {
        level == .partial
    }

    public static func archPresetGigabytes() -> [Int] {
        [50, 75, 100, 125, 150, 200]
    }

    public static func vramMegabytesOptions() -> [Int] {
        LinuxBootConfigLogic.allowedVramMb
    }
}
