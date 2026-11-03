import Foundation

public enum TitleConstants {
    public static let titleID = "CSTP00002"
    public static let contentID = "IV0000-CSTP00002_00-PS4LINUXL0700000"
    public static let canonicalPkgFileName = "IV0000-CSTP00002_00-PS4LINUXL0700000.pkg"

    /// Primary boot log (title install dir on GoldHEN FTP).
    public static let bootLogPaths: [String] = [
        "/user/app/CSTP00002/ps4-linux-app.log",
        "/user/.ps4-linux-app.log",
        "/user/data/ps4-linux-app.log",
        "/data/pkg/ps4-linux-app.log",
        "/data/linux/boot/ps4-linux-app.log",
    ]
}
