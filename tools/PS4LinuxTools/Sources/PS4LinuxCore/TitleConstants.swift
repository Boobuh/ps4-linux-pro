import Foundation

public enum TitleConstants {
    public static let titleID = "CSTP00003"
    public static let contentID = "IV0000-CSTP00003_00-PS4LINUXL0700001"
    public static let canonicalPkgFileName = "IV0000-CSTP00003_00-PS4LINUXL0700001.pkg"
    /// Previous pre-release ID; remove from Library if still present.
    public static let legacyTitleIDs = ["CSTP00002", "CSTP00001"]

    /// Primary boot log (title install dir on GoldHEN FTP).
    public static let bootLogPaths: [String] = [
        "/user/app/CSTP00003/ps4-linux-app.log",
        "/user/.ps4-linux-app.log",
        "/user/data/ps4-linux-app.log",
        "/data/pkg/ps4-linux-app.log",
        "/data/linux/boot/ps4-linux-app.log",
    ]
}
