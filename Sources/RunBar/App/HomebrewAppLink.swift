import Foundation
import RunBarCore

enum HomebrewAppLink {
    static func ensureApplicationsSymlink(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) {
        guard InstallOrigin.from(bundlePath: bundleURL.path) == .homebrewFormula,
              bundleURL.pathExtension == "app"
        else { return }

        let apps = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let dest = apps.appendingPathComponent("RunBar.app")
        do {
            try fileManager.createDirectory(at: apps, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: dest.path) {
                let values = try dest.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink == true else { return }
                try fileManager.removeItem(at: dest)
            }
            try fileManager.createSymbolicLink(at: dest, withDestinationURL: bundleURL)
        } catch {
            // Best-effort. The keg app still launches.
        }
    }
}
