#if canImport(Darwin)
import Darwin
#endif
import Foundation

public struct GhProcess: GhRunning, Sendable {
    public static let defaultTimeout: TimeInterval = 30
    public static let maxOutputBytes = 1_048_576
    public static let maxErrorMessageLength = 240

    private let executablePath: String?
    private let timeout: TimeInterval
    private let maxOutputBytes: Int

    public init(
        executablePath: String? = GhExecutable.resolve(),
        timeout: TimeInterval = Self.defaultTimeout,
        maxOutputBytes: Int = Self.maxOutputBytes
    ) {
        self.executablePath = executablePath
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(_ arguments: [String]) async throws -> String {
        guard let executablePath else {
            throw GhError.notFound
        }

        let session = ProcessSession(
            executablePath: executablePath,
            arguments: arguments,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )

        return try await withTaskCancellationHandler {
            try await session.run()
        } onCancel: {
            session.terminate()
        }
    }

    static func sanitizedMessage(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxErrorMessageLength {
            return trimmed
        }
        return String(trimmed.prefix(maxErrorMessageLength)) + "…"
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

private final class ProcessSession: @unchecked Sendable {
    private let executablePath: String
    private let arguments: [String]
    private let timeout: TimeInterval
    private let maxOutputBytes: Int
    private let lock = NSLock()
    private var process: Process?

    init(executablePath: String, arguments: [String], timeout: TimeInterval, maxOutputBytes: Int) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process else { return }
        Self.forceTerminate(process)
    }

    func run() async throws -> String {
        try await Task.detached(priority: .utility) {
            try self.execute()
        }.value
    }

    private func execute() throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        lock.lock()
        self.process = process
        lock.unlock()

        do {
            try process.run()
        } catch {
            throw GhError.notFound
        }

        let group = DispatchGroup()
        let captured = PipeCapture()

        func collect(_ handle: FileHandle, isStdout: Bool) {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                captured.append(handle.readDataToEndOfFile(), isStdout: isStdout)
                group.leave()
            }
        }

        collect(stdout.fileHandleForReading, isStdout: true)
        collect(stderr.fileHandleForReading, isStdout: false)

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            Self.forceTerminate(process)
            _ = finished.wait(timeout: .now() + 2)
            _ = group.wait(timeout: .now() + 1)
            throw GhError.timedOut
        }

        group.wait()

        let outputBytes = captured.stdoutData
        let errorBytes = captured.stderrData

        if outputBytes.count > maxOutputBytes || errorBytes.count > maxOutputBytes {
            throw GhError.outputTooLarge
        }

        let output = String(data: outputBytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: errorBytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            return output
        }

        let message = GhProcess.sanitizedMessage(errorOutput)
        if errorOutput.localizedCaseInsensitiveContains("not logged")
            || errorOutput.localizedCaseInsensitiveContains("authentication")
            || errorOutput.localizedCaseInsensitiveContains("gh auth login")
        {
            throw GhError.unauthenticated(message)
        }

        throw GhError.failed(code: Int(process.terminationStatus), message: message)
    }

    private static func forceTerminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.4)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func append(_ chunk: Data, isStdout: Bool) {
        lock.lock()
        if isStdout {
            stdout.append(chunk)
        } else {
            stderr.append(chunk)
        }
        lock.unlock()
    }

    var stdoutData: Data {
        lock.lock()
        defer { lock.unlock() }
        return stdout
    }

    var stderrData: Data {
        lock.lock()
        defer { lock.unlock() }
        return stderr
    }
}
