import Foundation

/// Console boot paths (mirrors app `BootStackStatus` and `ps4-linux-sync`).
public enum LinuxBootStackLogic {
    public static let bzImagePath = "/data/linux/boot/bzImage"
    public static let initramfsPath = "/data/linux/boot/initramfs.cpio.gz"
    public static let kernelIdPath = "/data/linux/boot/ps4-kernel-id.txt"

    public static let bzImageExpectedBytes: Int64 = 9_872_896
    public static let bzImageMinBytes: Int64 = 8_000_000
    public static let bzImageMaxBytes: Int64 = 16_000_000
    public static let initramfsMinBytes: Int64 = 3_000_000

    public struct RemoteCheck {
        public var kernelBytes: Int64?
        public var initramfsBytes: Int64?
        public var kernelId: String?

        public var kernelPresent: Bool { kernelBytes != nil }
        public var initramfsPresent: Bool { initramfsBytes != nil }

        public var kernelSizeOk: Bool {
            guard let k = kernelBytes else { return false }
            return k >= bzImageMinBytes && k <= bzImageMaxBytes
        }

        public var initramfsSizeOk: Bool {
            guard let i = initramfsBytes else { return false }
            return i >= initramfsMinBytes
        }

        public var readyForLaunch: Bool {
            kernelPresent && kernelSizeOk && initramfsPresent && initramfsSizeOk
        }

        public func statusLines() -> [String] {
            var lines: [String] = []
            if let k = kernelBytes {
                let tag = kernelSizeOk ? "OK" : "BAD SIZE"
                let exp = k == bzImageExpectedBytes ? " (feeRnt expected)" : ""
                lines.append("bzImage: \(k) B [\(tag)]\(exp) @ \(bzImagePath)")
            } else {
                lines.append("bzImage: missing @ \(bzImagePath)")
            }
            if let i = initramfsBytes {
                let tag = initramfsSizeOk ? "OK" : "TOO SMALL"
                lines.append("initramfs: \(i) B [\(tag)] @ \(initramfsPath)")
            } else {
                lines.append("initramfs: missing @ \(initramfsPath)")
            }
            if let id = kernelId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                lines.append("kernel id: \(id)")
            }
            if readyForLaunch {
                lines.append("Boot stack: ready for kexec")
            } else {
                lines.append("Boot stack: NOT ready — sync or use app Download kernel")
            }
            return lines
        }
    }

    public static func validateSizes(kernelBytes: Int64?, initramfsBytes: Int64?) -> RemoteCheck {
        RemoteCheck(kernelBytes: kernelBytes, initramfsBytes: initramfsBytes, kernelId: nil)
    }
}