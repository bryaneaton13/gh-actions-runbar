import Foundation

public struct GhProcess: GhRunning, Sendable {
    private let executablePath: String?

    public init(executablePath: String? = GhExecutable.resolve()) {
        self.executablePath = executablePath
    }

    public func run(_ arguments: [String]) async throws -> String {
        guard let executablePath else {
            throw GhError.notFound
        }

        return try await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            do {
                try process.run()
            } catch {
                throw GhError.notFound
            }

            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return output
            }

            if errorOutput.localizedCaseInsensitiveContains("not logged")
                || errorOutput.localizedCaseInsensitiveContains("authentication")
                || errorOutput.localizedCaseInsensitiveContains("gh auth login")
            {
                throw GhError.unauthenticated(errorOutput)
            }

            throw GhError.failed(code: Int(process.terminationStatus), message: errorOutput.isEmpty ? output : errorOutput)
        }.value
    }
}

public enum GhExecutable {
    public static func resolve() -> String? {
        var candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for directory in pathEnv.split(separator: ":") {
                candidates.append("\(directory)/gh")
            }
        }

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
