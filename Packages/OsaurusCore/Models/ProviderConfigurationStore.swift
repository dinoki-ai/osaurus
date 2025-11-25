//
//  ProviderConfigurationStore.swift
//  osaurus
//
//  Persistence for ProviderConfiguration (Application Support bundle directory)
//

import Foundation

@MainActor
public enum ProviderConfigurationStore {
    /// Optional directory override for tests
    static var overrideDirectory: URL?

    public static func load() -> ProviderConfiguration {
        let url = configurationFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                return try decoder.decode(ProviderConfiguration.self, from: data)
            } catch {
                print("[Osaurus] Failed to load ProviderConfiguration: \(error)")
            }
        }
        // On first use, create defaults and persist
        let defaults = ProviderConfiguration.default
        save(defaults)
        return defaults
    }

    public static func save(_ configuration: ProviderConfiguration) {
        let url = configurationFileURL()
        do {
            try ensureDirectoryExists(url.deletingLastPathComponent())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[Osaurus] Failed to save ProviderConfiguration: \(error)")
        }
    }

    // MARK: - Private

    private static func configurationFileURL() -> URL {
        if let overrideDirectory {
            return overrideDirectory.appendingPathComponent("ProviderConfiguration.json")
        }
        let fm = FileManager.default
        let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "osaurus"
        return supportDir.appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("ProviderConfiguration.json")
    }

    private static func ensureDirectoryExists(_ url: URL) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

