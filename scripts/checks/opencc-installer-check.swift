// Verifies that OpenCC installation invokes Homebrew explicitly and reports package-manager failures.

import Foundation

@main
struct OpenCCInstallerCheck {
    static func main() async throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vhrase-opencc-installer-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }

        let argumentsURL = fixtureDirectory.appendingPathComponent("arguments.txt")
        let successfulBrewURL = fixtureDirectory.appendingPathComponent("brew-success")
        try writeExecutable(
            at: successfulBrewURL,
            body: "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(argumentsURL.path)'\n"
        )
        try await OpenCCInstaller(homebrewURL: successfulBrewURL).install()
        let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
        precondition(arguments == "install\nopencc\n")

        let failingBrewURL = fixtureDirectory.appendingPathComponent("brew-failure")
        try writeExecutable(
            at: failingBrewURL,
            body: "#!/bin/sh\necho 'formula download failed' >&2\nexit 1\n"
        )
        do {
            try await OpenCCInstaller(homebrewURL: failingBrewURL).install()
            preconditionFailure("Expected the failed Homebrew process to throw")
        } catch {
            precondition(error.localizedDescription.contains("formula download failed"))
        }

        do {
            try await OpenCCInstaller(homebrewURL: nil).install()
            preconditionFailure("Expected missing Homebrew to throw")
        } catch {
            precondition(error.localizedDescription.contains("Homebrew"))
        }

        print("OpenCC installer checks passed")
    }

    private static func writeExecutable(at url: URL, body: String) throws {
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
