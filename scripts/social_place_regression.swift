import Foundation

let fileManager = FileManager.default
let workingDirectory = URL(
    fileURLWithPath: fileManager.currentDirectoryPath,
    isDirectory: true
)
let scriptURL = URL(
    fileURLWithPath: CommandLine.arguments[0],
    relativeTo: workingDirectory
).standardizedFileURL
let helperURL = scriptURL
    .deletingLastPathComponent()
    .appendingPathComponent("run-social-place-regression.sh")

guard fileManager.fileExists(atPath: helperURL.path) else {
    fputs("social place regression: missing helper \(helperURL.path)\n", stderr)
    exit(1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [helperURL.path] + Array(CommandLine.arguments.dropFirst())
process.currentDirectoryURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    fputs("social place regression: ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}
