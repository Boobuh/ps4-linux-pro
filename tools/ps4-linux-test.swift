#!/usr/bin/env swift
// Runs unit + integration + optional PS4 FTP e2e tests.
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let packageDir = repo.appendingPathComponent("tools/PS4LinuxTools")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
task.arguments = ["run", "--package-path", packageDir.path, "ps4-linux-test"]
    + Array(CommandLine.arguments.dropFirst())
task.currentDirectoryURL = repo
var env = ProcessInfo.processInfo.environment
env["PS4_HOST"] = env["PS4_HOST"] ?? "10.0.1.7"
env["PS4_PORT"] = env["PS4_PORT"] ?? "2121"
task.environment = env
task.standardOutput = FileHandle.standardOutput
task.standardError = FileHandle.standardError
do {
    try task.run()
    task.waitUntilExit()
    exit(task.terminationStatus)
} catch {
    fputs("ps4-linux-test: \(error)\n", stderr)
    exit(1)
}
